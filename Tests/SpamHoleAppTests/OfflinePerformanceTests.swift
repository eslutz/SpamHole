import XCTest
import SpamHoleCore
import os
@testable import SpamHole

/// Opt-in through the SpamHolePerformance scheme. No network, Contacts, or extension installation.
final class OfflinePerformanceTests: XCTestCase {
    private struct Fixture: Sendable {
        let pipeline: ProtectionPipeline
        let prepared: PreparedProtectionSnapshot
    }

    private func fixture(_ count: Int) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpamHole-Performance-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let store = try EvidenceStore(url: root.appendingPathComponent("evidence.sqlite"))
        let files = SnapshotFiles(rootURL: root.appendingPathComponent("Protection"))
        let source = SourceDefinition(id: "performance", name: "Synthetic offline fixture",
            url: URL(string: "https://example.com/never-requested")!, format: .evidenceJSON,
            channels: [.call], sourceFamilyID: "performance")
        let now = Date(timeIntervalSince1970: 1_790_985_600)
        let records = (0..<count).map { index in
            EvidenceRecord(id: String(index), sourceID: source.id, sourceFamilyID: source.sourceFamilyID,
                numberE164: "+4420" + String(format: "%08d", index), channel: .call,
                observedAt: now, reportedAt: now, publisherWatermark: now,
                identificationLabel: "Synthetic fixture")
        }
        try store.replaceEvidence(records, source: source,
            state: SourceState(sourceID: source.id, recordCount: count))
        let snapshot = try SnapshotBuilder().build(evidence: records, sources: [source], rules: [],
            settings: AppSettings(), protectedContacts: [], previous: nil, now: now)
        try files.publish(snapshot: snapshot)
        return Fixture(pipeline: ProtectionPipeline(store: store, files: files),
            prepared: PreparedProtectionSnapshot(snapshot: snapshot))
    }

    private func profile(_ count: Int, operation: StaticString,
                         work: @escaping @Sendable (Fixture) async throws -> Void) throws {
        let fixture = try fixture(count) // Setup intentionally excluded from metrics.
        XCTAssertEqual(fixture.prepared.assessmentPositions.count, count)
        let context = XCTAttachment(string: "Synthetic entries=\(count); operation=\(operation); " +
            "UUID temporary root; no production container, downloads, Contacts or installation; " +
            "3 measured repetitions plus XCTest warm-up; actor task completion included.")
        context.name = "Performance fixture context"; context.lifetime = .keepAlways; add(context)
        let options = XCTMeasureOptions(); options.iterationCount = 3
        let signposter = OSSignposter(subsystem: "dev.ericslutz.SpamHole.Performance", category: "OfflineFixture")
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            let completed = expectation(description: "Measured operation completes")
            Task.detached {
                let interval = signposter.beginInterval(operation)
                defer { signposter.endInterval(operation, interval); completed.fulfill() }
                do { try await work(fixture) }
                catch { XCTFail("Performance operation failed: \(error)") }
            }
            wait(for: [completed], timeout: 180)
        }
    }

    private func load(_ count: Int) throws {
        try profile(count, operation: "SavedSnapshotLoadAndIndex") { fixture in
            let loaded = try await fixture.pipeline.loadSavedSnapshot()
            XCTAssertEqual(loaded?.assessmentPositions.count, count)
        }
    }
    private func rebuild(_ count: Int) throws {
        try profile(count, operation: "RebuildAndPublish") { fixture in
            let result = try await fixture.pipeline.rebuild(settings: AppSettings(), protectedContacts: [],
                now: Date(timeIntervalSince1970: 1_790_985_600))
            XCTAssertEqual(result.assessmentPositions.count, count)
        }
    }
    private func lookup(_ count: Int) throws {
        try profile(count, operation: "IndexedLookupBatch") { fixture in
            let last = try XCTUnwrap(fixture.prepared.snapshot.assessments.last)
            var hits = 0
            var misses = 0
            for _ in 0..<10_000 {
                if fixture.prepared.assessment(for: last.identifier) != nil { hits += 1 }
                if fixture.prepared.assessment(for: "missing") == nil { misses += 1 }
            }
            XCTAssertEqual(hits, 10_000)
            XCTAssertEqual(misses, 10_000)
        }
    }
    func testSavedSnapshotLoad50k() throws { try load(50_000) }
    func testSavedSnapshotLoad250k() throws { try load(250_000) }
    func testRebuild50k() throws { try rebuild(50_000) }
    func testRebuild250k() throws { try rebuild(250_000) }
    func testLookup50k() throws { try lookup(50_000) }
    func testLookup250k() throws { try lookup(250_000) }
}
