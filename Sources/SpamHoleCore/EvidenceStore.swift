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
            guard version <= 1 else { throw SpamHoleCoreError.unsupportedSchema }
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
                    try execute("PRAGMA user_version=1")
                }
            }
        } catch { if let database { sqlite3_close(database) }; database = nil; throw error }
    }
    deinit { if let database { sqlite3_close(database) } }

    public func sources() throws -> [SourceDefinition] {
        try locked { try decodeRows("SELECT payload FROM sources ORDER BY id", as: SourceDefinition.self).map(SourceCatalog.canonicalize) }
    }
    public func saveSource(_ source: SourceDefinition) throws {
        try locked {
            try SourceCatalog.validateURL(source.url)
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

    /// A failed validation or insert rolls back the entire replacement and source-success state.
    /// Missing IDs in a successful full snapshot are removals; source disable/removal is immediate.
    public func replaceEvidence(_ records: [EvidenceRecord], source: SourceDefinition, state: SourceState,
                                requireCurrentSource: Bool = false) throws {
        try locked {
            guard records.count <= SourceAdapters.maximumRecords, state.sourceID == source.id else {
                throw SourceImportError.invalidSchema("Replacement source identity or count is invalid.")
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
            try transaction {
                try saveSource(canonical)
                try execute("DELETE FROM evidence WHERE source_id=?", [.text(source.id)])
                for original in records {
                    guard original.sourceID == source.id, !original.id.isEmpty,
                          original.positivePenalty.isFinite, (0...1).contains(original.positivePenalty),
                          original.uncertaintyPenalty.isFinite, (0...1).contains(original.uncertaintyPenalty),
                          [0.0, 0.8, 1.0].contains(original.confirmationGrade) else {
                        throw SourceImportError.invalidSchema("Invalid evidence identity or policy values.")
                    }
                    var record = original
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
                try saveSourceState(updatedState)
            }
        }
    }
    public func evidence(enabledOnly: Bool = true) throws -> [EvidenceRecord] {
        try locked {
            let sql = "SELECT evidence.payload FROM evidence JOIN sources ON sources.id=evidence.source_id"
                + (enabledOnly ? " WHERE sources.enabled=1" : "") + " ORDER BY family_id,record_id,source_id"
            let records: [EvidenceRecord] = try decodeRows(sql, as: EvidenceRecord.self)
            var unique: [String: EvidenceRecord] = [:]
            for record in records {
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
        for record in records where record.retractedAt == nil && record.numberRole == .displayedSender {
            let key = Key(family: record.sourceFamilyID, sender: record.numberE164,
                          day: Int(floor((record.observedAt ?? record.reportedAt).timeIntervalSince1970 / 86400)))
            counts[key, default: 0] += record.observedAt == nil ? 0.5 : 1
        }
        return counts.map { DailyEvidenceCount(sourceFamilyID: $0.key.family, identifier: $0.key.sender, day: $0.key.day, weightedCount: $0.value) }
            .sorted { ($0.sourceFamilyID, $0.identifier, $0.day) < ($1.sourceFamilyID, $1.identifier, $1.day) }
    }

    public func rules() throws -> [PersonalRule] { try locked { try decodeRows("SELECT payload FROM rules ORDER BY id", as: PersonalRule.self) } }
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
        let normalized = rule.channel == .sms ? try PhoneNormalizer.smsIdentifier(rule.identifier) : try PhoneNormalizer.e164(rule.identifier)
        guard rule.identifier == normalized else { throw SpamHoleCoreError.invalidSenderIdentifier }
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
