import Foundation
import XCTest
import CSQLite
@testable import SpamHoleCore

final class CallOnlyTests: XCTestCase, @unchecked Sendable {
    private let now = Date(timeIntervalSince1970: 1_791_072_000)
    private func temporaryDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
    private func source(_ id: String, channels: [CommunicationChannel] = [.call], enabled: Bool = true,
                        format: SourceFormat = .evidenceJSON) -> SourceDefinition {
        .init(id: id, name: id, url: URL(string: "https://example.org/\(id)")!, format: format,
            enabled: enabled, channels: channels, sourceFamilyID: id)
    }
    private func record(_ id: String, source: SourceDefinition, channel: CommunicationChannel = .call,
                        number: String = "+12025550100") -> EvidenceRecord {
        .init(id: id, sourceID: source.id, sourceFamilyID: source.id, numberE164: number,
            channel: channel, observedAt: now, reportedAt: now, publisherWatermark: now)
    }

    func testNewRulesSourcesAndImportsRejectLegacyChannelsAndTextIdentifiers() throws {
        let store = try EvidenceStore(url: temporaryDirectory().appendingPathComponent("store.sqlite"))
        let calls = source("calls")
        try store.saveSource(calls)
        let existing = PersonalRule(identifier: "+12025550100", action: .allow)
        try store.saveRule(existing)
        for channel in [CommunicationChannel.sms, .both] {
            XCTAssertThrowsError(try store.saveRule(.init(identifier: "+14255550100", channel: channel, action: .block)))
            XCTAssertThrowsError(try store.saveSource(source("legacy", channels: [channel])))
            XCTAssertThrowsError(try SourceCatalog.custom(name: "Legacy", url: calls.url, format: .evidenceJSON, channels: [channel]))
            XCTAssertThrowsError(try store.replaceEvidence([record("unsupported", source: calls, channel: channel)],
                source: calls, state: .init(sourceID: calls.id)))
            let feed = Data("""
                {"schemaVersion":1,"publisherWatermark":"2026-10-04T00:00:00Z","records":[
                {"id":"a","identifier":"2025550100","channel":"\(channel.rawValue)","reportedAt":"2026-10-04T00:00:00Z"}]}
                """.utf8)
            XCTAssertThrowsError(try SourceAdapters.parse(data: feed, source: calls, now: now))
            XCTAssertThrowsError(try SnapshotBuilder().build(evidence: [record("unsupported", source: calls, channel: channel)],
                sources: [calls], rules: [], settings: .init(), now: now))
        }
        for identifier in ["12345", "BANKALERT"] {
            XCTAssertThrowsError(try store.saveRule(.init(identifier: identifier, action: .block)))
            XCTAssertThrowsError(try store.replaceEvidence([record("invalid", source: calls, number: identifier)],
                source: calls, state: .init(sourceID: calls.id)))
        }
        let retired = source("retired", format: .fccJSON)
        XCTAssertThrowsError(try store.saveSource(retired))
        XCTAssertThrowsError(try SourceAdapters.parse(data: Data("[]".utf8), source: retired, now: now))
        XCTAssertEqual(try store.rules(), [existing])
        XCTAssertEqual(try store.sources(), [calls])
        XCTAssertTrue(try store.evidence().isEmpty)
        XCTAssertEqual(CommunicationChannel.allCases, [.call])
        XCTAssertFalse(SourceFormat.allCases.contains(.fccJSON))
        XCTAssertEqual(SourceCatalog.builtIns.count, 1)
        XCTAssertEqual(SourceCatalog.builtIns.first?.channels, [.call])
    }

