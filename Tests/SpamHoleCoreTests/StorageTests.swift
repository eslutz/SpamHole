import Foundation
import XCTest
@testable import SpamHoleCore

final class StorageTests: XCTestCase {
    private func withStore(_ body: (EvidenceStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        try body(EvidenceStore(url: url), url)
    }
    private func record(id: String = "a", source: SourceDefinition = SourceCatalog.builtIns[0]) -> EvidenceRecord {
        EvidenceRecord(id: id, sourceID: source.id, sourceFamilyID: source.sourceFamilyID, numberE164: "+12025550100",
                       channel: .call, reportedAt: Date(timeIntervalSince1970: 1_791_000_000),
                       publisherWatermark: Date(timeIntervalSince1970: 1_791_000_000))
    }
    func testReplayFullSnapshotRemovalAndDailyQualityWeight() throws {
        try withStore { store, _ in
            let source = SourceCatalog.builtIns[0]; let state = SourceState(sourceID: source.id)
            try store.replaceEvidence([record(), record(), record(id: "b")], source: source, state: state)
            XCTAssertEqual(try store.evidence().count, 2)
            XCTAssertEqual(try store.dailyCounts().first?.weightedCount, 1)
            try store.replaceEvidence([record(id: "b")], source: source, state: state)
            XCTAssertEqual(try store.evidence().map(\.id), ["b"])
            try store.replaceEvidence([], source: source, state: state)
            XCTAssertTrue(try store.evidence().isEmpty)
        }
    }
    func testFailedTransactionPreservesPreviousRecordsAndSuccessState() throws {
        try withStore { store, _ in
            let source = SourceCatalog.builtIns[0]; let oldState = SourceState(sourceID: source.id, lastSuccessAt: Date(timeIntervalSince1970: 100))
            try store.replaceEvidence([record()], source: source, state: oldState)
            var invalid = record(id: "invalid"); invalid.positivePenalty = .nan
            XCTAssertThrowsError(try store.replaceEvidence([record(id: "replacement"), invalid], source: source,
                                                         state: SourceState(sourceID: source.id, lastSuccessAt: Date(timeIntervalSince1970: 200))))
            XCTAssertEqual(try store.evidence().map(\.id), ["a"])
            XCTAssertEqual(try store.sourceState(id: source.id)?.lastSuccessAt, oldState.lastSuccessAt)
        }
    }
    func testSourceDisableAndDeleteRemoveActiveEvidence() throws {
        try withStore { store, _ in
            var source = SourceCatalog.builtIns[0]
            try store.replaceEvidence([record()], source: source, state: SourceState(sourceID: source.id))
            source.enabled = false; try store.saveSource(source)
            XCTAssertTrue(try store.evidence().isEmpty)
            XCTAssertEqual(try store.evidence(enabledOnly: false).count, 1)
            try store.removeSource(id: source.id)
            XCTAssertTrue(try store.evidence(enabledOnly: false).isEmpty)
            XCTAssertTrue(try store.sourceStates().isEmpty)
        }
    }
    func testRulesSettingsAndSchemaSurviveReopening() throws {
        try withStore { store, url in
            let rule = PersonalRule(identifier: "+12025550100", channel: .call, action: .allow)
            try store.saveRule(rule); try store.setSetting(AppSettings(policy: .conservative), forKey: "app-settings")
            let reopened = try EvidenceStore(url: url)
            XCTAssertEqual(try reopened.rules(), [rule])
            XCTAssertEqual(try reopened.setting(forKey: "app-settings", as: AppSettings.self)?.policy, .conservative)
            try reopened.deleteRule(id: rule.id); XCTAssertTrue(try store.rules().isEmpty)
        }
    }
    func testAtomicRuleBackupRejectsInvalidAndDuplicateRules() throws {
        try withStore { store, _ in
            let old = PersonalRule(identifier: "+12025550100", action: .allow)
            try store.saveRule(old)
            let invalid = PersonalRule(identifier: "202*", action: .block)
            XCTAssertThrowsError(try store.replaceRules([invalid]))
            XCTAssertEqual(try store.rules(), [old])
            XCTAssertThrowsError(try store.replaceRules([old, old]))
            try store.replaceRules([PersonalRule(identifier: "+14255550100", action: .block)])
            XCTAssertEqual(try store.rules().first?.identifier, "+14255550100")
        }
    }
    func testPersistedCustomTrustCannotBecomeReviewedSource() throws {
        try withStore { store, _ in
            var source = SourceCatalog.builtIns[0]
            source.url = URL(string: "https://example.org/pretend-ftc")!
            try store.saveSource(source)
            XCTAssertNil(try store.sources().first?.reviewedTrust)
            XCTAssertEqual(try store.sources().first?.sourceFamilyID, source.id)
        }
    }
    func testAutomaticRefreshEvaluatesSourcesIndependentlyAndSkipsDisabledSources() {
        let now = Date(timeIntervalSince1970: 1_791_072_000)
        let healthy = SourceDefinition(id: "healthy", name: "Healthy", url: URL(string: "https://example.org/healthy")!,
                                       format: .evidenceJSON, sourceFamilyID: "healthy")
        var failed = healthy; failed.id = "failed"
        var added = healthy; added.id = "added"
        var disabled = healthy; disabled.id = "disabled"; disabled.enabled = false
        let states = [SourceState(sourceID: "healthy", lastSuccessAt: now.addingTimeInterval(-60)),
                      SourceState(sourceID: "failed", lastAttemptAt: now.addingTimeInterval(-901), error: "Failed")]
        XCTAssertEqual(RefreshPolicy.dueSourceIDs(sources: [healthy, failed, added, disabled], states: states,
                                                  cadence: .daily, now: now), ["failed", "added"])
        XCTAssertTrue(RefreshPolicy.dueSourceIDs(sources: [healthy, failed, added], states: states,
                                                 cadence: .manual, now: now).isEmpty)
    }
    func testAutomaticRefreshCadenceAndRetryBoundaries() {
        let now = Date(timeIntervalSince1970: 1_791_072_000)
        let source = SourceCatalog.builtIns[0]
        func due(_ successAge: TimeInterval?, attemptAge: TimeInterval? = nil, cadence: RefreshCadence = .daily) -> Bool {
            let state = SourceState(sourceID: source.id,
                                    lastAttemptAt: attemptAge.map { now.addingTimeInterval(-$0) },
                                    lastSuccessAt: successAge.map { now.addingTimeInterval(-$0) })
            return RefreshPolicy.dueSourceIDs(sources: [source], states: [state], cadence: cadence, now: now).contains(source.id)
        }
        XCTAssertFalse(due(86400 - 1))
        XCTAssertTrue(due(86400))
        XCTAssertFalse(due(7 * 86400 - 1, cadence: .weekly))
        XCTAssertTrue(due(7 * 86400, cadence: .weekly))
        XCTAssertFalse(due(nil, attemptAge: 899))
        XCTAssertTrue(due(nil, attemptAge: 900))
        XCTAssertFalse(due(2 * 86400, attemptAge: 0))
        XCTAssertTrue(due(nil))
    }
}
