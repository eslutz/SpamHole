#if DEBUG
import Foundation
import SpamHoleCore

/// Synthetic UI fixtures live only in the isolated --ui-testing container.
@MainActor
enum DebugLocalBlockingFixture {
    static func seed(model: AppModel) throws {
        guard model.testing else { return }
        let source = SourceCatalog.builtIns[0]
        let now = Date()
        let cases = [("+12025550101", 3), ("+12025550102", 4), ("+12025550100", 7)]
        let records = cases.flatMap { number, days in (0..<days).flatMap { day in (0..<5).map { report in
            EvidenceRecord(id: "ui-fixture-\(number)-\(day)-\(report)", sourceID: source.id,
                sourceFamilyID: source.sourceFamilyID, numberE164: number, channel: .call,
                observedAt: now.addingTimeInterval(-Double(day) * 86_400), reportedAt: now, publisherWatermark: now)
        } } }
        try model.store.replaceEvidence(records, source: source,
            state: SourceState(sourceID: source.id, lastSuccessAt: now, publisherWatermark: now))
    }
}
#endif
