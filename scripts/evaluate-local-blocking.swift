import Foundation

/// Compile with Sources/SpamHoleCore/*.swift and Sources/CSQLite; emits aggregates only.
/// --download-ftc uses a fresh temporary database which is removed after evaluation.
/// --store-copy PATH accepts only a private copy, since opening SQLite can create sidecars.
@main
enum EvaluateLocalBlocking {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("SpamHole-Evaluation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let now = Date()
        let store: EvidenceStore
        if arguments == ["--download-ftc"] {
            store = try EvidenceStore(url: temporary.appendingPathComponent("evidence.sqlite"))
            let source = SourceCatalog.builtIns[0]
            try store.saveSource(source)
            _ = try await SourceDownloader(store: store).refresh(source: source, now: now)
        } else if arguments.count == 2 && arguments[0] == "--store-copy" {
            store = try EvidenceStore(url: URL(fileURLWithPath: arguments[1]))
        } else {
            throw SpamHoleCoreError.invalidValue("Use --download-ftc or --store-copy PATH (private copy only).")
        }
        let sources = try store.sources().filter { $0.id == "ftc-dnc" }
        let states = try store.sourceStates().filter { $0.sourceID == "ftc-dnc" }
        let records = try store.evidence().filter { $0.sourceID == "ftc-dnc" }
        var summaries: [[String: Any]] = []
        for policy in PolicyPreset.allCases {
            let snapshot = try SnapshotBuilder().build(evidence: records, sources: sources, rules: [],
                settings: AppSettings(policy: policy, automaticBlockingEnabled: true), sourceStates: states, now: now)
            let report = snapshot.assessments.compactMap(\.result.localReportIndex).sorted()
            let local = snapshot.assessments.compactMap(\.result.localBlockingIndex).sorted()
            func distribution(_ values: [Double]) -> [String: Double] {
                guard !values.isEmpty else { return [:] }
                return ["p50": values[values.count / 2], "p90": values[Int(Double(values.count - 1) * 0.9)],
                    "p99": values[Int(Double(values.count - 1) * 0.99)], "max": values.last!]
            }
            summaries.append(["policy": policy.rawValue, "assessments": snapshot.assessments.count,
                "identificationEntries": snapshot.callIdentification.count, "automaticBlocks": snapshot.callBlocking.count,
                "capacityExcluded": snapshot.metadata.capacityExcludedCount ?? 0,
                "reportIndex": distribution(report), "localBlockingIndex": distribution(local)])
        }
        let output: [String: Any] = ["scoringVersion": 2, "evaluatedAt": ISO8601DateFormatter().string(from: now),
            "publisherCoverage": states.compactMap(\.publisherWatermark).max().map { ISO8601DateFormatter().string(from: $0) } ?? "unavailable",
            "records": records.count, "personalRulesApplied": 0, "contactsApplied": false, "policies": summaries]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
