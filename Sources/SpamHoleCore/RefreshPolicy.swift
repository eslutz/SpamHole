import Foundation

/// Decides automatic update eligibility per source. An explicit user refresh bypasses this helper.
public enum RefreshPolicy {
    public static let automaticRetryInterval: TimeInterval = 15 * 60

    public static func dueSourceIDs(sources: [SourceDefinition], states: [SourceState],
                                    cadence: RefreshCadence, now: Date = Date()) -> Set<String> {
        let interval: TimeInterval
        switch cadence {
        case .manual: return []
        case .daily: interval = 24 * 60 * 60
        case .weekly: interval = 7 * 24 * 60 * 60
        }
        var stateByID: [String: SourceState] = [:]
        for state in states { stateByID[state.sourceID] = state }
        return Set(sources.filter { source in
            guard source.enabled else { return false }
            let state = stateByID[source.id]
            let pastCadence = state?.lastSuccessAt.map { now.timeIntervalSince($0) >= interval } ?? true
            guard pastCadence else { return false }
            if let attempt = state?.lastAttemptAt {
                let elapsed = now.timeIntervalSince(attempt)
                if elapsed >= 0 && elapsed < automaticRetryInterval { return false }
            }
            return true
        }.map(\.id))
    }
}
