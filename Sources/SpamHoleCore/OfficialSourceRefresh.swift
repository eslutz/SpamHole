import Foundation

extension SourceDownloader {
    func refreshOfficial(source: SourceDefinition, previous: SourceState, now: Date,
                         headers suppliedHeaders: [String: String]) async throws -> SourceRefreshResult {
        guard SourceCatalog.builtIns.contains(where: { $0.id == source.id && $0.url == source.url && $0.format == source.format }) else {
            throw SourceImportError.invalidSchema("Official adapters require the reviewed publisher identity.")
        }
        var headers = suppliedHeaders; headers["User-Agent"] = "SpamHole/1.0 (offline dataset synchronization)"
        let download: (ParsedSourceImport, SourceState)
        switch source.format {
        case .fccCallsJSON: download = try await downloadFCC(source: source, previous: previous, now: now, headers: headers)
        case .phoneBlockJSON: download = try await downloadPhoneBlock(source: source, previous: previous, now: now, headers: headers)
        case .callShieldJSON: download = try await downloadCallShield(source: source, previous: previous, now: now, headers: headers)
        default: throw SourceImportError.invalidSchema("Unsupported official adapter.")
        }
        try Task.checkCancellation()
        var state = download.1
        state.lastAttemptAt = now; state.lastSuccessAt = now; state.error = nil
        state.publisherWatermark = download.0.publisherWatermark
        state.rejectedRecordCount = download.0.rejectedRecordCount
        try store.replaceEvidence(download.0.records, source: source, state: state, requireCurrentSource: true,
            expectedImportRevision: state.importRevision, enforceRevision: true)
        return SourceRefreshResult(sourceID: source.id, recordCount: download.0.records.count,
            rejectedRecordCount: download.0.rejectedRecordCount, publisherWatermark: download.0.publisherWatermark, lastSuccessAt: now)
    }

