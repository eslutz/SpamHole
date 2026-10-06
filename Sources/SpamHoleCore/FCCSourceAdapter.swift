import Foundation

/// FCC's issue date is the alleged call day, not the date the complaint was filed.
enum FCCSourceAdapter {
    private struct Row: Decodable {
        let id: String?
        let issue_date: String?
        let caller_id_number: String?
        let type_of_call_or_messge: String?
    }
    static let voiceTypes = ["Abandoned Calls", "Autodialed Live Voice Call", "Live Voice", "Prerecorded Voice"]

    static func parse(_ data: Data, source: SourceDefinition, now: Date, watermark: Date?) throws -> ParsedSourceImport {
        guard let coverage = watermark, coverage.timeIntervalSince1970.isFinite, coverage <= now.addingTimeInterval(300) else {
            throw SourceImportError.invalidSchema("FCC requires a valid publisher publication watermark.")
        }
        let rows = try JSONDecoder().decode([Row].self, from: data)
        guard rows.count <= SourceAdapters.maximumRecords else { throw SourceImportError.tooManyRecords }
        var records: [EvidenceRecord] = []; var seen: [String: EvidenceRecord] = [:]; var rejected = 0
        for row in rows {
            guard let id = row.id, !id.isEmpty, id.utf8.count <= 128,
                  let type = row.type_of_call_or_messge, voiceTypes.contains(type),
                  let raw = row.caller_id_number, let number = try? PhoneNormalizer.e164(raw),
                  let literal = row.issue_date, let observed = PublisherDate.calendar(literal),
                  observed >= Date(timeIntervalSince1970: 0), observed <= min(coverage, now) else { rejected += 1; continue }
            var record = EvidenceRecord(id: id, sourceID: source.id, sourceFamilyID: "fcc-calls",
                numberE164: number, channel: .call, observedAt: observed, reportedAt: coverage,
                publisherWatermark: coverage, originalObservedDate: literal)
            record.reportedDateIsPublicationProxy = true; record.category = type
            if let old = seen[id] {
                guard old == record else { throw SourceImportError.invalidSchema("FCC reused a ticket ID with conflicting evidence.") }
                continue
            }
            seen[id] = record; records.append(record)
        }
        return ParsedSourceImport(records: records, publisherWatermark: coverage, rejectedRecordCount: rejected)
    }
}

/// Calendar-only dates retain their UTC day bucket; no local call time is invented.
enum PublisherDate {
    static func calendar(_ raw: String) -> Date? {
        guard raw.count >= 10 else { return nil }
        let day = String(raw.prefix(10))
        let parts = day.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let date = Int(parts[2]),
              (1970...9999).contains(year), (1...12).contains(month), (1...31).contains(date) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: date)
        guard let value = calendar.date(from: components), calendar.component(.year, from: value) == year,
              calendar.component(.month, from: value) == month, calendar.component(.day, from: value) == date else { return nil }
        if raw.count > 10 {
            guard SourceAdapters.parseDate(raw) != nil else { return nil }
        }
        return value
    }
}
