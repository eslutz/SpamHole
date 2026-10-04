import Foundation
import SpamHoleCore

struct PreparedProtectionSnapshot: Sendable {
    let snapshot: ProtectionSnapshot
    let assessmentPositions: [String: Int]

    init(snapshot: ProtectionSnapshot) {
        self.snapshot = snapshot
        // Store offsets rather than copying each assessment into the index.
        assessmentPositions = Dictionary(snapshot.assessments.enumerated().map { ($0.element.identifier, $0.offset) },
            uniquingKeysWith: { first, _ in first })
    }
    func assessment(for identifier: String) -> ReputationAssessment? {
        guard let offset = assessmentPositions[identifier] else { return nil }
        return snapshot.assessments[offset]
    }
}

/// Owns the expensive rebuild work off the UI actor. The store also serializes SQLite access.
actor ProtectionPipeline {
    let store: EvidenceStore
    let files: SnapshotFiles
    let downloader: SourceDownloader

    init(store: EvidenceStore, files: SnapshotFiles) {
        self.store = store
        self.files = files
        self.downloader = SourceDownloader(store: store, transport: BackgroundSourceTransport.shared)
    }

    func loadSavedSnapshot() throws -> PreparedProtectionSnapshot? {
        try Task.checkCancellation()
        do {
            let snapshot = try files.loadCurrent()
            try Task.checkCancellation()
            return PreparedProtectionSnapshot(snapshot: snapshot)
        } catch SpamHoleCoreError.snapshotUnavailable { return nil }
    }

    func installationReceipt() throws -> CallInstallationReceipt? {
        try files.loadInstallationReceipt()
    }

    func contactNumbers() throws -> Set<String> {
        try Task.checkCancellation()
        return try ContactsProtection.numbers()
    }

    func refresh(now: Date, testing: Bool, sourceIDs: Set<String>? = nil) async -> [String] {
        guard !testing else { return [] }
        var errors: [String] = []
        do {
            for source in try store.sources() where source.enabled && (sourceIDs?.contains(source.id) ?? true) {
                try Task.checkCancellation()
                do {
                    var headers: [String: String] = [:]
                    if let token = try KeychainCredentials.token(for: source.id) {
                        headers["Authorization"] = "Bearer \(token)"
                    }
                    _ = try await downloader.refresh(source: source, now: now, headers: headers)
                } catch is CancellationError { break }
                catch {
                    let detail = (error as? SourceImportError)?.localizedDescription ?? "Download failed; previous dataset retained."
                    errors.append("\(source.name): \(detail)")
                }
            }
        } catch { errors.append(error.localizedDescription) }
        return errors
    }

    func rebuild(settings: AppSettings, protectedContacts: Set<String>,
                 now: Date, identificationLimit: Int = 250_000, blockLimit: Int = 25_000) throws -> PreparedProtectionSnapshot {
        try Task.checkCancellation()
        let previous = try? files.loadCurrent()
        try Task.checkCancellation()
        let snapshot = try SnapshotBuilder(maxIdentificationEntries: identificationLimit, maxBlockingEntries: blockLimit)
            .build(evidence: store.evidence(), sources: store.sources(), rules: store.rules(),
                   settings: settings, protectedContacts: protectedContacts, previous: previous, now: now)
        try Task.checkCancellation()
        try files.publish(snapshot: snapshot)
        try store.saveGeneration(snapshot.metadata)
        return PreparedProtectionSnapshot(snapshot: snapshot)
    }
}
