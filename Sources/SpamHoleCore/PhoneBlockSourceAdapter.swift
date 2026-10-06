import Foundation

struct PhoneBlockDelta: Sendable {
    let records: [EvidenceRecord]
    let removed: Set<String>
    let version: Int64
    let rejected: Int
    let watermark: Date
    let hasInvalidRecords: Bool
}

enum PhoneBlockSourceAdapter {
    private struct Envelope: Decodable { let version: Int64; let numbers: [Row] }
    private struct Row: Decodable { let phone: String; let rating: String; let votes: Int; let lastActivity: Int64? }
    static let negativeRatings: Set<String> = ["C_PING", "D_POLL", "E_ADVERTISING", "F_GAMBLE", "G_FRAUD"]

    static func parse(_ data: Data, source: SourceDefinition, now: Date) throws -> PhoneBlockDelta {
        let payload = try JSONDecoder().decode(Envelope.self, from: data)
        guard payload.version >= 0, payload.numbers.count <= SourceAdapters.maximumRecords else {
            throw SourceImportError.invalidSchema("Invalid PhoneBlock version or number count.")
        }
        var records: [EvidenceRecord] = []; var removed = Set<String>(); var identifiers = Set<String>(); var rejected = 0; var hasInvalidRecords = false
        for row in payload.numbers {
            guard row.phone.hasPrefix("+") else { rejected += 1; hasInvalidRecords = true; continue }
            let number: String
            do { number = try PhoneNormalizer.e164(row.phone) }
            catch SpamHoleCoreError.unsupportedPhoneRegion { rejected += 1; continue }
            catch { rejected += 1; hasInvalidRecords = true; continue }
            guard identifiers.insert(number).inserted else { throw SourceImportError.invalidSchema("PhoneBlock published a duplicate number.") }
            guard [0, 2, 4, 10, 20, 50, 100].contains(row.votes),
                  negativeRatings.contains(row.rating) || ["A_LEGITIMATE", "B_MISSED"].contains(row.rating) else { rejected += 1; hasInvalidRecords = true; continue }
            if row.votes == 0 || ["A_LEGITIMATE", "B_MISSED"].contains(row.rating) { removed.insert(number); continue }
            let activity = row.lastActivity.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            if let activity, activity < Date(timeIntervalSince1970: 0) || activity > now { rejected += 1; hasInvalidRecords = true; continue }
            var record = EvidenceRecord(id: number, sourceID: source.id, sourceFamilyID: "phoneblock",
                numberE164: number, channel: .call, reportedAt: activity ?? .distantPast,
                publisherWatermark: activity ?? .distantPast, identificationLabel: "Community listed")
            record.evidenceKind = .aggregateMembership; record.aggregateVotesLowerBound = row.votes
            record.activityAt = activity; record.category = row.rating
            records.append(try EvidenceNormalization.normalize(record, source: source))
        }
        let watermark = records.compactMap(\.activityAt).max() ?? .distantPast
        return PhoneBlockDelta(records: records, removed: removed, version: payload.version, rejected: rejected, watermark: watermark, hasInvalidRecords: hasInvalidRecords)
    }
}
