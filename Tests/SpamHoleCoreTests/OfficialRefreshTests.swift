import XCTest
@testable import SpamHoleCore

final class OfficialRefreshTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_791_158_400)
    func store(_ id: String) throws -> (EvidenceStore, SourceDefinition, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try EvidenceStore(url: root.appendingPathComponent("test.sqlite"))
        var source = try XCTUnwrap(SourceCatalog.builtIns.first { $0.id == id }); source.enabled = true
        try store.saveSource(source)
        return (store, source, root)
    }
    func testFCCCompletesNormalizedImportAndChangingMetadataPreservesPreviousData() async throws {
        let (store, source, root) = try store("fcc-calls")
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = Data("{\"rowsUpdatedAt\":1791158400}".utf8)
        let rows = Data(#"[{"id":"one","issue_date":"2026-10-04T00:00:00.000","caller_id_number":"2025550100","type_of_call_or_messge":"Live Voice"}]"#.utf8)
        let downloader = SourceDownloader(store: store, transport: QueueTransport([metadata, rows, metadata]))
        try await downloader.refresh(source: source, now: now)
        XCTAssertEqual(try store.evidence().map(\.numberE164), ["+12025550100"])
        let revision = try store.sourceState(id: source.id)?.importRevision
        let changed = Data("{\"rowsUpdatedAt\":1791158460}".utf8)
        let failing = SourceDownloader(store: store, transport: QueueTransport([metadata, Data("[]".utf8), changed]))
        do { try await failing.refresh(source: source, now: now.addingTimeInterval(120)); XCTFail("Changing dataset replaced previous data") }
        catch { }
        XCTAssertEqual(try store.evidence().count, 1)
        XCTAssertEqual(try store.sourceState(id: source.id)?.importRevision, revision)
    }
    func testPhoneBlockAccessGateRejectsUnapprovedActivation() async throws {
        let (store, source, root) = try store("phoneblock")
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = SourceDownloader(store: store, transport: QueueTransport([]))
        do { try await downloader.refresh(source: source, now: now, headers: ["Authorization":"Bearer synthetic"]); XCTFail("Unapproved access accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("clearance")) }
        XCTAssertTrue(try store.evidence().isEmpty)
    }
    func testPhoneBlockDeltasRemoveRecordsAndCommitTheirVersion() async throws {
        let (store, source, root) = try store("phoneblock")
        defer { try? FileManager.default.removeItem(at: root) }
        let full = Data(#"{"version":1,"numbers":[{"phone":"+12025550100","rating":"G_FRAUD","votes":10,"lastActivity":1791158400000},{"phone":"+12025550101","rating":"G_FRAUD","votes":4,"lastActivity":1791158400000}]}"#.utf8)
        let delta = Data(#"{"version":2,"numbers":[{"phone":"+12025550100","rating":"A_LEGITIMATE","votes":0},{"phone":"+12025550102","rating":"G_FRAUD","votes":20,"lastActivity":1791158400000}]}"#.utf8)
        let downloader = SourceDownloader(store: store, transport: QueueTransport([full,delta]), phoneBlockAccessApproved: true)
        try await downloader.refresh(source: source, now: now, headers: ["Authorization":"Bearer synthetic"])
        let later = now.addingTimeInterval(90000)
        try await downloader.refresh(source: source, now: later, headers: ["Authorization":"Bearer synthetic"])
        XCTAssertEqual(Set(try store.evidence().map(\.numberE164)), ["+12025550101", "+12025550102"])
        XCTAssertEqual(try store.sourceState(id: source.id)?.publisherVersion, 2)
        do { try await downloader.refresh(source: source, now: later, headers: ["Authorization":"Bearer synthetic"]); XCTFail("Manual refresh bypassed cadence") }
        catch { XCTAssertTrue(error.localizedDescription.contains("due")) }
        XCTAssertEqual(try store.sourceState(id: source.id)?.publisherVersion, 2)
    }
    func testPhoneBlockExcludesUnsupportedCountriesButDoesNotAdvancePastMalformedDeltas() async throws {
        let (store, source, root) = try store("phoneblock")
        defer { try? FileManager.default.removeItem(at: root) }
        let full = Data(#"{"version":1,"numbers":[{"phone":"+12025550100","rating":"G_FRAUD","votes":10,"lastActivity":1791158400000},{"phone":"+5511987654321","rating":"G_FRAUD","votes":10,"lastActivity":1791158400000}]}"#.utf8)
        let bad = Data(#"{"version":2,"numbers":[{"phone":"+12025550100","rating":"NEW_CATEGORY","votes":10,"lastActivity":1791158400000}]}"#.utf8)
        let downloader = SourceDownloader(store: store, transport: QueueTransport([full, bad]), phoneBlockAccessApproved: true)
        try await downloader.refresh(source: source, now: now, headers: ["Authorization":"Bearer synthetic"])
        XCTAssertEqual(try store.evidence().count, 1)
        XCTAssertEqual(try store.sourceState(id: source.id)?.rejectedRecordCount, 1)
        do {
            try await downloader.refresh(source: source, now: now.addingTimeInterval(90000), headers: ["Authorization":"Bearer synthetic"])
            XCTFail("Malformed delta silently advanced the checkpoint")
        } catch { }
        XCTAssertEqual(try store.sourceState(id: source.id)?.publisherVersion, 1)
        XCTAssertEqual(try store.evidence().count, 1)
    }

    func testDelayedConditionalAndReplacementResponsesCannotRestoreAnOlderCheckpoint() async throws {
        for status in [304, 200] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = try EvidenceStore(url: root.appendingPathComponent("test.sqlite"))
            let source = SourceDefinition(id: "synthetic", name: "Synthetic", url: URL(string: "https://example.org/feed")!, format: .evidenceJSON, sourceFamilyID: "synthetic")
            let old = EvidenceRecord(id: "old", sourceID: source.id, sourceFamilyID: source.id,
                numberE164: "+12025550100", channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now)
            try store.replaceEvidence([old], source: source, state: .init(sourceID: source.id, lastSuccessAt: now, publisherWatermark: now, etag: "old"))
            let oldRevision = try store.sourceState(id: source.id)?.importRevision
            let transport = MutationTransport { requestURL in
                var newer = old; newer.id = "new"
                try store.replaceEvidence([newer], source: source, state: .init(sourceID: source.id, lastSuccessAt: old.reportedAt, publisherWatermark: old.publisherWatermark, etag: "new"))
                let data = Data(#"{"schemaVersion":1,"snapshot":true,"publisherWatermark":"2026-10-05T00:00:00Z","records":[]}"#.utf8)
                return SourceHTTPResponse(data: status == 304 ? Data() : data, statusCode: status, finalURL: requestURL)
            }
            let downloader = SourceDownloader(store: store, transport: transport)
            do { try await downloader.refresh(source: source, now: now.addingTimeInterval(60)); XCTFail("Stale response accepted") }
            catch { XCTAssertEqual(error as? SourceImportError, .sourceChanged) }
            XCTAssertNotEqual(try store.sourceState(id: source.id)?.importRevision, oldRevision)
            XCTAssertEqual(try store.sourceState(id: source.id)?.etag, "new")
            XCTAssertEqual(try store.evidence().map(\.id), ["new"])
        }
    }

    func testPhoneBlockCredentialRotationInvalidatesDataWithoutBypassingFullSyncCadence() async throws {
        let (store, source, root) = try store("phoneblock")
        defer { try? FileManager.default.removeItem(at: root) }
        let full = Data(#"{"version":1,"numbers":[{"phone":"+12025550100","rating":"G_FRAUD","votes":10,"lastActivity":1791158400000}]}"#.utf8)
        let downloader = SourceDownloader(store: store, transport: QueueTransport([full]), phoneBlockAccessApproved: true)
        try await downloader.refresh(source: source, now: now, headers: ["Authorization":"Bearer synthetic-one"])
        do { try await downloader.refresh(source: source, now: now.addingTimeInterval(90000), headers: ["Authorization":"Bearer synthetic-two"]); XCTFail("Credential rotation bypassed full-sync cadence") }
        catch { }
        XCTAssertTrue(try store.evidence().isEmpty)
        XCTAssertNil(try store.sourceState(id: source.id)?.publisherVersion)
        XCTAssertEqual(try store.sourceState(id: source.id)?.lastFullAttemptAt, now)
    }
}

private actor QueueTransport: SourceHTTPTransport {
    var payloads: [Data]
    init(_ payloads: [Data]) { self.payloads = payloads }
    func fetch(url: URL, headers: [String:String], maximumBytes: Int) async throws -> SourceHTTPResponse {
        guard !payloads.isEmpty else { throw SourceImportError.httpStatus(500) }
        return SourceHTTPResponse(data: payloads.removeFirst(), statusCode: 200, finalURL: url)
    }
}

private struct MutationTransport: SourceHTTPTransport {
    let mutation: @Sendable (URL) throws -> SourceHTTPResponse
    init(_ mutation: @escaping @Sendable (URL) throws -> SourceHTTPResponse) { self.mutation = mutation }
    func fetch(url: URL, headers: [String:String], maximumBytes: Int) async throws -> SourceHTTPResponse { try mutation(url) }
}
