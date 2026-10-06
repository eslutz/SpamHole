import Foundation

/// Compile with Sources/SpamHoleCore/*.swift and -I Sources/CSQLite.
/// Downloads public FCC/CallShield datasets into an isolated, disposable store.
/// Emits counts and controlled failure messages only; never prints caller numbers.
@main
enum ValidateAdditionalSources {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpamHole-SourceValidation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EvidenceStore(url: root.appendingPathComponent("evidence.sqlite"))
        let downloader = SourceDownloader(store: store)
        var failures = 0
        for id in ["fcc-calls", "callshield"] {
            var source = SourceCatalog.builtIns.first { $0.id == id }!
            source.enabled = true
            try store.saveSource(source)
            let started = Date()
            do {
                let result = try await downloader.refresh(source: source)
                let records = try store.evidence().filter { $0.sourceID == id }
                guard records.count == result.recordCount else { throw SourceImportError.invalidSchema("Stored readback count differs.") }
                let events = records.filter { !$0.isAggregate }.count
                let summaries = records.count - events
                print("\(id): passed; records=\(records.count); events=\(events); summaries=\(summaries); excluded=\(result.rejectedRecordCount); seconds=\(Int(Date().timeIntervalSince(started)))")
            } catch {
                failures += 1
                let message = (error as? SourceImportError)?.localizedDescription ?? "Download or import failed."
                print("\(id): failed; \(message)")
            }
        }
        if failures > 0 { throw SpamHoleCoreError.invalidValue("Public source validation failed; review the controlled results above.") }
    }
}