    func testRetiredSourceCannotStartNetworkRefresh() async throws {
        let store = try EvidenceStore(url: temporaryDirectory().appendingPathComponent("store.sqlite"))
        let transport = CountingCallTransport()
        let downloader = SourceDownloader(store: store, transport: transport)
        for retired in [source("texts", channels: [.sms]), source("mixed", channels: [.both]),
                        source("fcc", format: .fccJSON)] {
            do { try await downloader.refresh(source: retired, now: now); XCTFail("Retired source refreshed") }
            catch { XCTAssertTrue(error is SourceImportError) }
        }
        let count = await transport.fetchCount
        XCTAssertEqual(count, 0)
    }

    func testLegacyMigrationArchivesTextDataAndRetainsCallPortionsOnRepeatedOpen() throws {
        let databaseURL = temporaryDirectory().appendingPathComponent("legacy.sqlite")
        let fixture = try LegacyDatabase(url: databaseURL)
        let calls = source("calls")
        let mixed = source("mixed", channels: [.both], enabled: false)
        let texts = source("texts", channels: [.sms])
        let fcc = source("fcc", channels: [.sms], format: .fccJSON)
        for item in [calls, mixed, texts, fcc] { try fixture.insertSource(item) }
        let callEvidence = record("call", source: calls)
        let textEvidence = record("text-under-call", source: calls, channel: .sms, number: "+14255550100")
        let mixedEvidence = record("mixed", source: mixed, channel: .both, number: "+16505550100")
        let mixedShortCode = record("mixed-short", source: mixed, channel: .both, number: "12345")
        let textOnly = record("text", source: texts, channel: .sms, number: "+12025550101")
        let fccEvidence = record("fcc", source: fcc, channel: .sms, number: "+12025550102")
        for item in [callEvidence, textEvidence, mixedEvidence, mixedShortCode, textOnly, fccEvidence] {
            try fixture.insertEvidence(item)
        }
        let callState = SourceState(sourceID: calls.id, lastAttemptAt: now, lastSuccessAt: now,
            publisherWatermark: now, etag: "call-etag", lastModified: "call-modified", recordCount: 2, error: "old-error")
        let mixedState = SourceState(sourceID: mixed.id, lastAttemptAt: now, lastSuccessAt: now,
            publisherWatermark: now, etag: "mixed-etag", recordCount: 2)
        try fixture.insertState(callState); try fixture.insertState(mixedState)
        try fixture.insertState(.init(sourceID: texts.id, lastSuccessAt: now, recordCount: 1))
        try fixture.insertState(.init(sourceID: fcc.id, lastSuccessAt: now, recordCount: 1))
        let callRule = PersonalRule(id: "call-rule", identifier: "+12025550100", action: .block, createdAt: now, note: "Call note")
        let bothRule = PersonalRule(id: "both-rule", identifier: "+14255550100", channel: .both, action: .allow, createdAt: now, note: "Mixed note")
        let textRule = PersonalRule(id: "text-rule", identifier: "+16505550100", channel: .sms, action: .block, createdAt: now, note: "Dormant text note")
        let shortRule = PersonalRule(id: "short-rule", identifier: "12345", channel: .both, action: .block, createdAt: now)
        for rule in [callRule, bothRule, textRule, shortRule] { try fixture.insertRule(rule) }
        let originalTextRulePayload = try fixture.rulePayload(id: textRule.id)
        let originalMixedSourcePayload = try fixture.sourcePayload(id: mixed.id)
        let settings = AppSettings(policy: .conservative, cadence: .weekly, contactProtection: true)
        try fixture.insertSetting(settings, key: "app-settings")

        var retainedBoth = bothRule; retainedBoth.channel = .call
        var retainedMixed = mixedEvidence; retainedMixed.channel = .call
        var expectedCallState = callState; expectedCallState.recordCount = 1
        var expectedMixedState = mixedState; expectedMixedState.recordCount = 1
        for _ in 0..<2 {
            let store = try EvidenceStore(url: databaseURL)
            XCTAssertEqual(try store.sources().map(\.id), [calls.id, mixed.id])
            XCTAssertEqual(try store.sources().first(where: { $0.id == mixed.id })?.enabled, false)
            XCTAssertTrue(try store.sources().allSatisfy { $0.channels == [.call] })
            XCTAssertEqual(try store.evidence(), [callEvidence])
            XCTAssertEqual(Set(try store.evidence(enabledOnly: false).map(\.id)), Set([callEvidence.id, retainedMixed.id]))
            XCTAssertEqual(try store.evidence(enabledOnly: false).first(where: { $0.id == retainedMixed.id }), retainedMixed)
            XCTAssertEqual(try store.rules(), [retainedBoth, callRule])
            XCTAssertEqual(try store.sourceState(id: calls.id), expectedCallState)
            XCTAssertEqual(try store.sourceState(id: mixed.id), expectedMixedState)
            XCTAssertNil(try store.sourceState(id: texts.id))
            XCTAssertNil(try store.sourceState(id: fcc.id))
            XCTAssertEqual(try store.setting(forKey: "app-settings", as: AppSettings.self), settings)
            let snapshot = try SnapshotBuilder().build(evidence: store.evidence(), sources: store.sources(),
                rules: store.rules(), settings: settings, now: now)
            XCTAssertEqual(snapshot.callBlocking, [12025550100])
            XCTAssertFalse(snapshot.assessments.contains { $0.identifier == textEvidence.numberE164 })
            XCTAssertEqual(try fixture.scalar("PRAGMA user_version"), 2)
            XCTAssertEqual(try fixture.scalar("SELECT COUNT(*) FROM legacy_channel_data"), 15)
            // Original bytes remain offline, including text-only data represented by full telephone numbers.
            XCTAssertEqual(try fixture.archived(kind: "rule", key: textRule.id), originalTextRulePayload)
            XCTAssertEqual(try fixture.archived(kind: "source", key: mixed.id), originalMixedSourcePayload)
        }
    }

