import Foundation
import CryptoKit

struct CallShieldManifest: Decodable, Sendable {
    struct Shard: Decodable, Sendable {
        let id: String
        let path: String
        let sha256: String
        let bytes: Int
        let numbers: Int
        let prefixes: Int
    }
    let format_version: Int
    let version: Int64
    let updated: String
    let shard_directory: String
    let shard_count: Int
    let shards: [Shard]
}

/// The two publisher P-256 PUBLIC keys are pinned; no downloaded key can grant trust.
enum CallShieldSourceAdapter {
    static let trustedPublicKeys = [
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAESGK0kjIAEM7FP2RBLbWctHhYVP7LcNVJmWiuh6k6hkBGHfVXaqw+TOaSVQtbZLZeN5OThnqd0WTEF/CkBJ2gdA==",
        "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE3eBrWqtgDaKc2HFC6EPtENrh8nlCH/bZ5PstgPpIJBVL8ZEf35UfwtbqWKJ/fQDi1pYKLmvMv/0OC3KSug/fxg=="
    ]

    static func manifest(_ data: Data, signature: String, now: Date,
                         publicKeys: [String] = trustedPublicKeys) throws -> CallShieldManifest {
        guard data.count <= 256 * 1024,
              let bytes = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: bytes),
              publicKeys.contains(where: { encoded in
                  guard let der = Data(base64Encoded: encoded), let key = try? P256.Signing.PublicKey(derRepresentation: der) else { return false }
                  return key.isValidSignature(signature, for: data)
              }) else { throw SourceImportError.invalidSchema("CallShield manifest signature is missing or invalid.") }
        let value = try JSONDecoder().decode(CallShieldManifest.self, from: data)
        guard value.format_version == 1, value.version >= 0,
              let updated = PublisherDate.calendar(value.updated), updated <= now,
              value.shard_directory == "data/spam_number_shards", (1...256).contains(value.shard_count),
              value.shard_count == value.shards.count else {
            throw SourceImportError.invalidSchema("Unsupported CallShield manifest layout, version or date.")
        }
        var ids = Set<String>(); var totalBytes = 0; var totalNumbers = 0
        for shard in value.shards {
            guard shard.id.count == 2, shard.id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  ids.insert(shard.id).inserted, shard.path == "data/spam_number_shards/\(shard.id).json",
                  shard.sha256.count == 64, shard.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }),
                  (1...2 * 1024 * 1024).contains(shard.bytes), (0...SourceAdapters.maximumRecords).contains(shard.numbers),
                  (0...SourceAdapters.maximumRecords).contains(shard.prefixes) else {
                throw SourceImportError.invalidSchema("Invalid CallShield shard descriptor.")
            }
            totalBytes += shard.bytes; totalNumbers += shard.numbers
            guard totalBytes <= 64 * 1024 * 1024, totalNumbers <= SourceAdapters.maximumRecords else {
                throw SourceImportError.oversizedPayload
            }
        }
        return value
    }

    private struct ShardPayload: Decodable { let shard_id: String; let numbers: [Row] }
    private struct Row: Decodable {
        let number: String
        let type: String?
        let reports: Int?
        let sources: [String]?
        let evidence: [Entry]?
    }
    private struct Entry: Decodable {
        let source_id: String
        let evidence_type: String
        let license: String?
        let last_seen: String?
        let expires_at_epoch_ms: Int64?
        let revoked: Bool?
        let retracted_at: String?
        let complaint_role: String?
    }

    static func shard(_ data: Data, descriptor: CallShieldManifest.Shard, source: SourceDefinition,
                      watermark: Date, now: Date) throws -> ParsedSourceImport {
        guard data.count == descriptor.bytes, RowFingerprint.sha256(Array(data)) == descriptor.sha256 else {
            throw SourceImportError.invalidSchema("CallShield shard digest or size mismatch.")
        }
        let payload = try JSONDecoder().decode(ShardPayload.self, from: data)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard payload.shard_id == descriptor.id, payload.numbers.count == descriptor.numbers,
              (object?["prefixes"] as? [Any])?.count == descriptor.prefixes else {
            throw SourceImportError.invalidSchema("CallShield shard identity or row counts disagree with its manifest.")
        }
        var records: [EvidenceRecord] = []; var rejected = 0; var ids = Set<String>()
        for row in payload.numbers {
            guard row.number.hasPrefix("+"), let number = try? PhoneNormalizer.e164(row.number) else { rejected += 1; continue }
            for entry in row.evidence ?? [] {
                // The compiled database and FTC/FCC mirrors are not independent community evidence.
                guard ["community_reports", "maintainer_review"].contains(entry.source_id),
                      entry.evidence_type == (entry.source_id == "community_reports" ? "user_report" : "maintainer_review"),
                      entry.license == (entry.source_id == "community_reports" ? "CallShield community report policy" : "CallShield database terms"),
                      entry.revoked != true, entry.retracted_at == nil,
                      entry.complaint_role.map({ ["caller_id", "displayed_sender", "originating"].contains($0) }) ?? true,
                      let expiryMilliseconds = entry.expires_at_epoch_ms else { continue }
                let expiry = Date(timeIntervalSince1970: Double(expiryMilliseconds) / 1000)
                guard expiry > now, expiry.timeIntervalSince1970 < 1e13 else { continue }
                let activity = entry.last_seen.flatMap(PublisherDate.calendar)
                if let literal = entry.last_seen, !literal.isEmpty, activity == nil { rejected += 1; continue }
                if let activity, activity > min(watermark, now) { rejected += 1; continue }
                // Mixed-source totals cannot be attributed to this community. Retain one assertion instead.
                let communityOnly = !(row.sources ?? []).isEmpty
                    && (row.sources ?? []).allSatisfy { ["community_reports", "maintainer_review"].contains($0) }
                let votes = entry.source_id == "community_reports" && communityOnly ? max(1, row.reports ?? 1) : 1
                guard votes <= 1_000_000_000 else { rejected += 1; continue }
                let id = number + "|" + entry.source_id
                guard ids.insert(id).inserted else { throw SourceImportError.invalidSchema("Duplicate CallShield originating evidence.") }
                var record = EvidenceRecord(id: id, sourceID: source.id, sourceFamilyID: "callshield-community",
                    numberE164: number, channel: .call, reportedAt: activity ?? watermark, publisherWatermark: watermark,
                    identificationLabel: "Community listed")
                record.evidenceKind = entry.source_id == "maintainer_review" ? .maintainerReview : .aggregateMembership
                record.aggregateVotesLowerBound = votes; record.activityAt = activity; record.expiresAt = expiry
                record.publisherShardID = descriptor.id
                record.category = row.type.flatMap { $0.utf8.count <= 64 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) ? $0 : nil }
                records.append(try EvidenceNormalization.normalize(record, source: source))
            }
        }
        return ParsedSourceImport(records: records, publisherWatermark: watermark, rejectedRecordCount: rejected)
    }
}
