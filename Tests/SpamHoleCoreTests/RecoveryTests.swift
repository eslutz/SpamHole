import Foundation
import XCTest
import CSQLite
@testable import SpamHoleCore

final class RecoveryTests: XCTestCase, @unchecked Sendable {
    private let now = Date(timeIntervalSince1970: 1_791_072_000)

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testInterruptedOrMalformedLaterShardRetainsCompletePreviousImportAfterReopen() async throws {
        for cancel in [true, false] {
            let root = temporaryDirectory()
            let databaseURL = root.appendingPathComponent("evidence.sqlite")
            let store = try EvidenceStore(url: databaseURL)
            let source = SourceCatalog.builtIns[0]
            let old = EvidenceRecord(id: "old", sourceID: source.id, sourceFamilyID: source.sourceFamilyID,
                numberE164: "+12025550100", channel: .call, observedAt: now.addingTimeInterval(-86400),
                reportedAt: now.addingTimeInterval(-86400), publisherWatermark: now.addingTimeInterval(-86400))
            let previous = SourceState(sourceID: source.id, lastSuccessAt: now.addingTimeInterval(-86400),
                publisherWatermark: old.publisherWatermark, etag: "previous", recordCount: 1)
            try store.replaceEvidence([old], source: source, state: previous)
            let firstURL = URL(string: "https://www.ftc.gov/first.csv")!
            let secondURL = URL(string: "https://www.ftc.gov/second.csv")!
            let validCSV = Data("Company_Phone_Number,Created_Date,Violation_Date\n2025550101,2026-10-04,2026-10-04\n".utf8)
            let transport = RecoveryTransport(responses: [
                .init(data: Data("<a href='/first.csv'>First</a><a href='/second.csv'>Second</a>".utf8), statusCode: 200, finalURL: source.url),
                .init(data: validCSV, statusCode: 200, finalURL: firstURL),
                .init(data: cancel ? validCSV : Data("\"unterminated".utf8), statusCode: 200, finalURL: secondURL)
            ], cancelOnFetch: cancel ? 3 : nil)
            let downloader = SourceDownloader(store: store, transport: transport)
            let task = Task { try await downloader.refresh(source: source, now: now) }
            do { _ = try await task.value; XCTFail("Incomplete multi-file import succeeded") }
            catch {
                if cancel { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertTrue(error is SourceImportError) }
            }
            let fetchCount = await transport.fetchCount
            XCTAssertEqual(fetchCount, 3, "Failure follows a successfully parsed first shard")
            let reopened = try EvidenceStore(url: databaseURL)
            XCTAssertEqual(try reopened.evidence(), [old])
            let state = try XCTUnwrap(reopened.sourceState(id: source.id))
            XCTAssertEqual(state.lastSuccessAt, previous.lastSuccessAt)
            XCTAssertEqual(state.publisherWatermark, previous.publisherWatermark)
            XCTAssertEqual(state.etag, previous.etag)
            XCTAssertEqual(state.recordCount, 1)
            XCTAssertEqual(state.lastAttemptAt, now)
            XCTAssertNotNil(state.error)
        }
    }

