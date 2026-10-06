import Foundation
import CryptoKit

public enum SourceImportError: Error, LocalizedError, Equatable {
    case invalidURL, invalidEncoding, invalidSchema(String), oversizedPayload, tooManyRecords
    case httpStatus(Int), noPublishedFiles, futureDate, emptyDataset, sourceChanged
    case refreshNotDue
    public var errorDescription: String? {
        switch self {
        case .invalidURL: "A direct HTTPS URL without embedded credentials or credential query parameters is required. Save access tokens in the separate Keychain token field."
        case .invalidEncoding: "The publisher response is not valid UTF-8."
        case .invalidSchema(let reason): "Source format rejected: \(reason)"
        case .oversizedPayload: "The source exceeds the permitted download size."
        case .tooManyRecords: "The source exceeds the permitted record count."
        case .httpStatus(let status): "The publisher returned HTTP \(status). The previous dataset is retained."
        case .noPublishedFiles: "The FTC page did not contain published CSV links."
        case .futureDate: "The source contains dates beyond its coverage watermark or the current time."
        case .emptyDataset: "No usable exact sender records were published."
        case .refreshNotDue: "Publisher refresh is not yet due. The previous dataset is retained."
        case .sourceChanged: "The subscription changed or was removed while downloading. The update was discarded."
        }
    }
}

public struct ParsedSourceImport: Sendable {
    public let records: [EvidenceRecord]
    public let publisherWatermark: Date
    public let rejectedRecordCount: Int
    public init(records: [EvidenceRecord], publisherWatermark: Date, rejectedRecordCount: Int = 0) {
        self.records = records; self.publisherWatermark = publisherWatermark
        self.rejectedRecordCount = rejectedRecordCount
    }
}

/// Parsing never grants trust from fields supplied by a publisher or subscriber.
public enum SourceAdapters {
    public static let maximumRecords = 500_000

