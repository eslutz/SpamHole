import XCTest
import SpamHoleCore
@testable import SpamHole

@MainActor
final class ProtectionPublicationTests: XCTestCase {
    func testInstallationReceiptWaitsForExtensionAcknowledgement() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SnapshotFiles(rootURL: root.appendingPathComponent("Protection"))
        let pipeline = ProtectionPipeline(store: try EvidenceStore(url: root.appendingPathComponent("evidence.sqlite")), files: files)
        let expected = CallInstallationReceipt(generationID: UUID(), installedAt: Date(), identificationCount: 1, blockingCount: 0)
        let writer = Task {
            try await Task.sleep(for: .milliseconds(100))
            try files.writeInstallationReceipt(expected)
        }
        let receipt = try await pipeline.installationReceipt(matching: expected.generationID)
        try await writer.value
        XCTAssertEqual(receipt?.generationID, expected.generationID)
    }

    func testInstallationReceiptTimeoutPreservesLastGoodGeneration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SnapshotFiles(rootURL: root.appendingPathComponent("Protection"))
        let pipeline = ProtectionPipeline(store: try EvidenceStore(url: root.appendingPathComponent("evidence.sqlite")), files: files)
        let old = CallInstallationReceipt(generationID: UUID(), installedAt: Date(), identificationCount: 1, blockingCount: 0)
        try files.writeInstallationReceipt(old)
        let receipt = try await pipeline.installationReceipt(matching: UUID(), timeout: .milliseconds(100))
        XCTAssertEqual(receipt?.generationID, old.generationID)
        let cancelled = Task { try await pipeline.installationReceipt(matching: UUID()) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled receipt wait must stop") }
        catch is CancellationError { }
    }

    private func model() throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return try AppModel(rootURL: root, testing: true)
    }

    func testHostedApplicationUsesIsolatedTestMode() {
        XCTAssertEqual(BackgroundDelegate.model?.testing, true)
    }

    func testRulesReplaceGenerationAndRetainCoherentLookup() async throws {
        let model = try model()
        try await model.saveRule(raw: "2025550123", action: .block)
        let first = try XCTUnwrap(model.snapshot)
        XCTAssertEqual(first.callBlocking, [1_202_555_0123])
        try await model.saveRule(raw: "2025550123", action: .allow)
        XCTAssertNotEqual(model.snapshot?.metadata.id, first.metadata.id)
        XCTAssertEqual(model.snapshot?.callBlocking, [])
        XCTAssertEqual(model.rules.first?.action, .allow)
        XCTAssertEqual(model.assessmentCount, model.snapshot?.assessments.count)
        XCTAssertNil(model.assessment(for: "missing"))
    }

    func testInvalidPhoneRulePreservesPersonalRulesAndGeneration() async throws {
        let model = try model()
        try await model.saveRule(raw: "2025550123", action: .block)
        let previousRules = model.rules
        let previousSnapshot = model.snapshot
        for invalid in ["54321", "BANK", "202*"] {
            do {
                try await model.saveRule(raw: invalid, action: .allow)
                XCTFail("Incomplete or non-phone input must not become a call rule")
            } catch { }
            XCTAssertEqual(model.rules, previousRules)
            XCTAssertEqual(model.snapshot, previousSnapshot)
        }
    }

    func testCancelledRebuildPreservesLastGoodGeneration() async throws {
        let model = try model()
        try await model.saveRule(raw: "2025550123", action: .allow)
        let before = model.snapshot
        let task = Task { @MainActor in await model.rebuild() }
        task.cancel()
        let succeeded = await task.value
        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.snapshot, before)
        XCTAssertFalse(model.isWorking)
    }

    func testFailedPublicationPreservesLastGoodGeneration() async throws {
        let model = try model()
        try await model.saveRule(raw: "2025550123", action: .allow)
        let before = model.snapshot
        // Replace only this test's generation directory with a file to force a write failure.
        let directory = model.files.rootURL.appendingPathComponent("generations")
        try FileManager.default.removeItem(at: directory)
        try Data("blocked".utf8).write(to: directory)
        let succeeded = await model.rebuild()
        XCTAssertFalse(succeeded)
        XCTAssertEqual(model.snapshot, before)
        XCTAssertNotNil(model.message)
        XCTAssertFalse(model.isWorking)
    }

    func testSavedGenerationReadFailureIsReported() async throws {
        let model = try model()
        try FileManager.default.createDirectory(at: model.files.rootURL, withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: model.files.rootURL.appendingPathComponent("current.json"))
        do {
            _ = try await model.pipeline.loadSavedSnapshot()
            XCTFail("Malformed generation must not appear as an empty database")
        } catch { XCTAssertNotNil(error as Error?) }
    }

    func testGenerationPublicationReplacesVisibleAssessmentIndex() async throws {
        let model = try model()
        let source = SourceDefinition(id: "test", name: "Test", url: URL(string: "https://example.com")!,
            format: .evidenceJSON, sourceFamilyID: "test")
        let now = Date()
        let record = EvidenceRecord(id: "a", sourceID: "test", sourceFamilyID: "test", numberE164: "+12025550123",
            channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now)
        try model.store.replaceEvidence([record], source: source, state: SourceState(sourceID: "test", recordCount: 1))
        let built = await model.rebuild()
        XCTAssertTrue(built)
        XCTAssertEqual(model.assessment(for: record.numberE164)?.identifier, record.numberE164)
        try model.store.replaceEvidence([], source: source, state: SourceState(sourceID: "test"))
        let replaced = await model.rebuild()
        XCTAssertTrue(replaced)
        XCTAssertNil(model.assessment(for: record.numberE164))
        XCTAssertEqual(model.assessmentCount, 0)
    }

    func testLargePreparedIndexFindsLastAndMissingIdentifiers() async throws {
        for count in [50_000, 250_000] {
            let prepared = try await Task.detached {
                let source = SourceDefinition(id: "test", name: "Test", url: URL(string: "https://example.com")!,
                    format: .evidenceJSON, channels: [.call], sourceFamilyID: "test")
                let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
                let records = (0..<count).map { i in
                    EvidenceRecord(id: "\(i)", sourceID: source.id, sourceFamilyID: "test", numberE164: "+4420\(String(format: "%08d", i))",
                        channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now, identificationLabel: "Test listing")
                }
                let value = try SnapshotBuilder().build(evidence: records, sources: [source], rules: [],
                    settings: AppSettings(), protectedContacts: [], previous: nil, now: now)
                return PreparedProtectionSnapshot(snapshot: value)
            }.value
            XCTAssertEqual(prepared.assessmentPositions.count, count)
            let last = try XCTUnwrap(prepared.snapshot.assessments.last)
            XCTAssertEqual(prepared.assessment(for: last.identifier), last)
            XCTAssertNil(prepared.assessment(for: "+19999999999"))

            let model = try model()
            let files = model.files
            let snapshot = prepared.snapshot
            try await Task.detached { try files.publish(snapshot: snapshot) }.value
            let saved = try await model.pipeline.loadSavedSnapshot()
            let loaded = try XCTUnwrap(saved)
            XCTAssertEqual(loaded.snapshot.metadata.id, snapshot.metadata.id)
            XCTAssertEqual(loaded.assessment(for: last.identifier), last)
            XCTAssertEqual(loaded.assessmentPositions.count, count)

            let metrics = await Task.detached {
                let clock = ContinuousClock()
                let start = clock.now
                var indexedMisses = 0
                for _ in 0..<1_000 { if loaded.assessment(for: "missing") == nil { indexedMisses += 1 } }
                let indexed = start.duration(to: clock.now)
                let scanStart = clock.now
                var scannedMisses = 0
                for _ in 0..<10 {
                    if loaded.snapshot.assessments.first(where: { $0.identifier == "missing" }) == nil { scannedMisses += 1 }
                }
                let scan = scanStart.duration(to: clock.now)
                return "\(count) entries: 1000 indexed misses=\(indexed); 10 reference linear misses=\(scan); checks=\(indexedMisses)/\(scannedMisses)"
            }.value
            print("LOOKUP_BENCHMARK: \(metrics)")
            let attachment = XCTAttachment(string: metrics)
            attachment.name = "Lookup benchmark \(count)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
