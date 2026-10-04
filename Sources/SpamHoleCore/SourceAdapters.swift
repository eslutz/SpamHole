import Foundation

public enum SourceImportError: Error, LocalizedError, Equatable {
    case invalidURL, invalidEncoding, invalidSchema(String), oversizedPayload, tooManyRecords
    case httpStatus(Int), noPublishedFiles, futureDate, emptyDataset, sourceChanged
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
        guard data.count <= 32 * 1024 * 1024 else { throw SourceImportError.oversizedPayload }
        switch source.format {
        case .evidenceJSON: return try parseEvidenceJSON(data, source: source, now: now)
        case .identificationCSV: return try parseIdentificationList(data, source: source, now: now, watermark: publisherWatermark)
        case .ftcCSV: return try parseFTC(data, source: source, now: now, watermark: publisherWatermark)
        case .fccJSON: return try parseFCC(data, source: source, now: now, watermark: publisherWatermark)
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
                  source.channels.contains(record.channel) || source.channels.contains(.both),
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
        for row in rows.dropFirst() where !row.allSatisfy({ $0.isEmpty }) {
            guard row.count == header.count else { throw SourceImportError.invalidSchema("FTC CSV row width changed.") }
            guard let number = normalize(row[phoneIndex], channel: .call), let reported = parseDate(row[reportedIndex]) else { rejected += 1; continue }
            let observed = parseDate(row[observedIndex])
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

    public static func parseFCC(_ data: Data, source: SourceDefinition, now: Date,
                               watermark: Date?) throws -> ParsedSourceImport {
        guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SourceImportError.invalidSchema("Expected the FCC Socrata JSON array.")
        }
        guard objects.count <= maximumRecords else { throw SourceImportError.tooManyRecords }
        var rows: [(String, String, Date, String)] = []; var rejected = 0
        for object in objects {
            // Voice records never become SMS evidence. Advertiser/business numbers are not sender IDs.
            guard object["type_of_call_or_messge"] as? String == "Text Message" else { rejected += 1; continue }
            guard let id = object["id"] as? String, let sender = object["caller_id_number"] as? String,
                  let exact = normalize(sender, channel: .sms), let dateString = object["issue_date"] as? String,
                  let date = parseDate(dateString), date <= now.addingTimeInterval(300) else { rejected += 1; continue }
            rows.append((id, exact, date, dateString))
        }
        guard let derived = rows.map({ $0.2 }).max() else { throw SourceImportError.emptyDataset }
        let coverage = watermark ?? derived; try validateWatermark(coverage, now: now)
        let records = rows.map {
            EvidenceRecord(id: $0.0, sourceID: source.id, sourceFamilyID: "fcc-complaints", numberE164: $0.1,
                           channel: .sms, numberRole: .displayedSender, reportedAt: $0.2, publisherWatermark: coverage,
                           originalReportedDate: $0.3)
        }
        return ParsedSourceImport(records: records, publisherWatermark: coverage, rejectedRecordCount: rejected)
    }

    public static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
    private static func validateWatermark(_ watermark: Date, now: Date) throws {
        guard watermark <= now.addingTimeInterval(300) else { throw SourceImportError.futureDate }
    }
    private static func normalize(_ raw: String, channel: CommunicationChannel) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !["", "none", "null", "n/a", "unknown", "anonymous"].contains(trimmed.lowercased()) else { return nil }
        if let phone = try? PhoneNormalizer.e164(trimmed) { return phone }
        guard channel == .sms else { return nil }
        return try? PhoneNormalizer.smsIdentifier(trimmed)
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
private enum RowFingerprint {
    static func sha256(_ input: [UInt8]) -> String {
        let constants: [UInt32] = [
            0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
            0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
            0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
            0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
            0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
            0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
            0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
            0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]
        var hash: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
        var bytes = input; let bits = UInt64(bytes.count) * 8; bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: bits >> shift)) }
        func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        for start in stride(from: 0, to: bytes.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { let o = start + i * 4; words[i] = UInt32(bytes[o]) << 24 | UInt32(bytes[o+1]) << 16 | UInt32(bytes[o+2]) << 8 | UInt32(bytes[o+3]) }
            for i in 16..<64 {
                let x = words[i-15], y = words[i-2]
                words[i] = words[i-16] &+ (rotate(x,7) ^ rotate(x,18) ^ (x >> 3)) &+ words[i-7] &+ (rotate(y,17) ^ rotate(y,19) ^ (y >> 10))
            }
            var a=hash[0], b=hash[1], c=hash[2], d=hash[3], e=hash[4], f=hash[5], g=hash[6], h=hash[7]
            for i in 0..<64 {
                let t1 = h &+ (rotate(e,6) ^ rotate(e,11) ^ rotate(e,25)) &+ ((e & f) ^ (~e & g)) &+ constants[i] &+ words[i]
                let t2 = (rotate(a,2) ^ rotate(a,13) ^ rotate(a,22)) &+ ((a & b) ^ (a & c) ^ (b & c))
                h=g; g=f; f=e; e=d &+ t1; d=c; c=b; b=a; a=t1 &+ t2
            }
            hash[0] &+= a; hash[1] &+= b; hash[2] &+= c; hash[3] &+= d; hash[4] &+= e; hash[5] &+= f; hash[6] &+= g; hash[7] &+= h
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }
}
