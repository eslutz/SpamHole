import Foundation

/// Shared normalization runs before evidence is stored or scored. It cannot grant publisher authority.
enum EvidenceNormalization {
    static func normalize(_ original: EvidenceRecord, source: SourceDefinition) throws -> EvidenceRecord {
        var record = original
        record.numberE164 = try PhoneNormalizer.e164(record.numberE164)
        record.sourceID = source.id; record.sourceFamilyID = source.sourceFamilyID
        let dates = [record.observedAt, record.activityAt, record.reportedAt, record.publisherWatermark,
                     record.expiresAt, record.retractedAt].compactMap { $0 }
        guard dates.allSatisfy({ $0.timeIntervalSince1970.isFinite && abs($0.timeIntervalSince1970) < 1e13 }),
              record.reportedAt <= record.publisherWatermark,
              record.observedAt.map({ $0 <= record.reportedAt }) ?? true,
              record.activityAt.map({ $0 <= record.publisherWatermark }) ?? true,
              record.aggregateVotesLowerBound.map({ (0...1_000_000_000).contains($0) }) ?? true else {
            throw SourceImportError.invalidSchema("Invalid normalized evidence dates or vote floor.")
        }
        if record.isAggregate { record.observedAt = nil }
        return record
    }
}