    func testFailedLegacyMigrationRollsBackActiveAndDormantTablesAndVersion() throws {
        let databaseURL = temporaryDirectory().appendingPathComponent("legacy.sqlite")
        let fixture = try LegacyDatabase(url: databaseURL)
        let calls = source("calls")
        try fixture.insertSource(calls)
        let rule = PersonalRule(id: "mixed", identifier: "+12025550100", channel: .both, action: .allow, createdAt: now)
        try fixture.insertRule(rule)
        try fixture.execute("CREATE TRIGGER interrupt_migration BEFORE UPDATE ON rules BEGIN SELECT RAISE(ABORT, 'synthetic interruption'); END")
        XCTAssertThrowsError(try EvidenceStore(url: databaseURL))
        XCTAssertEqual(try fixture.scalar("PRAGMA user_version"), 1)
        XCTAssertEqual(try fixture.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='legacy_channel_data'"), 0)
        XCTAssertEqual(try fixture.rule(id: rule.id), rule)
        try fixture.execute("DROP TRIGGER interrupt_migration")
        let recovered = try EvidenceStore(url: databaseURL)
        var expected = rule; expected.channel = .call
        XCTAssertEqual(try recovered.rules(), [expected])
        XCTAssertEqual(try fixture.scalar("PRAGMA user_version"), 2)
    }

    func testLegacySnapshotIgnoresTextFieldsAndNewPublicationContainsOnlyCalls() throws {
        let root = temporaryDirectory()
        let files = SnapshotFiles(rootURL: root)
        let snapshot = try SnapshotBuilder().build(evidence: [], sources: [],
            rules: [.init(identifier: "+12025550100", action: .block)], settings: .init(), now: now)
        try files.publish(snapshot: snapshot)
        let generation = root.appendingPathComponent("generations/\(snapshot.metadata.id.uuidString)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: generation.appendingPathComponent("sms.json").path))
        let snapshotURL = generation.appendingPathComponent("snapshot.json")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any])
        var metadata = try XCTUnwrap(legacy["metadata"] as? [String: Any])
        metadata["smsDecisionCount"] = 1; legacy["metadata"] = metadata
        legacy["smsDecisions"] = [["identifier": "+14255550100", "action": "junk", "reason": "Legacy text rule"]]
        try JSONSerialization.data(withJSONObject: legacy).write(to: snapshotURL)
        XCTAssertEqual(try files.loadCurrent(), snapshot)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(files.loadCurrent())) as? [String: Any])
        XCTAssertNil(encoded["smsDecisions"])
        XCTAssertNil((encoded["metadata"] as? [String: Any])?["smsDecisionCount"])
        var blocks: [Int64] = []
        try files.callDirectoryReader().streamBlocking { blocks.append($0) }
        XCTAssertEqual(blocks, [12025550100])
    }
}

