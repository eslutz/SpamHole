import Foundation

public struct PolicyThresholds: Sendable, Equatable {
    public var identify: Double
    public var strongLabel: Double
    public var blockAssociation: Double
    public var blockSafety: Double
    public var minimumObservedDays: Int
    public static func forPreset(_ preset: PolicyPreset) -> PolicyThresholds {
        switch preset {
        case .conservative: .init(identify: 50, strongLabel: 80, blockAssociation: 90, blockSafety: 90, minimumObservedDays: 4)
        case .balanced: .init(identify: 35, strongLabel: 75, blockAssociation: 85, blockSafety: 75, minimumObservedDays: 3)
        case .aggressive: .init(identify: 20, strongLabel: 65, blockAssociation: 75, blockSafety: 60, minimumObservedDays: 2)
        }
    }
}

/// A deterministic policy index ported from the supplied reference, not a calibrated probability.
public enum ReputationEngine {
    private static func bounded(_ value: Double, name: String, lower: Double = 0, upper: Double = 1) throws -> Double {
        guard value.isFinite, (lower...upper).contains(value) else {
            throw SpamHoleCoreError.invalidValue("\(name) must be finite and between \(lower) and \(upper)")
        }
        return value
    }
    public static func sourceFreshness(watermarkAgeDays: Double) throws -> Double {
        guard watermarkAgeDays.isFinite, watermarkAgeDays >= 0 else {
            throw SpamHoleCoreError.invalidValue("Watermark age must be finite and nonnegative")
        }
        if watermarkAgeDays <= 3 { return 1 }
        if watermarkAgeDays > 14 { return 0 }
        return pow(2, -(watermarkAgeDays - 3) / 7)
    }
    public static func familyContribution(dailyWeightedCounts: [Int: Double], weight: Double = 1, freshness: Double = 1) throws -> Double {
        _ = try bounded(weight, name: "Weight"); _ = try bounded(freshness, name: "Freshness")
        var total = 0.0
        for (age, count) in dailyWeightedCounts.sorted(by: { $0.key < $1.key }) {
            guard age >= 0, count.isFinite, count >= 0 else {
                throw SpamHoleCoreError.invalidValue("Evidence ages and counts must be finite and nonnegative")
            }
            if age < 90 { total += pow(2, -Double(age) / 7) * min(count, 5) }
        }
        return min(25, weight * freshness * total)
    }
    public static func aggregateMembershipContribution(votesLowerBound: Double, freshness: Double = 1) throws -> Double {
        _ = try bounded(freshness, name: "Freshness")
        guard votesLowerBound.isFinite, votesLowerBound >= 0 else {
            throw SpamHoleCoreError.invalidValue("Votes must be finite and nonnegative")
        }
        return min(5, 0.5 * log2(1 + votesLowerBound)) * freshness
    }
    public static func evaluate(independentFamilyValues: [Double], confirmation: Double = 0,
                                confirmationAgeDays: Double = 0, confirmationUnexpired: Bool = true,
                                observedDays: Int = 0, positivePenalty: Double = 0, uncertaintyPenalty: Double = 0) throws -> ReputationResult {
        guard [0.0, 0.8, 1.0].contains(confirmation), confirmationAgeDays.isFinite,
              confirmationAgeDays >= 0, (0...14).contains(observedDays) else {
            throw SpamHoleCoreError.invalidValue("Invalid confirmation grade, age, or observed-day count")
        }
        _ = try bounded(positivePenalty, name: "Positive penalty")
        _ = try bounded(uncertaintyPenalty, name: "Uncertainty penalty")
        let values = try independentFamilyValues.map { try bounded($0, name: "Family value", upper: 25) }.sorted(by: >)
        var evidence = values.first ?? 0
        if values.count >= 2 { evidence += 0.35 * values[1] }
        evidence += 0.15 * min(10, values.dropFirst(2).reduce(0, +))
        let reportIndex = 100 * (1 - exp(-evidence / 8))
        let effectiveConfirmation = confirmationAgeDays > 7 || !confirmationUnexpired ? 0 : confirmation
        let freshness = effectiveConfirmation == 0 ? 0 : pow(2, -confirmationAgeDays / 14)
        let association = effectiveConfirmation == 0 ? reportIndex : max(reportIndex, 95 * freshness)
        let persistence = min(1, Double(observedDays) / 4)
        let blockSafety = association * effectiveConfirmation * (0.5 + 0.5 * persistence) * freshness
            * (1 - positivePenalty) * (1 - uncertaintyPenalty)
        return ReputationResult(evidence: evidence, reportIndex: reportIndex, associationIndex: association,
                                blockSafetyIndex: blockSafety, confirmation: effectiveConfirmation,
                                confirmationFreshness: freshness, observedDays: observedDays,
                                positivePenalty: positivePenalty, uncertaintyPenalty: uncertaintyPenalty)
    }
    public static func classify(_ result: ReputationResult, policy: PolicyPreset,
                                trustedInputsFresh: Bool = true, lastRelevantEvidenceAgeDays: Double = 0,
                                exactNumberValid: Bool = true, localAllow: Bool = false,
                                localManualBlock: Bool = false) throws -> ReputationClassification {
        guard lastRelevantEvidenceAgeDays.isFinite, lastRelevantEvidenceAgeDays >= 0 else {
            throw SpamHoleCoreError.invalidValue("Last evidence age must be finite and nonnegative")
        }
        if !exactNumberValid || localAllow { return .noAction }
        if localManualBlock { return .manualBlock }
        let thresholds = PolicyThresholds.forPreset(policy)
        if trustedInputsFresh && result.confirmation >= 0.8 && result.positivePenalty < 1 && result.uncertaintyPenalty < 1
            && result.observedDays >= thresholds.minimumObservedDays && result.associationIndex >= thresholds.blockAssociation
            && result.blockSafetyIndex >= thresholds.blockSafety { return .automaticBlock }
        if lastRelevantEvidenceAgeDays > 30 { return .noAction }
        if result.associationIndex >= thresholds.strongLabel { return .identifyManySpamReports }
        if result.associationIndex >= thresholds.identify { return .identifyReportedUnwanted }
        return .noAction
    }
}
