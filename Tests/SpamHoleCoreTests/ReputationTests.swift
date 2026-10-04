import XCTest
@testable import SpamHoleCore

final class ReputationTests: XCTestCase {
    private struct Fixture: Decodable { let checks_passed: Int; let examples: [String: Example] }
    private struct Example: Decodable {
        let family_values: [Double]
        let E: Double; let S: Double; let B: Double
        let classification: [String: String]
    }
    func testEverySuppliedWorkedExampleMatchesReference() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "spam_reputation_worked_examples_20261003", withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "spam_reputation_worked_examples_20261003", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.checks_passed, 123)
        for (name, example) in fixture.examples {
            var grade = 0.0; var age = 0.0; var days = 0; var positive = 0.0; var uncertainty = 0.0
            switch name {
            case "one_complaint": days = 1
            case "100_complaints_one_day": days = 1; uncertainty = 0.5
            case "seven_days_one_family_and_any_number_of_mirrors", "seven_days_two_families": days = 7
            case "strong_current_origin_confirmation": grade = 1; days = 7
            case "one_origin_confirmation_provider": grade = 0.8; days = 7
            case "legitimate_outgoing_or_spoof_conflict": grade = 1; days = 7; positive = 1
            case "all_evidence_28_days_older": grade = 1; age = 28
            case "verified_assignment_reset": break
            default: XCTFail("Unrecognized reference example: \(name)")
            }
            let result = try ReputationEngine.evaluate(independentFamilyValues: example.family_values,
                confirmation: grade, confirmationAgeDays: age, observedDays: days,
                positivePenalty: positive, uncertaintyPenalty: uncertainty)
            XCTAssertEqual(result.evidence, example.E, accuracy: 1e-12, name)
            XCTAssertEqual(result.associationIndex, example.S, accuracy: 1e-12, name)
            XCTAssertEqual(result.blockSafetyIndex, example.B, accuracy: 1e-12, name)
            for policy in PolicyPreset.allCases {
                XCTAssertEqual(try ReputationEngine.classify(result, policy: policy).rawValue, example.classification[policy.rawValue], name)
            }
        }
    }
    func testReferenceDecayCapsFreshnessAndPersistenceMatrix() throws {
        XCTAssertEqual(try ReputationEngine.familyContribution(dailyWeightedCounts: [0: 100]), 5)
        XCTAssertEqual(try ReputationEngine.familyContribution(dailyWeightedCounts: [0: 1, 7: 2]), 2)
        XCTAssertEqual(try ReputationEngine.familyContribution(dailyWeightedCounts: [90: 500]), 0)
        XCTAssertEqual(try ReputationEngine.familyContribution(dailyWeightedCounts: Dictionary(uniqueKeysWithValues: (0..<90).map { ($0, 500.0) })), 25)
        XCTAssertEqual(try ReputationEngine.sourceFreshness(watermarkAgeDays: 3), 1)
        XCTAssertEqual(try ReputationEngine.sourceFreshness(watermarkAgeDays: 10), 0.5)
        XCTAssertEqual(try ReputationEngine.sourceFreshness(watermarkAgeDays: 15), 0)
        for grade in [0.0, 0.8, 1] {
            for days in [0, 1, 2, 3, 4, 7, 14] {
                for age in [0.0, 3, 7, 8, 28] {
                    let result = try ReputationEngine.evaluate(independentFamilyValues: [25, 20, 10], confirmation: grade,
                                                               confirmationAgeDays: age, observedDays: days)
                    XCTAssertGreaterThanOrEqual(result.blockSafetyIndex, 0)
                    XCTAssertLessThanOrEqual(result.blockSafetyIndex, result.associationIndex)
                    XCTAssertLessThanOrEqual(result.associationIndex, 100)
                    if grade == 0 || age > 7 { XCTAssertEqual(result.blockSafetyIndex, 0) }
                }
            }
        }
    }
    func testVetoesAndThresholdBoundaries() throws {
        let high = try ReputationEngine.evaluate(independentFamilyValues: [25, 25], confirmation: 1, observedDays: 7)
        XCTAssertEqual(try ReputationEngine.classify(high, policy: .conservative), .automaticBlock)
        XCTAssertEqual(try ReputationEngine.classify(high, policy: .aggressive, localAllow: true, localManualBlock: true), .noAction)
        XCTAssertNotEqual(try ReputationEngine.classify(high, policy: .aggressive, trustedInputsFresh: false), .automaticBlock)
        XCTAssertEqual(try ReputationEngine.classify(high, policy: .aggressive, exactNumberValid: false, localManualBlock: true), .noAction)
        for penalty in [0.0, 1] {
            let result = try ReputationEngine.evaluate(independentFamilyValues: [25], confirmation: 1,
                confirmationUnexpired: penalty == 0, observedDays: 7, positivePenalty: penalty)
            if penalty == 1 { XCTAssertEqual(result.blockSafetyIndex, 0) }
        }
        let many = try ReputationEngine.evaluate(independentFamilyValues: [25])
        XCTAssertEqual(try ReputationEngine.classify(many, policy: .balanced, lastRelevantEvidenceAgeDays: 31), .noAction)
        XCTAssertEqual(try ReputationEngine.classify(many, policy: .balanced, lastRelevantEvidenceAgeDays: 30), .identifyManySpamReports)
    }
    func testRejectsNonFiniteAndOutOfRangeInputs() {
        XCTAssertThrowsError(try ReputationEngine.sourceFreshness(watermarkAgeDays: .nan))
        XCTAssertThrowsError(try ReputationEngine.sourceFreshness(watermarkAgeDays: -1))
        XCTAssertThrowsError(try ReputationEngine.familyContribution(dailyWeightedCounts: [-1: 1]))
        XCTAssertThrowsError(try ReputationEngine.familyContribution(dailyWeightedCounts: [0: .infinity]))
        XCTAssertThrowsError(try ReputationEngine.familyContribution(dailyWeightedCounts: [0: 1], weight: 1.1))
        XCTAssertThrowsError(try ReputationEngine.evaluate(independentFamilyValues: [26]))
        XCTAssertThrowsError(try ReputationEngine.evaluate(independentFamilyValues: [1], confirmation: 0.9))
        XCTAssertThrowsError(try ReputationEngine.evaluate(independentFamilyValues: [1], observedDays: 15))
        XCTAssertThrowsError(try ReputationEngine.evaluate(independentFamilyValues: [1], positivePenalty: .nan))
        XCTAssertThrowsError(try ReputationEngine.aggregateMembershipContribution(votesLowerBound: -1))
    }
}