    static func validateDigest(data: Data, contentDigest: String?, legacyDigest: String?) throws {
        guard let supplied = contentDigest ?? legacyDigest else { return }
        let pattern = contentDigest != nil ? "(?:^|,)\\s*sha-256\\s*=\\s*:([A-Za-z0-9+/=]+):(?:\\s*(?:,|$))" : "(?:^|,)\\s*sha-256\\s*=\\s*([A-Za-z0-9+/=]+)(?:\\s*(?:,|$))"
        let expression = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        guard let match = expression.firstMatch(in: supplied, range: NSRange(supplied.startIndex..., in: supplied)),
              let range = Range(match.range(at: 1), in: supplied), let expected = Data(base64Encoded: String(supplied[range])), expected.count == 32 else {
            throw SourceImportError.invalidSchema("The publisher digest must supply supported SHA-256 bytes.")
        }
        let hex = RowFingerprint.sha256(Array(data))
        let actual = Data(stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset); let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)!
        })
        guard actual == expected else { throw SourceImportError.invalidSchema("Publisher SHA-256 digest does not match downloaded bytes.") }
    }

    public static func parse(data: Data, source: SourceDefinition, now: Date,
                             publisherWatermark: Date? = nil) throws -> ParsedSourceImport {
        try SourceCatalog.validateCallSource(source)
        guard data.count <= 32 * 1024 * 1024 else { throw SourceImportError.oversizedPayload }
        switch source.format {
        case .evidenceJSON: return try parseEvidenceJSON(data, source: source, now: now)
        case .identificationCSV: return try parseIdentificationList(data, source: source, now: now, watermark: publisherWatermark)
        case .ftcCSV: return try parseFTC(data, source: source, now: now, watermark: publisherWatermark)
        case .fccCallsJSON: return try FCCSourceAdapter.parse(data, source: source, now: now, watermark: publisherWatermark)
        case .phoneBlockJSON:
            let delta = try PhoneBlockSourceAdapter.parse(data, source: source, now: now)
            return ParsedSourceImport(records: delta.records, publisherWatermark: delta.watermark, rejectedRecordCount: delta.rejected)
        case .callShieldJSON: throw SourceImportError.invalidSchema("CallShield imports require a verified manifest and all required shards.")
        case .fccJSON: throw SourceImportError.invalidSchema("The retired text-complaint format is unsupported.")
        }
    }

    private struct Envelope: Decodable {
        let schemaVersion: Int
        let publisherWatermark: Date
        let records: [WireRecord]
        let snapshot: Bool?
    }
    private struct WireRecord: Decodable {
        let id: String
        let identifier: String
        let channel: CommunicationChannel
        let numberRole: NumberRole?
        let observedAt: Date?
        let reportedAt: Date
        let confirmationGrade: Double?
        let confirmationMethod: String?
        let confirmationExpiresAt: Date?
        let confirmationReviewedAt: Date?
        let retractedAt: Date?
        let assignmentBoundaryAt: Date?
        let positivePenalty: Double?
        let uncertaintyPenalty: Double?
    }

    public static func parseEvidenceJSON(_ data: Data, source: SourceDefinition, now: Date) throws -> ParsedSourceImport {
        try SourceCatalog.validateCallSource(source)
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["signature"] != nil {
            throw SourceImportError.invalidSchema("Signed feed envelopes need a reviewed signing-key contract, which V1 does not support.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard text.contains("T"), let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw SourceImportError.invalidSchema("Dates must be ISO 8601 timestamps with a timezone.")
            }
            return date
        }
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw SourceImportError.invalidSchema("Expected a versioned evidence JSON snapshot with valid dates.") }
        guard envelope.schemaVersion == 1, envelope.snapshot != false else {
            throw SourceImportError.invalidSchema("Only schemaVersion 1 full snapshots are supported.")
        }
        try validateWatermark(envelope.publisherWatermark, now: now)
        guard envelope.records.count <= maximumRecords else { throw SourceImportError.tooManyRecords }
        var identifiers = Set<String>()
        let safeSource = SourceCatalog.canonicalize(source)
        let records = try envelope.records.map { record -> EvidenceRecord in
            guard !record.id.isEmpty, record.id.utf8.count <= 256, identifiers.insert(record.id).inserted,
                  let identifier = normalize(record.identifier, channel: record.channel),
                  record.channel == .call,
                  record.reportedAt <= envelope.publisherWatermark,
                  record.observedAt.map({ $0 <= record.reportedAt }) ?? true else {
                throw SourceImportError.invalidSchema("A record has an invalid identifier, duplicate ID, channel or date.")
            }
            for value in [record.positivePenalty ?? 0, record.uncertaintyPenalty ?? 0] {
                guard value.isFinite, (0...1).contains(value) else { throw SourceImportError.invalidSchema("Penalties must be finite values from 0 to 1.") }
            }
            let proposedGrade = record.confirmationGrade ?? 0
            guard [0.0, 0.8, 1.0].contains(proposedGrade) else { throw SourceImportError.invalidSchema("Unsupported confirmation grade.") }
            let trust = safeSource.reviewedTrust
            let approved = trust?.confirmationAuthority == true
                && trust?.allowedConfirmationMethods.contains(record.confirmationMethod ?? "") == true
                && proposedGrade <= (trust?.maximumConfirmationGrade ?? 0)
            return EvidenceRecord(id: record.id, sourceID: source.id, sourceFamilyID: safeSource.sourceFamilyID,
                                  numberE164: identifier, channel: record.channel, numberRole: record.numberRole ?? .displayedSender,
                                  observedAt: record.observedAt, reportedAt: record.reportedAt,
                                  publisherWatermark: envelope.publisherWatermark,
                                  confirmationGrade: approved ? proposedGrade : 0,
                                  confirmationMethod: approved ? record.confirmationMethod : nil,
                                  confirmationExpiresAt: approved ? record.confirmationExpiresAt : nil,
                                  confirmationReviewedAt: approved ? record.confirmationReviewedAt : nil,
                                  retractedAt: record.retractedAt, assignmentBoundaryAt: record.assignmentBoundaryAt,
                                  positivePenalty: record.positivePenalty ?? 0, uncertaintyPenalty: record.uncertaintyPenalty ?? 0)
        }
        return ParsedSourceImport(records: records, publisherWatermark: envelope.publisherWatermark)
    }

    public static func parseIdentificationList(_ data: Data, source: SourceDefinition, now: Date,
                                               watermark: Date?) throws -> ParsedSourceImport {
        try SourceCatalog.validateCallSource(source)
        guard let watermark else { throw SourceImportError.invalidSchema("Identification lists require a publisher Last-Modified timestamp.") }
        try validateWatermark(watermark, now: now)
        guard let text = String(data: data, encoding: .utf8) else { throw SourceImportError.invalidEncoding }
        let rows = try CSV.parse(text)
        guard rows.count <= maximumRecords + 1 else { throw SourceImportError.tooManyRecords }
        var records: [EvidenceRecord] = []; var seen = Set<String>()
        for (index, row) in rows.enumerated() where !row.allSatisfy({ $0.isEmpty }) {
            if index == 0 && ["identifier", "phone", "number"].contains(row[0].lowercased()) { continue }
            guard row.count == 1, let identifier = normalize(row[0], channel: .call) else {
                throw SourceImportError.invalidSchema("Identification lists contain one exact telephone number per line.")
            }
            guard seen.insert(identifier).inserted else { continue }
            records.append(EvidenceRecord(id: identifier, sourceID: source.id, sourceFamilyID: source.id,
                                          numberE164: identifier, channel: .call, numberRole: .displayedSender,
                                          reportedAt: watermark, publisherWatermark: watermark,
                                          identificationLabel: "Listed by source"))
        }
        return ParsedSourceImport(records: records, publisherWatermark: watermark)
    }

    public static func parseFTC(_ data: Data, source: SourceDefinition, now: Date,
                               watermark: Date?) throws -> ParsedSourceImport {
        try SourceCatalog.validateCallSource(source)
        guard let text = String(data: data, encoding: .utf8) else { throw SourceImportError.invalidEncoding }
        let rows = try CSV.parse(text)
        guard let header = rows.first else { throw SourceImportError.invalidSchema("Missing FTC CSV header.") }
        let keys = header.map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard let phoneIndex = keys.firstIndex(of: "companyphonenumber"),
              let reportedIndex = keys.firstIndex(of: "createddate"),
              let observedIndex = keys.firstIndex(of: "violationdate") else {
            throw SourceImportError.invalidSchema("FTC CSV requires Company_Phone_Number, Created_Date and Violation_Date.")
        }
        guard rows.count <= maximumRecords + 1 else { throw SourceImportError.tooManyRecords }
        var dated: [(id: String, number: String, reported: Date, observed: Date?, reportedLiteral: String, observedLiteral: String)] = []
        var rejected = 0
        let dates = SourceDateParser()
        for row in rows.dropFirst() where !row.allSatisfy({ $0.isEmpty }) {
            guard row.count == header.count else { throw SourceImportError.invalidSchema("FTC CSV row width changed.") }
            guard let number = normalize(row[phoneIndex], channel: .call), let reported = dates.parse(row[reportedIndex]) else { rejected += 1; continue }
            let observed = dates.parse(row[observedIndex])
            guard reported <= now.addingTimeInterval(300), observed.map({ $0 <= reported }) ?? true else { rejected += 1; continue }
            // No public complaint ID is supplied in daily CSV. Identical complete rows are one evidence item,
            // including across daily files/mirrors. Keep every original field in this stable identity.
            let rowIdentity = row.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
            let identity = RowFingerprint.sha256(Array(rowIdentity.utf8))
            dated.append((identity, number, reported, observed, row[reportedIndex], row[observedIndex]))
        }
        guard let derived = dated.map(\.reported).max() else { throw SourceImportError.emptyDataset }
        let coverage = watermark ?? derived
        try validateWatermark(coverage, now: now)
        var seen = Set<String>()
        let records = dated.filter { seen.insert($0.id).inserted }.map {
            EvidenceRecord(id: $0.id, sourceID: source.id, sourceFamilyID: "ftc-dnc", numberE164: $0.number,
                           channel: .call, numberRole: .displayedSender, observedAt: $0.observed,
                           reportedAt: $0.reported, publisherWatermark: coverage,
                           originalReportedDate: $0.reportedLiteral, originalObservedDate: $0.observedLiteral.isEmpty ? nil : $0.observedLiteral)
        }
        return ParsedSourceImport(records: records, publisherWatermark: coverage, rejectedRecordCount: rejected)
    }

    public static func parseDate(_ text: String) -> Date? {
        SourceDateParser().parse(text)
    }
    private static func validateWatermark(_ watermark: Date, now: Date) throws {
        guard watermark <= now.addingTimeInterval(300) else { throw SourceImportError.futureDate }
    }
    private static func normalize(_ raw: String, channel: CommunicationChannel) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !["", "none", "null", "n/a", "unknown", "anonymous"].contains(trimmed.lowercased()) else { return nil }
        guard channel == .call else { return nil }
        return try? PhoneNormalizer.e164(trimmed)
    }
}

