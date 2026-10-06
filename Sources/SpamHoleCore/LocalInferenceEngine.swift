import Foundation

public enum LocalBlockingDecision: String, Codable, Sendable {
    case sourceNotEligible, staleCoverage, noRecentObservedCall, insufficientEvidence
    case personalAllow, personalBlock, protectedContact, awaitingActivation, automaticBlock, capacityExcluded

    public var explanation: String {
        switch self {
        case .sourceNotEligible: "This source is not reviewed for automatic local blocking."
        case .staleCoverage: "Publisher coverage is older than seven days; automatic blocking is ineligible."
        case .noRecentObservedCall: "No qualifying observed call within seven days; automatic blocking is ineligible."
        case .insufficientEvidence: "Evidence does not meet the selected policy's score and persistence thresholds."
        case .personalAllow: "Your personal Allow rule takes priority."
        case .personalBlock: "Your personal Block rule takes priority over contact protection."
        case .protectedContact: "This number is in your accessible protected Contacts."
        case .awaitingActivation: "Eligible for automatic blocking after you review and activate protection."
        case .automaticBlock: "Selected for automatic blocking by your local reputation policy."
        case .capacityExcluded: "Eligible, but excluded from blocking by the selected device capacity."
        }
    }
}

/// Version 2 policy inference. Scores are not probabilities or proof of caller identity.
/// The version 1 confirmation classifier remains available only for reference parity.
public enum LocalInferenceEngine {
    public static let scoringVersion = 2

    public static func evaluate(independentFamilyValues: [Double], observedDays: Int,
                                positivePenalty: Double = 0, uncertaintyPenalty: Double = 0) throws -> ReputationResult {
        var result = try ReputationEngine.evaluate(independentFamilyValues: independentFamilyValues,
            observedDays: observedDays, positivePenalty: positivePenalty, uncertaintyPenalty: uncertaintyPenalty)
        result.localBlockingIndex = result.reportIndex * (0.5 + 0.5 * min(1, Double(observedDays) / 4))
            * (1 - positivePenalty) * (1 - uncertaintyPenalty)
        result.localReportIndex = result.reportIndex
        result.localObservedDays = observedDays
        return result
    }

    public static func qualifies(_ result: ReputationResult, policy: PolicyPreset) -> Bool {
        let thresholds = PolicyThresholds.forPreset(policy)
        guard let index = result.localBlockingIndex, index.isFinite, (0...100).contains(index),
              result.reportIndex.isFinite, (0...100).contains(result.reportIndex),
              (0...14).contains(result.observedDays) else { return false }
        return result.reportIndex >= thresholds.blockAssociation && index >= thresholds.blockSafety
            && result.observedDays >= thresholds.minimumObservedDays
    }
}