    func testImportInsertionFailureRollsBackDeletionAndSourceSuccessStateAfterReopen() throws {
        let databaseURL = temporaryDirectory().appendingPathComponent("evidence.sqlite")
        let store = try EvidenceStore(url: databaseURL)
        let source = SourceDefinition(id: "synthetic", name: "Synthetic", url: URL(string: "https://example.org/feed")!,
            format: .evidenceJSON, sourceFamilyID: "synthetic")
        let original = EvidenceRecord(id: "original", sourceID: source.id, sourceFamilyID: source.id,
            numberE164: "+12025550100", channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now)
        let previous = SourceState(sourceID: source.id, lastSuccessAt: now, publisherWatermark: now, etag: "old", recordCount: 1)
        try store.replaceEvidence([original], source: source, state: previous)
        let persistedPrevious = try store.sourceState(id: source.id)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &connection), SQLITE_OK)
        defer { if let connection { sqlite3_close(connection) } }
        // Abort after the old rows were deleted and the first new row inserted.
        let trigger = "CREATE TRIGGER reject_import BEFORE INSERT ON evidence WHEN NEW.record_id = 'reject' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END"
        XCTAssertEqual(sqlite3_exec(connection, trigger, nil, nil, nil), SQLITE_OK)
        var first = original; first.id = "first"; first.numberE164 = "+12025550101"
        var second = first; second.id = "reject"
        var replacementSource = source; replacementSource.name = "Replacement"
        XCTAssertThrowsError(try store.replaceEvidence([first, second], source: replacementSource,
            state: .init(sourceID: source.id, lastSuccessAt: now.addingTimeInterval(60), etag: "new", recordCount: 2)))
        let reopened = try EvidenceStore(url: databaseURL)
        XCTAssertEqual(try reopened.evidence(), [original])
        XCTAssertEqual(try reopened.sources(), [SourceCatalog.canonicalize(source)])
        XCTAssertEqual(try reopened.sourceState(id: source.id), persistedPrevious)
    }

    func testMissingOrCorruptCurrentPointerCannotLoadCallProtection() throws {
        for corrupt in [false, true] {
            let root = temporaryDirectory()
            let files = SnapshotFiles(rootURL: root)
            let snapshot = try SnapshotBuilder().build(evidence: [], sources: [],
                rules: [.init(identifier: "+12025550100", action: .block)], settings: .init(), now: now)
            try files.publish(snapshot: snapshot)
            let pointerURL = root.appendingPathComponent("current.json")
            if corrupt { try Data("broken".utf8).write(to: pointerURL) }
            else { try FileManager.default.removeItem(at: pointerURL) }
            XCTAssertThrowsError(try files.loadCurrent())
            XCTAssertThrowsError(try files.callDirectoryReader())
        }
    }

    func testMissingCallExportOrCorruptMetadataCannotReplaceInstalledReceipt() throws {
        for fault in ["missing-blocking", "missing-identification", "corrupt-metadata", "wrong-generation"] {
            let root = temporaryDirectory()
            let files = SnapshotFiles(rootURL: root)
            let snapshot = try SnapshotBuilder().build(evidence: [], sources: [],
                rules: [.init(identifier: "+12025550100", action: .block)], settings: .init(), now: now)
            try files.publish(snapshot: snapshot)
            let receipt = CallInstallationReceipt(generationID: UUID(), installedAt: now.addingTimeInterval(-60),
                identificationCount: 0, blockingCount: 0)
            try files.writeInstallationReceipt(receipt)
            let generationURL = root.appendingPathComponent("generations/\(snapshot.metadata.id.uuidString)")
            switch fault {
            case "missing-blocking": try FileManager.default.removeItem(at: generationURL.appendingPathComponent("call-blocking.bin"))
            case "missing-identification": try FileManager.default.removeItem(at: generationURL.appendingPathComponent("call-identification.bin"))
            case "corrupt-metadata": try Data("broken".utf8).write(to: generationURL.appendingPathComponent("metadata.json"))
            default:
                var metadata = snapshot.metadata; metadata.id = UUID()
                let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                try encoder.encode(metadata).write(to: generationURL.appendingPathComponent("metadata.json"))
            }
            XCTAssertThrowsError(try files.callDirectoryReader(), fault)
            XCTAssertEqual(try files.loadInstallationReceipt(), receipt, fault)
        }
    }
}

private actor RecoveryTransport: SourceHTTPTransport {
    private var responses: [SourceHTTPResponse]
    private let cancelOnFetch: Int?
    private(set) var fetchCount = 0
    init(responses: [SourceHTTPResponse], cancelOnFetch: Int?) {
        self.responses = responses; self.cancelOnFetch = cancelOnFetch
    }
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> SourceHTTPResponse {
        fetchCount += 1
        if fetchCount == cancelOnFetch { withUnsafeCurrentTask { $0?.cancel() } }
        return responses.removeFirst()
    }
}