/// Per-import ownership avoids global mutable formatters and repeated ICU setup per row.
private final class SourceDateParser {
    private let fractional = ISO8601DateFormatter()
    private let internet = ISO8601DateFormatter()
    private let formats: [DateFormatter]

    init() {
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formats = ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.isLenient = false
            formatter.dateFormat = format
            return formatter
        }
    }

    func parse(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        if let date = fractional.date(from: text) ?? internet.date(from: text) { return date }
        for formatter in formats {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}

/// RFC 4180 quoting, CRLF and embedded newlines; malformed quotation fails the entire transaction.
private enum CSV {
    static func parse(_ text: String) throws -> [[String]] {
        let clean = (text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text).replacingOccurrences(of: "\r\n", with: "\n")
        let chars = Array(clean)
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false, index = 0
        while index < chars.count {
            let char = chars[index]
            if quoted {
                if char == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(char) }
            } else if char == "\"" {
                guard field.isEmpty && !closed else { throw SourceImportError.invalidSchema("Malformed CSV quotation.") }
                quoted = true
            } else if char == "," { row.append(field); field = ""; closed = false
            } else if char == "\n" || char == "\r" {
                if char == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
                row.append(field); rows.append(row); row = []; field = ""; closed = false
                guard rows.count <= SourceAdapters.maximumRecords + 1 else { throw SourceImportError.tooManyRecords }
            } else {
                guard !closed else { throw SourceImportError.invalidSchema("Characters after closing CSV quote.") }
                field.append(char)
            }
            index += 1
        }
        guard !quoted else { throw SourceImportError.invalidSchema("Unclosed CSV quotation.") }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

/// Stable row identity only; this does not authenticate a publisher or authorize a filtering decision.
enum RowFingerprint {
    static func sha256(_ input: [UInt8]) -> String {
        SHA256.hash(data: Data(input)).map { String(format: "%02x", $0) }.joined()
    }
}