private actor CountingCallTransport: SourceHTTPTransport {
    private(set) var fetchCount = 0
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> SourceHTTPResponse {
        fetchCount += 1
        throw SourceImportError.httpStatus(500)
    }
}

/// Writes version 1 synthetic fixtures directly, bypassing new call-only write validation.
private final class LegacyDatabase {
    private var database: OpaquePointer?
    init(url: URL) throws {
        _ = try EvidenceStore(url: url)
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw EvidenceStoreError(message: "Fixture open failed") }
        try execute("DROP TABLE legacy_channel_data")
        try execute("PRAGMA user_version=1")
    }
    deinit { if let database { sqlite3_close(database) } }
    func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw EvidenceStoreError(message: "Fixture SQL failed") }
    }
    private func insert<T: Encodable>(_ sql: String, value: T) throws {
        let bytes = try JSONEncoder().encode(value)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw EvidenceStoreError(message: "Fixture prepare failed") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let bound = bytes.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) }
        guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw EvidenceStoreError(message: "Fixture insert failed") }
    }
    func insertSource(_ source: SourceDefinition) throws {
        try insert("INSERT INTO sources(id,enabled,payload) VALUES('\(source.id)',\(source.enabled ? 1 : 0),?)", value: source)
    }
    func insertEvidence(_ record: EvidenceRecord) throws {
        let day = Int(floor(record.reportedAt.timeIntervalSince1970 / 86400))
        try insert("INSERT INTO evidence(source_id,record_id,family_id,identifier,day,weight,payload) VALUES('\(record.sourceID)','\(record.id)','\(record.sourceFamilyID)','\(record.numberE164)',\(day),1,?)", value: record)
    }
    func insertState(_ state: SourceState) throws { try insert("INSERT INTO source_states(source_id,payload) VALUES('\(state.sourceID)',?)", value: state) }
    func insertRule(_ rule: PersonalRule) throws { try insert("INSERT INTO rules(id,payload) VALUES('\(rule.id)',?)", value: rule) }
    func insertSetting<T: Encodable>(_ value: T, key: String) throws { try insert("INSERT INTO settings(key,payload) VALUES('\(key)',?)", value: value) }
    func scalar(_ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw EvidenceStoreError(message: "Fixture scalar prepare failed") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw EvidenceStoreError(message: "Fixture scalar read failed") }
        return Int(sqlite3_column_int64(statement, 0))
    }
    private func payload(_ sql: String) throws -> Data {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw EvidenceStoreError(message: "Fixture payload prepare failed") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else {
            throw EvidenceStoreError(message: "Fixture payload read failed")
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
    }
    func archived(kind: String, key: String) throws -> Data {
        try payload("SELECT payload FROM legacy_channel_data WHERE kind='\(kind)' AND original_key='\(key)'")
    }
    func rulePayload(id: String) throws -> Data { try payload("SELECT payload FROM rules WHERE id='\(id)'") }
    func sourcePayload(id: String) throws -> Data { try payload("SELECT payload FROM sources WHERE id='\(id)'") }
    func rule(id: String) throws -> PersonalRule { try JSONDecoder().decode(PersonalRule.self, from: rulePayload(id: id)) }
}
