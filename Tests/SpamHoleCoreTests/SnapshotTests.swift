import XCTest
import CSQLite
@testable import SpamHoleCore

final class SnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_985_600)
    private let number = "+12025550100"
    private func source(id: String = "publisher", family: String = "origin",
                        trusted: Bool = true) -> SourceDefinition {
        .init(id: id, name: "Test publisher", url: URL(string: "https://example.com/feed")!, format: .evidenceJSON,
              channels: [.call], sourceFamilyID: family,
              reviewedTrust: trusted ? .init(familyWeight: 1) : nil)
    }
    private func record(id: String = "a", sourceID: String = "publisher", channel: CommunicationChannel = .call,
                        identifier: String? = nil, age: Double = 0, confirmed: Bool = false) -> EvidenceRecord {
        .init(id: id, sourceID: sourceID, sourceFamilyID: "untrusted-feed-family", numberE164: identifier ?? number,
              channel: channel, observedAt: now.addingTimeInterval(-age * 86_400), reportedAt: now,
              publisherWatermark: now, confirmationGrade: confirmed ? 1 : 0,
              confirmationMethod: confirmed ? "reviewed-origin" : nil,
              confirmationExpiresAt: confirmed ? now.addingTimeInterval(2 * 86_400) : nil,
              confirmationReviewedAt: confirmed ? now : nil)
    }
    private func build(_ evidence: [EvidenceRecord] = [], sources: [SourceDefinition] = [], rules: [PersonalRule] = [],
                       settings: AppSettings = .init(), contacts: Set<String> = [], previous: ProtectionSnapshot? = nil) throws -> ProtectionSnapshot {
        try SnapshotBuilder().build(evidence: evidence, sources: sources, rules: rules, settings: settings,
                                    protectedContacts: contacts, previous: previous, now: now)
    }
    func testAllowManualBlockContactsAndFeedPrecedence() throws {
        let block = PersonalRule(identifier: number, action: .block)
        let snapshot = try build(rules: [block], settings: .init(contactProtection: true), contacts: [number])
        XCTAssertEqual(snapshot.callBlocking, [12025550100], "Manual block overrides contact protection")
        let allow = PersonalRule(identifier: number, action: .allow)
        XCTAssertTrue(try build(rules: [block, allow]).callBlocking.isEmpty)
        let reports = (0..<5).map { record(id: "\($0)") }
        XCTAssertFalse(try build(reports, sources: [source()]).callIdentification.isEmpty)
        XCTAssertTrue(try build(reports, sources: [source()], rules: [allow]).callIdentification.isEmpty)
        XCTAssertTrue(try build(reports, sources: [source()], settings: .init(contactProtection: true), contacts: [number]).callIdentification.isEmpty)
    }
    func testMirrorsDoNotCorroborateAndFeedFamiliesCannotPromoteThemselves() throws {
        let records = (0..<7).flatMap { day in
            (0..<5).map { record(id: "\(day)-\($0)", age: Double(day)) }
        }
        let original = try build(records, sources: [source()])
        var mirrored = records.map { record -> EvidenceRecord in
            var value = record; value.sourceID = "mirror"; value.sourceFamilyID = "pretended-independent"; return value
        }
        mirrored.append(contentsOf: records)
        let duplicate = try build(mirrored, sources: [source(), source(id: "mirror")])
        XCTAssertEqual(original.assessments.first?.result, duplicate.assessments.first?.result)
        XCTAssertEqual(original.assessments.first?.result.evidence, 25)
        XCTAssertEqual(original.callIdentification.first?.label, "Many spam reports")
        XCTAssertTrue(try build(records, sources: [source(trusted: false)]).callIdentification.isEmpty)
    }
    func testUntrustedGradeCannotAuthorizeCallBlocking() throws {
        let records = (0..<7).flatMap { day in (0..<5).map { record(id: "\(day)-\($0)", age: Double(day), confirmed: true) } }
        let snapshot = try build(records, sources: [source()])
        XCTAssertTrue(snapshot.callBlocking.isEmpty)
        XCTAssertEqual(snapshot.assessments.first?.result.confirmation, 0)

    }
    func testBurstUncertaintyUsesRawDeduplicatedObservedDates() throws {
        let concentrated = (0..<100).map { record(id: "\($0)") }
        let assessment = try XCTUnwrap(build(concentrated, sources: [source()]).assessments.first)
        XCTAssertEqual(assessment.result.uncertaintyPenalty, 0.5)
        XCTAssertEqual(assessment.result.evidence, 5, "Score caps do not hide raw-count concentration")
        let spread = (0..<7).flatMap { day in (0..<5).map { record(id: "\(day)-\($0)", age: Double(day)) } }
        XCTAssertEqual(try build(spread, sources: [source()]).assessments.first?.result.uncertaintyPenalty, 0)
    }
    func testApprovedCallConfirmationExpiresAndRequiresReviewedMethodAndGrade() throws {
        var approved = source()
        approved.reviewedTrust = .init(familyWeight: 1, confirmationAuthority: true,
                                      allowedConfirmationMethods: ["reviewed-origin"], maximumConfirmationGrade: 1)
        let confirmed = record(confirmed: true)
        let snapshot = try build([confirmed], sources: [approved])
        XCTAssertEqual(snapshot.assessments.first?.result.confirmation, 1)
        XCTAssertTrue(snapshot.callBlocking.isEmpty, "Feed confirmation does not enable automatic blocking")
        var expired = confirmed; expired.confirmationReviewedAt = now.addingTimeInterval(-8 * 86_400)
        XCTAssertEqual(try build([expired], sources: [approved]).assessments.first?.result.confirmation, 0)
        expired = confirmed; expired.confirmationExpiresAt = now
        XCTAssertEqual(try build([expired], sources: [approved]).assessments.first?.result.confirmation, 0)
        var unsupported = confirmed; unsupported.confirmationMethod = "publisher-self-claim"
        XCTAssertEqual(try build([unsupported], sources: [approved]).assessments.first?.result.confirmation, 0)
        approved.reviewedTrust?.maximumConfirmationGrade = 0.8
        XCTAssertEqual(try build([confirmed], sources: [approved]).assessments.first?.result.confirmation, 0)
    }
    func testRetractionsCallbackEvidenceSourceRemovalAndOwnershipResetRemoveEntries() throws {
        var approved = source()
        approved.reviewedTrust = .init(familyWeight: 1, confirmationAuthority: true)
        let reports = (0..<5).map { record(id: "\($0)", age: 1) }
        XCTAssertFalse(try build(reports, sources: [approved]).callIdentification.isEmpty)
        var boundary = record(id: "reset"); boundary.assignmentBoundaryAt = now
        XCTAssertTrue(try build(reports + [boundary], sources: [approved]).callIdentification.isEmpty)
        let retracted = reports.map { item -> EvidenceRecord in var value = item; value.retractedAt = now; return value }
        XCTAssertTrue(try build(retracted, sources: [approved]).callIdentification.isEmpty)
        let callbacks = reports.map { item -> EvidenceRecord in var value = item; value.numberRole = .callback; return value }
        XCTAssertTrue(try build(callbacks, sources: [approved]).callIdentification.isEmpty)
        XCTAssertTrue(try build(reports, sources: []).callIdentification.isEmpty)
    }
    func testHysteresisDoesNotDelayStalenessOrAllowRules() throws {
        let fresh = (0..<4).map { record(id: "\($0)") }
        let previous = try build(fresh, sources: [source()])
        XCTAssertEqual(previous.callIdentification.count, 1)
        let aged = (0..<4).map { record(id: "\($0)", age: 3) }
        XCTAssertTrue(try build(aged, sources: [source()]).callIdentification.isEmpty)
        XCTAssertEqual(try build(aged, sources: [source()], previous: previous).callIdentification.count, 1)
        XCTAssertTrue(try build(aged, sources: [source()], rules: [.init(identifier: number, action: .allow)], previous: previous).callIdentification.isEmpty)
        let stale = aged.map { item -> EvidenceRecord in var value = item; value.publisherWatermark = now.addingTimeInterval(-15 * 86_400); return value }
        XCTAssertTrue(try build(stale, sources: [source()], previous: previous).callIdentification.isEmpty)
    }
    func testSnapshotAtomicPublicationCompactExportsAndPinnedGeneration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = SnapshotFiles(rootURL: directory)
        XCTAssertThrowsError(try files.loadCurrent())
        let snapshot = try build(rules: [.init(identifier: number, action: .block)])
        try files.publish(snapshot: snapshot)
        XCTAssertEqual(try files.loadCurrent().metadata.id, snapshot.metadata.id)
        let reader = try files.callDirectoryReader()
        var numbers: [Int64] = []
        try reader.streamBlocking { numbers.append($0) }
        XCTAssertEqual(numbers, [12025550100])
        try reader.streamIdentification { _ in XCTFail("Unexpected identification entry") }
        XCTAssertThrowsError(try files.publish(snapshot: snapshot), "Published generation payloads are immutable")
        let next = try build()
        try files.publish(snapshot: next)
        XCTAssertEqual(try files.loadCurrent().metadata.id, next.metadata.id)
        numbers = []
        try reader.streamBlocking { numbers.append($0) }
        XCTAssertEqual(numbers, [12025550100], "Reader stays pinned when current generation changes")
        let receipt = CallInstallationReceipt(generationID: snapshot.metadata.id, installedAt: now, identificationCount: 0, blockingCount: 1)
        try files.writeInstallationReceipt(receipt)
        XCTAssertEqual(try files.loadInstallationReceipt(), receipt)
    }
    func testMalformedStreamingPayloadFailsClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = SnapshotFiles(rootURL: directory)
        let snapshot = try build(rules: [.init(identifier: number, action: .block)])
        try files.publish(snapshot: snapshot)
        let binary = directory.appendingPathComponent("generations/\(snapshot.metadata.id.uuidString)/call-blocking.bin")
        let handle = try FileHandle(forWritingTo: binary)
        try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        XCTAssertThrowsError(try files.callDirectoryReader().streamBlocking { _ in })
        try Data([1, 2, 3]).write(to: binary)
        XCTAssertThrowsError(try files.callDirectoryReader().streamBlocking { _ in })
        try Data("{\"schemaVersion\":1,\"generationID\":\"../../outside\"}".utf8).write(to: directory.appendingPathComponent("current.json"))
        XCTAssertThrowsError(try files.loadCurrent())
    }
    func testGenerationRetentionProtectsInstalledAndPinnedReaders() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = SnapshotFiles(rootURL: directory)
        let first = try build(rules: [.init(identifier: number, action: .block)])
        try files.publish(snapshot: first)
        let pinnedFirst = try files.callDirectoryReader()
        let second = try build(rules: [.init(identifier: "+14255550100", action: .block)])
        try files.publish(snapshot: second)
        let pinnedSecond = try files.callDirectoryReader()
        try files.writeInstallationReceipt(.init(generationID: first.metadata.id, installedAt: now,
            identificationCount: 0, blockingCount: 1))
        let third = try build(); try files.publish(snapshot: third)
        let fourth = try build(); try files.publish(snapshot: fourth)
        let fifth = try build(); try files.publish(snapshot: fifth)
        let generationURLs = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("generations"), includingPropertiesForKeys: nil)
        XCTAssertEqual(Set(generationURLs.map(\.lastPathComponent)), Set([first, third, fourth, fifth].map { $0.metadata.id.uuidString }))
        XCTAssertEqual(try files.loadCurrent().metadata.id, fifth.metadata.id)
        var firstNumbers: [Int64] = []
        try pinnedFirst.streamBlocking { firstNumbers.append($0) }
        XCTAssertEqual(firstNumbers, [12025550100])
        var secondNumbers: [Int64] = []
        try pinnedSecond.streamBlocking { secondNumbers.append($0) }
        XCTAssertEqual(secondNumbers, [14255550100], "Pinned descriptors survive pruning their generation directory")
        try pinnedSecond.streamIdentification { _ in XCTFail("Unexpected identification entry") }
    }
    func testPersonalStateRestoreCommitsRulesAndSettingsTogether() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EvidenceStore(url: directory.appendingPathComponent("store.sqlite"))
        try store.saveRule(.init(id: "old", identifier: number, action: .block))
        try store.setSetting(AppSettings(policy: .conservative), forKey: "app-settings")
        try store.setSetting(true, forKey: "onboarding-complete")
        let replacement = PersonalRule(id: "new", identifier: "+14255550100", channel: .call, action: .allow, createdAt: now)
        let settings = AppSettings(policy: .aggressive, cadence: .weekly, contactProtection: true)
        try store.restorePersonalState(rules: [replacement], settings: settings)
        XCTAssertEqual(try store.rules(), [replacement])
        XCTAssertEqual(try store.setting(forKey: "app-settings", as: AppSettings.self), settings)
        XCTAssertEqual(try store.setting(forKey: "onboarding-complete", as: Bool.self), true)
        XCTAssertThrowsError(try store.restorePersonalState(rules: [replacement, replacement], settings: .init()))
        XCTAssertEqual(try store.rules(), [replacement])
        XCTAssertEqual(try store.setting(forKey: "app-settings", as: AppSettings.self), settings)
    }
    func testPersonalStateRestoreRollsBackRulesWhenSettingsWriteFails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("store.sqlite")
        let store = try EvidenceStore(url: databaseURL)
        let originalRule = PersonalRule(id: "old", identifier: number, action: .block, createdAt: now)
        let originalSettings = AppSettings(policy: .conservative, cadence: .manual)
        try store.saveRule(originalRule)
        try store.setSetting(originalSettings, forKey: "app-settings")
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        defer { if let connection { sqlite3_close(connection) } }
        // Fail the settings write after rule deletion/insertion to prove SQL transaction rollback.
        let trigger = "CREATE TRIGGER reject_restore BEFORE INSERT ON settings WHEN NEW.key = 'app-settings' BEGIN SELECT RAISE(ABORT, 'test-failure'); END"
        XCTAssertEqual(sqlite3_exec(connection, trigger, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try store.restorePersonalState(rules: [.init(id: "new", identifier: "+14255550100", channel: .call, action: .allow)],
                                                           settings: .init(policy: .aggressive)))
        XCTAssertEqual(try store.rules(), [originalRule])
        XCTAssertEqual(try store.setting(forKey: "app-settings", as: AppSettings.self), originalSettings)
    }
    func testBoundedCallExportStreamsInitialCapacityWithoutAssessments() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entries = (0..<250_000).map { CallIdentificationEntry(number: 12025550000 + Int64($0), label: "Reported unwanted") }
        let blocks = (0..<25_000).map { 14255550000 + Int64($0) }
        let snapshot = ProtectionSnapshot(metadata: .init(createdAt: now, callIdentificationCount: entries.count,
            callBlockCount: blocks.count, policy: .balanced), callIdentification: entries, callBlocking: blocks)
        let files = SnapshotFiles(rootURL: directory)
        try files.publish(snapshot: snapshot)
        var count = 0
        try files.callDirectoryReader().streamIdentification { _ in count += 1 }
        XCTAssertEqual(count, entries.count)
        var blockCount = 0
        try files.callDirectoryReader().streamBlocking { _ in blockCount += 1 }
        XCTAssertEqual(blockCount, blocks.count)
    }
}
