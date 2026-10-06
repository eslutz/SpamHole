import XCTest
import SpamHoleCore
@testable import SpamHole

@MainActor
final class SourceIntegrationTests: XCTestCase {
    private func root() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testBuiltInMigrationPreservesDisabledSources() throws {
        let root = root(); let store = try EvidenceStore(url: root.appendingPathComponent("evidence.sqlite"))
        var ftc = SourceCatalog.builtIns[0]; ftc.enabled = false; try store.saveSource(ftc)
        let model = try AppModel(rootURL: root, testing: true)
        XCTAssertEqual(Set(model.sources.map(\.id)), ["ftc-dnc", "fcc-calls", "callshield", "phoneblock"])
        XCTAssertTrue(model.sources.allSatisfy { !$0.enabled })
    }
    func testPhoneBlockActivationRemainsGatedWithoutPublisherClearance() async throws {
        let model = try AppModel(rootURL: root(), testing: true)
        let source = try XCTUnwrap(model.sources.first { $0.id == "phoneblock" })
        await model.setSource(source, enabled: true)
        XCTAssertFalse(try XCTUnwrap(model.sources.first { $0.id == source.id }).enabled)
        XCTAssertTrue(model.message?.contains("clearance") == true)
    }
    func testCredentialRotationClearsOnlyItsSourceAndPreservesRefreshCadence() async throws {
        let model = try AppModel(rootURL: root(), testing: true)
        let source = SourceDefinition(id: "synthetic-credential-\(UUID().uuidString)", name: "Synthetic",
            url: URL(string: "https://example.org/feed")!, format: .evidenceJSON, sourceFamilyID: "synthetic")
        try model.store.saveSource(source)
        defer { try? KeychainCredentials.remove(for: source.id) }
        let now = Date(); let due = now.addingTimeInterval(86400)
        let record = EvidenceRecord(id: "one", sourceID: source.id, sourceFamilyID: source.id,
            numberE164: "+12025550100", channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now)
        var state = SourceState(sourceID: source.id, lastSuccessAt: now, publisherWatermark: now)
        state.lastFullAttemptAt = now; state.nextRefreshAt = due; state.publisherVersion = 42
        try model.store.replaceEvidence([record], source: source, state: state)
        try model.store.saveRule(.init(identifier: "+12025550101", action: .allow))
        try model.loadState()
        try await model.saveSourceCredential(sourceID: source.id, token: "synthetic-not-a-real-credential")
        XCTAssertTrue(try model.store.evidence().isEmpty)
        XCTAssertNil(try model.store.sourceState(id: source.id)?.publisherVersion)
        XCTAssertEqual(try model.store.sourceState(id: source.id)?.nextRefreshAt, due)
        XCTAssertEqual(try model.store.sourceState(id: source.id)?.lastFullAttemptAt, now)
        XCTAssertEqual(model.rules.map(\.identifier), ["+12025550101"])
        XCTAssertNotNil(try KeychainCredentials.token(for: source.id))
    }
}
