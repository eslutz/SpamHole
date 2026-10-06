import Foundation
import CSQLite

public struct EvidenceStoreError: Error, LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { "Local database operation failed: \(message)" }
}

public struct DailyEvidenceCount: Sendable, Equatable {
    public let sourceFamilyID: String
    public let identifier: String
    public let day: Int
    public let weightedCount: Double
}

/// A single serialized SQLite connection. App-only database; extensions consume immutable exports.
public final class EvidenceStore: @unchecked Sendable {
    private var database: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database"
            if let database { sqlite3_close(database) }; database = nil
            throw EvidenceStoreError(message: message)
        }
        do {
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA foreign_keys=ON")
            try execute("PRAGMA busy_timeout=5000")
            let version = try query("PRAGMA user_version").first.flatMap { $0.first }.flatMap(Int.init) ?? 0
            guard version <= 2 else { throw SpamHoleCoreError.unsupportedSchema }
            if version == 0 {
                try transaction {
                    try execute("CREATE TABLE sources (id TEXT PRIMARY KEY, enabled INTEGER NOT NULL, payload BLOB NOT NULL)")
                    try execute("CREATE TABLE source_states (source_id TEXT PRIMARY KEY REFERENCES sources(id) ON DELETE CASCADE, payload BLOB NOT NULL)")
                    try execute("CREATE TABLE evidence (source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE, record_id TEXT NOT NULL, family_id TEXT NOT NULL, identifier TEXT NOT NULL, day INTEGER NOT NULL, weight REAL NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(source_id,record_id))")
                    try execute("CREATE INDEX evidence_sender ON evidence(identifier)")
                    try execute("CREATE INDEX evidence_lineage ON evidence(family_id,record_id)")
                    try execute("CREATE TABLE rules (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
                    try execute("CREATE TABLE settings (key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
                    try execute("CREATE TABLE generations (id TEXT PRIMARY KEY, installed INTEGER NOT NULL DEFAULT 0, payload BLOB NOT NULL)")
                    try execute("CREATE TABLE legacy_channel_data (kind TEXT NOT NULL, original_key TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(kind,original_key))")
                    try execute("PRAGMA user_version=2")
                }
            } else if version == 1 {
                try migrateLegacyChannels()
            }
        } catch { if let database { sqlite3_close(database) }; database = nil; throw error }
    }
    deinit { if let database { sqlite3_close(database) } }

    public func sources() throws -> [SourceDefinition] {
        try locked {
            try decodeRows("SELECT payload FROM sources ORDER BY id", as: SourceDefinition.self)
                .filter { $0.channels == [.call] && $0.format != .fccJSON }.map(SourceCatalog.canonicalize)
        }
    }
    public func saveSource(_ source: SourceDefinition) throws {
        try locked {
            try SourceCatalog.validateURL(source.url)
            try SourceCatalog.validateCallSource(source)
            let canonical = SourceCatalog.canonicalize(source)
            try execute("INSERT INTO sources(id,enabled,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET enabled=excluded.enabled,payload=excluded.payload",
                        [.text(canonical.id), .integer(canonical.enabled ? 1 : 0), .blob(try encoder.encode(canonical))])
        }
    }
    public func removeSource(id: String) throws {
        try locked { try execute("DELETE FROM sources WHERE id=?", [.text(id)]) }
    }
    public func sourceStates() throws -> [SourceState] {
        try locked { try decodeRows("SELECT payload FROM source_states ORDER BY source_id", as: SourceState.self) }
    }
    public func sourceState(id: String) throws -> SourceState? {
        try locked { try decodeRows("SELECT payload FROM source_states WHERE source_id=?", [.text(id)], as: SourceState.self).first }
    }
    public func saveSourceState(_ state: SourceState) throws {
        try locked {
            try execute("INSERT INTO source_states(source_id,payload) VALUES(?,?) ON CONFLICT(source_id) DO UPDATE SET payload=excluded.payload",
                        [.text(state.sourceID), .blob(try encoder.encode(state))])
        }
    }

    /// Updates contact/scheduling metadata without restoring a checkpoint captured before suspension.
    func saveSourceState(_ state: SourceState, for source: SourceDefinition, expectedImportRevision: String?) throws {
        try locked {
            try transaction {
                guard state.sourceID == source.id,
                      let current = try sources().first(where: { $0.id == source.id }), current.enabled,
                      current.url == source.url, current.format == source.format, current.channels == source.channels,
                      try sourceState(id: source.id)?.importRevision == expectedImportRevision else {
                    throw SourceImportError.sourceChanged
                }
                try saveSourceState(state)
            }
        }
    }

    /// A failed validation or insert rolls back the entire replacement and source-success state.
    /// Missing IDs in a successful full snapshot are removals; source disable/removal is immediate.
    public func replaceEvidence(_ records: [EvidenceRecord], source: SourceDefinition, state: SourceState,
                                requireCurrentSource: Bool = false, expectedImportRevision: String? = nil,
                                enforceRevision: Bool = false) throws {
        try locked {
            try SourceCatalog.validateCallSource(source)
            guard records.count <= SourceAdapters.maximumRecords, state.sourceID == source.id else {
                throw SourceImportError.invalidSchema("Replacement source identity or count is invalid.")
            }
            try transaction {
                if enforceRevision, try sourceState(id: source.id)?.importRevision != expectedImportRevision {
                    throw SourceImportError.sourceChanged
                }
                var canonical = SourceCatalog.canonicalize(source)
                if requireCurrentSource {
                    guard let current: SourceDefinition = try decodeRows("SELECT payload FROM sources WHERE id=?", [.text(source.id)], as: SourceDefinition.self).first,
                          current.url == source.url, current.format == source.format, current.channels == source.channels else {
                        throw SourceImportError.sourceChanged
                    }
                    // User changes made during network suspension take precedence over the stale request.
                    canonical = SourceCatalog.canonicalize(current)
                }
                try saveSource(canonical)
                try execute("DELETE FROM evidence WHERE source_id=?", [.text(source.id)])
                for original in records {
                    guard original.sourceID == source.id, !original.id.isEmpty, original.channel == .call,
                          (try? PhoneNormalizer.callNumber(original.numberE164)) == original.numberE164,
                          original.positivePenalty.isFinite, (0...1).contains(original.positivePenalty),
                          original.uncertaintyPenalty.isFinite, (0...1).contains(original.uncertaintyPenalty),
                          [0.0, 0.8, 1.0].contains(original.confirmationGrade) else {
                        throw SourceImportError.invalidSchema("Invalid evidence identity or policy values.")
                    }
                    var record = try EvidenceNormalization.normalize(original, source: canonical)
                    record.sourceFamilyID = canonical.sourceFamilyID
                    let trust = canonical.reviewedTrust
                    if trust?.confirmationAuthority != true || trust?.allowedConfirmationMethods.contains(record.confirmationMethod ?? "") != true {
                        record.confirmationGrade = 0; record.confirmationMethod = nil
                        record.confirmationReviewedAt = nil; record.confirmationExpiresAt = nil
                    }
                    let day = Int64(floor((record.observedAt ?? record.reportedAt).timeIntervalSince1970 / 86400))
                    try execute("INSERT INTO evidence(source_id,record_id,family_id,identifier,day,weight,payload) VALUES(?,?,?,?,?,?,?) ON CONFLICT(source_id,record_id) DO UPDATE SET family_id=excluded.family_id,identifier=excluded.identifier,day=excluded.day,weight=excluded.weight,payload=excluded.payload",
                                [.text(source.id), .text(record.id), .text(record.sourceFamilyID), .text(record.numberE164),
                                 .integer(day), .real(record.observedAt == nil ? 0.5 : 1), .blob(try encoder.encode(record))])
                }
                var updatedState = state; updatedState.recordCount = Set(records.map(\.id)).count
                updatedState.importRevision = UUID().uuidString
                updatedState.eventRecordCount = records.filter { !$0.isAggregate }.count
                updatedState.aggregateRecordCount = records.filter(\.isAggregate).count
                try saveSourceState(updatedState)
            }
        }
    }
    /// Preserve publisher cadence across credential rotation while invalidating account-bound data.
    public func resetSourceEvidence(id: String) throws {
        try locked {
            guard try sources().contains(where: { $0.id == id }) else { throw SourceImportError.sourceChanged }
            let old = try sourceState(id: id)
            try transaction {
                try execute("DELETE FROM evidence WHERE source_id=?", [.text(id)])
                var state = SourceState(sourceID: id)
                state.lastFullAttemptAt = old?.lastFullAttemptAt; state.nextRefreshAt = old?.nextRefreshAt
                state.importRevision = UUID().uuidString
                try saveSourceState(state)
            }
        }
    }

    public func evidence(enabledOnly: Bool = true) throws -> [EvidenceRecord] {
        try locked {
            let sql = "SELECT evidence.payload FROM evidence JOIN sources ON sources.id=evidence.source_id"
                + (enabledOnly ? " WHERE sources.enabled=1" : "") + " ORDER BY family_id,record_id,source_id"
            let records: [EvidenceRecord] = try decodeRows(sql, as: EvidenceRecord.self)
            var unique: [String: EvidenceRecord] = [:]
            let activeSourceIDs = Set(try sources().map(\.id))
            for record in records where record.channel == .call && activeSourceIDs.contains(record.sourceID) {
                let key = "\(record.sourceFamilyID.utf8.count):\(record.sourceFamilyID)\(record.id)"
                if let old = unique[key] {
                    if record.retractedAt != nil || (old.retractedAt == nil && record.publisherWatermark > old.publisherWatermark) { unique[key] = record }
                } else { unique[key] = record }
            }
            return unique.values.sorted { ($0.numberE164, $0.sourceFamilyID, $0.id) < ($1.numberE164, $1.sourceFamilyID, $1.id) }
        }
    }
    public func dailyCounts() throws -> [DailyEvidenceCount] {
        let records = try evidence()
        struct Key: Hashable { let family: String; let sender: String; let day: Int }
        var counts: [Key: Double] = [:]
        for record in records where record.retractedAt == nil && !record.isAggregate && record.numberRole == .displayedSender {
            let key = Key(family: record.sourceFamilyID, sender: record.numberE164,
                          day: Int(floor((record.observedAt ?? record.reportedAt).timeIntervalSince1970 / 86400)))
            counts[key, default: 0] += record.observedAt == nil ? 0.5 : 1
        }
        return counts.map { DailyEvidenceCount(sourceFamilyID: $0.key.family, identifier: $0.key.sender, day: $0.key.day, weightedCount: $0.value) }
            .sorted { ($0.sourceFamilyID, $0.identifier, $0.day) < ($1.sourceFamilyID, $1.identifier, $1.day) }
    }

    public func rules() throws -> [PersonalRule] {
        try locked { try decodeRows("SELECT payload FROM rules ORDER BY id", as: PersonalRule.self).filter { $0.channel == .call } }
    }
    public func saveRule(_ rule: PersonalRule) throws {
        try locked {
            try validateRule(rule)
            try writeRule(rule)
        }
    }
    public func deleteRule(id: String) throws { try locked { try execute("DELETE FROM rules WHERE id=?", [.text(id)]) } }
    public func replaceRules(_ rules: [PersonalRule]) throws {
        try locked {
            try validateRuleReplacement(rules)
            try transaction {
                try execute("DELETE FROM rules")
                for rule in rules { try writeRule(rule) }
            }
        }
    }
    /// Restore the backup's personal rules and app settings as one indivisible local change.
    public func restorePersonalState(rules: [PersonalRule], settings: AppSettings) throws {
        try locked {
            try validateRuleReplacement(rules)
            let settingsPayload = try encoder.encode(settings)
            try transaction {
                try execute("DELETE FROM rules")
                for rule in rules { try writeRule(rule) }
                try execute("INSERT INTO settings(key,payload) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload",
                            [.text("app-settings"), .blob(settingsPayload)])
            }
        }
    }
    public func setting<T: Decodable>(forKey key: String, as type: T.Type) throws -> T? {
        try locked { try decodeRows("SELECT payload FROM settings WHERE key=?", [.text(key)], as: type).first }
    }
    public func setSetting<T: Encodable>(_ value: T, forKey key: String) throws {
        try locked { try execute("INSERT INTO settings(key,payload) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload", [.text(key), .blob(try encoder.encode(value))]) }
    }
    public func saveGeneration(_ metadata: GenerationMetadata, installed: Bool = false) throws {
        try locked { try execute("INSERT INTO generations(id,installed,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET installed=excluded.installed,payload=excluded.payload",
                                 [.text(metadata.id.uuidString), .integer(installed ? 1 : 0), .blob(try encoder.encode(metadata))]) }
    }
    public func generations() throws -> [GenerationMetadata] { try locked { try decodeRows("SELECT payload FROM generations ORDER BY rowid DESC", as: GenerationMetadata.self) } }

    private enum Binding { case text(String), integer(Int64), real(Double), blob(Data) }
    private func validateRule(_ rule: PersonalRule) throws {
        guard rule.channel == .call else { throw SourceImportError.invalidSchema("Only call rules are supported.") }
        let normalized = try PhoneNormalizer.e164(rule.identifier)
        guard rule.identifier == normalized else { throw SpamHoleCoreError.invalidPhoneNumber }
    }

    /// Version 1 compatibility is local and one-way: preserve original mixed/text payloads in
    /// a dormant table, expose only valid call portions, and never reinterpret text evidence as calls.
    /// Dormant rows have no public accessor, export, source refresh, or snapshot publication path.
    private func migrateLegacyChannels() throws {
        try transaction {
            try execute("CREATE TABLE legacy_channel_data (kind TEXT NOT NULL, original_key TEXT NOT NULL, payload BLOB NOT NULL, PRIMARY KEY(kind,original_key))")
            let oldSources = try decodeRows("SELECT payload FROM sources ORDER BY id", as: SourceDefinition.self)
            let oldEvidence = try decodeRows("SELECT payload FROM evidence", as: EvidenceRecord.self)
            let oldRules = try decodeRows("SELECT payload FROM rules", as: PersonalRule.self)
            var retainedSourceIDs = Set<String>()
            var remainingCounts: [String: Int] = [:]
            for var source in oldSources {
                let hasCallPortion = source.format != .fccJSON && source.channels.contains { $0 == .call || $0 == .both }
                if source.channels != [.call] || !hasCallPortion {
                    try execute("INSERT INTO legacy_channel_data(kind,original_key,payload) SELECT 'source',id,payload FROM sources WHERE id=?", [.text(source.id)])
                    try execute("INSERT INTO legacy_channel_data(kind,original_key,payload) SELECT 'source-state',source_id,payload FROM source_states WHERE source_id=?", [.text(source.id)])
                }
                if hasCallPortion {
                    retainedSourceIDs.insert(source.id)
                    if source.channels != [.call] {
                        source.channels = [.call]
                        try execute("UPDATE sources SET payload=? WHERE id=?", [.blob(try encoder.encode(source)), .text(source.id)])
                    }
                }
            }
            for var record in oldEvidence {
                let canonical = try? PhoneNormalizer.callNumber(record.numberE164)
                let retain = retainedSourceIDs.contains(record.sourceID) && record.channel != .sms && canonical != nil
                if !retain || record.channel != .call || canonical != record.numberE164 {
                    let key = "\(record.sourceID.utf8.count):\(record.sourceID)\(record.id)"
                    try execute("INSERT INTO legacy_channel_data(kind,original_key,payload) SELECT 'evidence',?,payload FROM evidence WHERE source_id=? AND record_id=?",
                        [.text(key), .text(record.sourceID), .text(record.id)])
                }
                if retain, let canonical {
                    remainingCounts[record.sourceID, default: 0] += 1
                    if record.channel != .call || canonical != record.numberE164 {
                        record.channel = .call; record.numberE164 = canonical
                        try execute("UPDATE evidence SET identifier=?,payload=? WHERE source_id=? AND record_id=?",
                            [.text(canonical), .blob(try encoder.encode(record)), .text(record.sourceID), .text(record.id)])
                    }
                } else {
                    try execute("DELETE FROM evidence WHERE source_id=? AND record_id=?", [.text(record.sourceID), .text(record.id)])
                }
            }
            for source in oldSources {
                if !retainedSourceIDs.contains(source.id) {
                    try execute("DELETE FROM sources WHERE id=?", [.text(source.id)])
                } else if var state = try sourceState(id: source.id) {
                    let count = remainingCounts[source.id] ?? 0
                    if state.recordCount != count {
                        try execute("INSERT OR IGNORE INTO legacy_channel_data(kind,original_key,payload) SELECT 'source-state',source_id,payload FROM source_states WHERE source_id=?", [.text(source.id)])
                        state.recordCount = count
                        try saveSourceState(state)
                    }
                }
            }
            for var rule in oldRules {
                let canonical = try? PhoneNormalizer.callNumber(rule.identifier)
                let retain = rule.channel != .sms && canonical != nil
                if !retain || rule.channel != .call || canonical != rule.identifier {
                    try execute("INSERT INTO legacy_channel_data(kind,original_key,payload) SELECT 'rule',id,payload FROM rules WHERE id=?", [.text(rule.id)])
                }
                if retain, let canonical {
                    if rule.channel != .call || canonical != rule.identifier {
                        rule.channel = .call; rule.identifier = canonical
                        try writeRule(rule)
                    }
                } else { try execute("DELETE FROM rules WHERE id=?", [.text(rule.id)]) }
            }
            try execute("PRAGMA user_version=2")
        }
    }
    private func validateRuleReplacement(_ rules: [PersonalRule]) throws {
        guard rules.count <= 100_000, Set(rules.map(\.id)).count == rules.count else {
            throw SourceImportError.invalidSchema("The rule backup contains too many rules or duplicate IDs.")
        }
        for rule in rules { try validateRule(rule) }
    }
    private func writeRule(_ rule: PersonalRule) throws {
        try execute("INSERT INTO rules(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",
                    [.text(rule.id), .blob(try encoder.encode(rule))])
    }
    private func locked<T>(_ action: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try action() }
    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do { let result = try action(); try execute("COMMIT"); return result }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func prepare(_ sql: String, _ bindings: [Binding]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw databaseError() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1); let result: Int32
            switch binding {
            case .text(let value): result = sqlite3_bind_text(statement, index, value, -1, transient)
            case .integer(let value): result = sqlite3_bind_int64(statement, index, value)
            case .real(let value): result = sqlite3_bind_double(statement, index, value)
            case .blob(let value): result = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
            }
            guard result == SQLITE_OK else { sqlite3_finalize(statement); throw databaseError() }
        }
        return statement
    }
    private func execute(_ sql: String, _ bindings: [Binding] = []) throws {
        let statement = try prepare(sql, bindings); defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw databaseError() }
    }
    private func query(_ sql: String) throws -> [[String]] {
        let statement = try prepare(sql, []); defer { sqlite3_finalize(statement) }
        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { index in sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" })
        }
        return rows
    }
    private func decodeRows<T: Decodable>(_ sql: String, _ bindings: [Binding] = [], as type: T.Type) throws -> [T] {
        let statement = try prepare(sql, bindings); defer { sqlite3_finalize(statement) }
        var values: [T] = []; var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { throw EvidenceStoreError(message: "Missing stored payload") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            values.append(try decoder.decode(type, from: data)); status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw databaseError() }
        return values
    }
    private func databaseError() -> EvidenceStoreError {
        EvidenceStoreError(message: database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database unavailable")
    }
}