    private struct FCCMetadata: Decodable { let rowsUpdatedAt: Int64 }
    private func downloadFCC(source: SourceDefinition, previous: SourceState, now: Date,
                             headers: [String: String]) async throws -> (ParsedSourceImport, SourceState) {
        let metadataURL = URL(string: "https://opendata.fcc.gov/api/views/vakf-fz8e.json")!
        let first = try await fetch(metadataURL, headers: headers, maximumBytes: 2 * 1024 * 1024)
        let metadata = try JSONDecoder().decode(FCCMetadata.self, from: first.data)
        let coverage = Date(timeIntervalSince1970: Double(metadata.rowsUpdatedAt))
        guard coverage >= Date(timeIntervalSince1970: 0), coverage <= now.addingTimeInterval(300),
              previous.publisherWatermark.map({ coverage >= $0 }) ?? true else { throw SourceImportError.futureDate }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let lower = formatter.string(from: now.addingTimeInterval(-90 * 86400))
        let upper = formatter.string(from: now)
        let kinds = FCCSourceAdapter.voiceTypes.map { "'\($0)'" }.joined(separator: ",")
        var records: [EvidenceRecord] = []; var seen = Set<String>(); var rejected = 0; var offset = 0; var bytes = 0
        while true {
            var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "$select", value: "id,issue_date,caller_id_number,type_of_call_or_messge"),
                URLQueryItem(name: "$where", value: "issue_date >= '\(lower)T00:00:00' AND issue_date <= '\(upper)T23:59:59' AND type_of_call_or_messge in (\(kinds))"),
                URLQueryItem(name: "$order", value: "issue_date ASC,id ASC"),
                URLQueryItem(name: "$limit", value: "10000"), URLQueryItem(name: "$offset", value: String(offset))]
            guard let url = components.url else { throw SourceImportError.invalidURL }
            let page = try await fetch(url, headers: headers, maximumBytes: 8 * 1024 * 1024)
            bytes += page.data.count
            guard bytes <= 64 * 1024 * 1024 else { throw SourceImportError.oversizedPayload }
            guard let raw = try JSONSerialization.jsonObject(with: page.data) as? [[String: Any]] else {
                throw SourceImportError.invalidSchema("FCC page is not a record array.")
            }
            offset += raw.count
            guard offset <= SourceAdapters.maximumRecords else { throw SourceImportError.tooManyRecords }
            let parsed = try FCCSourceAdapter.parse(page.data, source: source, now: now, watermark: coverage)
            for record in parsed.records {
                guard seen.insert(record.id).inserted else { throw SourceImportError.invalidSchema("FCC paging repeated a ticket ID.") }
                records.append(try EvidenceNormalization.normalize(record, source: source))
            }
            rejected += parsed.rejectedRecordCount
            if raw.count < 10000 { break }
        }
        let final = try await fetch(metadataURL, headers: headers, maximumBytes: 2 * 1024 * 1024)
        guard try JSONDecoder().decode(FCCMetadata.self, from: final.data).rowsUpdatedAt == metadata.rowsUpdatedAt else {
            throw SourceImportError.invalidSchema("FCC changed during paging; the previous complete dataset is retained.")
        }
        if offset > 0 && records.isEmpty { throw SourceImportError.emptyDataset }
        return (ParsedSourceImport(records: records, publisherWatermark: coverage, rejectedRecordCount: rejected), previous)
    }

    private func downloadPhoneBlock(source: SourceDefinition, previous original: SourceState, now: Date,
                                    headers: [String: String]) async throws -> (ParsedSourceImport, SourceState) {
        guard phoneBlockAccessApproved else {
            throw SourceImportError.invalidSchema("PhoneBlock requires publisher app registration and database-use clearance before activation.")
        }
        guard let authorization = headers.first(where: { $0.key.lowercased() == "authorization" })?.value,
              authorization.hasPrefix("Bearer "), authorization.count > 7 else {
            throw SourceImportError.invalidSchema("PhoneBlock requires an authorized bearer token stored in Keychain.")
        }
        var previous = original
        let fingerprint = RowFingerprint.sha256(Array(authorization.utf8))
        if let old = previous.credentialFingerprint, old != fingerprint {
            try store.resetSourceEvidence(id: source.id)
            previous = try store.sourceState(id: source.id) ?? SourceState(sourceID: source.id)
        }
        let full = previous.publisherVersion == nil
        if full, let attempt = previous.lastFullAttemptAt, now < attempt.addingTimeInterval(30 * 86400) {
            previous.nextRefreshAt = attempt.addingTimeInterval(30 * 86400); try store.saveSourceState(previous, for: source, expectedImportRevision: previous.importRevision)
            throw SourceImportError.refreshNotDue
        }
        if let due = previous.nextRefreshAt, now < due { throw SourceImportError.refreshNotDue }
        previous.credentialFingerprint = fingerprint
        previous.nextRefreshAt = now.addingTimeInterval(86400 + Double.random(in: 0...1800))
        if full { previous.lastFullAttemptAt = now }
        try store.saveSourceState(previous, for: source, expectedImportRevision: previous.importRevision)
        var components = URLComponents(url: source.url, resolvingAgainstBaseURL: false)!
        if let version = previous.publisherVersion {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "since", value: String(version))]
        }
        guard let url = components.url else { throw SourceImportError.invalidURL }
        let response = try await fetch(url, headers: headers, maximumBytes: 32 * 1024 * 1024)
        let delta = try PhoneBlockSourceAdapter.parse(response.data, source: source, now: now)
        if let version = previous.publisherVersion {
            guard delta.version >= version,
                  delta.version != version || (delta.records.isEmpty && delta.removed.isEmpty) else {
                throw SourceImportError.invalidSchema("PhoneBlock version rolled back or changed without advancing.")
            }
        }
        if delta.hasInvalidRecords { throw SourceImportError.invalidSchema("PhoneBlock sync contains malformed records; its checkpoint and previous dataset are retained.") }
        var merged: [String: EvidenceRecord] = [:]
        if !full {
            for record in try store.evidence(enabledOnly: false) where record.sourceID == source.id { merged[record.id] = record }
        }
        for id in delta.removed { merged.removeValue(forKey: id) }
        for record in delta.records { merged[record.id] = record }
        let coverage = max(delta.watermark, merged.values.compactMap(\.activityAt).max() ?? .distantPast)
        let records = try merged.values.sorted { $0.id < $1.id }.map { value in
            var record = value; record.publisherWatermark = coverage
            return try EvidenceNormalization.normalize(record, source: source)
        }
        previous.publisherVersion = delta.version
        return (ParsedSourceImport(records: records, publisherWatermark: coverage, rejectedRecordCount: delta.rejected), previous)
    }

    private func downloadCallShield(source: SourceDefinition, previous: SourceState, now: Date,
                                    headers: [String: String]) async throws -> (ParsedSourceImport, SourceState) {
        let response = try await fetch(source.url, headers: headers, maximumBytes: 256 * 1024)
        let signatureURL = URL(string: source.url.absoluteString + ".sig")!
        let detached = try await fetch(signatureURL, headers: headers, maximumBytes: 4096)
        guard let signature = String(data: detached.data, encoding: .utf8) else { throw SourceImportError.invalidEncoding }
        let manifest = try CallShieldSourceAdapter.manifest(response.data, signature: signature, now: now)
        let digest = RowFingerprint.sha256(Array(response.data))
        let coverage = PublisherDate.calendar(manifest.updated)!
        if let version = previous.publisherVersion {
            guard manifest.version >= version,
                  manifest.version != version || previous.publisherDigest == digest,
                  previous.publisherWatermark.map({ coverage >= $0 }) ?? true else {
                throw SourceImportError.invalidSchema("CallShield attempted a database rollback or unversioned change.")
            }
        }
        let existing = try store.evidence(enabledOnly: false).filter { $0.sourceID == source.id }
        let cached = Dictionary(grouping: existing, by: { $0.publisherShardID ?? "" })
        let base = source.url.deletingLastPathComponent().deletingLastPathComponent()
        var records: [EvidenceRecord] = []; var rejected = 0; var digests: [String: String] = [:]
        for descriptor in manifest.shards {
            try Task.checkCancellation()
            if previous.shardDigests?[descriptor.id] == descriptor.sha256 {
                records.append(contentsOf: cached[descriptor.id] ?? [])
            } else {
                let shardURL = base.appendingPathComponent(descriptor.path)
                let response = try await fetch(shardURL, headers: headers, maximumBytes: descriptor.bytes)
                let parsed = try CallShieldSourceAdapter.shard(response.data, descriptor: descriptor,
                    source: source, watermark: coverage, now: now)
                records.append(contentsOf: parsed.records); rejected += parsed.rejectedRecordCount
            }
            digests[descriptor.id] = descriptor.sha256
            guard records.count <= SourceAdapters.maximumRecords else { throw SourceImportError.tooManyRecords }
        }
        guard Set(records.map(\.id)).count == records.count else {
            throw SourceImportError.invalidSchema("CallShield repeated evidence across shards.")
        }
        for i in records.indices { records[i].publisherWatermark = coverage }
        var state = previous; state.publisherVersion = manifest.version; state.publisherDigest = digest; state.shardDigests = digests
        return (ParsedSourceImport(records: records, publisherWatermark: coverage, rejectedRecordCount: rejected), state)
    }
}
