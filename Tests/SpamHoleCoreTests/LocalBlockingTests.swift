import XCTest
@testable import SpamHoleCore

final class LocalBlockingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_158_400)
    private let number = "+12025550100"
    private var ftc: SourceDefinition { SourceCatalog.builtIns[0] }

    private func settings(_ policy: PolicyPreset = .balanced, enabled: Bool = true,
                          contacts: Bool = false) throws -> AppSettings {
        // Exercises the persisted-settings boundary, including the legacy decoder.
        try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: [
            "policy": policy.rawValue, "cadence": "daily", "contactProtection": contacts,
            "automaticBlockingEnabled": enabled
        ]))
    }

    private func reports(days: Int = 7, perDay: Int = 5, identifier: String? = nil,
                         coverageAge: Double = 0, eventOffset: Double = 0) -> [EvidenceRecord] {
        (0..<days).flatMap { day in (0..<perDay).map { report in
            EvidenceRecord(id: "\(identifier ?? number)-\(day)-\(report)", sourceID: ftc.id,
                sourceFamilyID: ftc.sourceFamilyID, numberE164: identifier ?? number, channel: .call,
                observedAt: now.addingTimeInterval(-(Double(day) + eventOffset) * 86_400),
                reportedAt: now.addingTimeInterval(-coverageAge * 86_400),
                publisherWatermark: now.addingTimeInterval(-coverageAge * 86_400))
        } }
    }

    private func build(_ records: [EvidenceRecord], policy: PolicyPreset = .balanced,
                       enabled: Bool = true, rules: [PersonalRule] = [], contacts: Set<String> = [],
                       capacity: Int = 25_000, sources: [SourceDefinition]? = nil,
                       previous: ProtectionSnapshot? = nil) throws -> ProtectionSnapshot {
        try SnapshotBuilder(maxBlockingEntries: capacity).build(evidence: records, sources: sources ?? [ftc],
            rules: rules, settings: settings(policy, enabled: enabled, contacts: !contacts.isEmpty),
            protectedContacts: contacts, previous: previous, now: now)
    }

    func testFTCAloneGeneratesBlocksWithoutConfirmationOrPersonalRules() throws {
        let snapshot = try build(reports())
        XCTAssertEqual(snapshot.callBlocking, [1_202_555_0100])
        XCTAssertTrue(snapshot.callIdentification.isEmpty)
        XCTAssertEqual(snapshot.assessments.first?.classification, .automaticBlock)
        XCTAssertEqual(snapshot.assessments.first?.result.confirmation, 0)
        try snapshot.validate()
    }

    func testPoliciesProduceNestedDistinctBlocklists() throws {
        let aggressive = "+12025550101", balanced = "+12025550102"
        let records = reports(days: 3, identifier: aggressive) + reports(days: 4, identifier: balanced) + reports()
        let conservativeBlocks = Set(try build(records, policy: .conservative).callBlocking)
        let balancedBlocks = Set(try build(records, policy: .balanced).callBlocking)
        let aggressiveBlocks = Set(try build(records, policy: .aggressive).callBlocking)
        XCTAssertEqual(conservativeBlocks.count, 1)
        XCTAssertEqual(balancedBlocks.count, 2)
        XCTAssertEqual(aggressiveBlocks.count, 3)
        XCTAssertTrue(conservativeBlocks.isSubset(of: balancedBlocks))
        XCTAssertTrue(balancedBlocks.isSubset(of: aggressiveBlocks))
    }

    func testReviewPreviewDoesNotInstallAutomaticBlocks() throws {
        let snapshot = try build(reports(), enabled: false)
        XCTAssertTrue(snapshot.callBlocking.isEmpty)
        XCTAssertEqual(snapshot.callIdentification.count, 1)
        let metadata = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot.metadata)) as? [String: Any])
        XCTAssertEqual(metadata["eligibleAutomaticCount"] as? Int, 1)
        XCTAssertEqual(metadata["exportedAutomaticCount"] as? Int, 0)
        XCTAssertEqual(metadata["scoringVersion"] as? Int, 2)
    }

    func testOverridesCapacityAndDisabledSources() throws {
        let other = "+12025550101"
        let records = reports() + reports(identifier: other)
        XCTAssertTrue(try build(records, rules: [.init(identifier: number, action: .allow)], contacts: [other]).callBlocking.isEmpty)
        XCTAssertEqual(try build(reports(), rules: [.init(identifier: number, action: .block)], contacts: [number]).callBlocking, [1_202_555_0100])
        XCTAssertTrue(try build(reports(), rules: [.init(identifier: number, action: .block), .init(identifier: number, action: .allow)]).callBlocking.isEmpty)
        let personal = PersonalRule(identifier: "+12025550103", action: .block)
        XCTAssertEqual(try build(records, rules: [personal], capacity: 1).callBlocking, [1_202_555_0103])
        XCTAssertEqual(try build(records, capacity: 1).callBlocking, [1_202_555_0100])
        var disabled = ftc; disabled.enabled = false
        XCTAssertTrue(try build(records, sources: [disabled]).callBlocking.isEmpty)
        XCTAssertTrue(try build(records, sources: []).callBlocking.isEmpty)
    }

    func testStaleUndatedAndConcentratedReportsNeverBlock() throws {
        XCTAssertTrue(try build(reports(coverageAge: 8, eventOffset: 8), policy: .aggressive).callBlocking.isEmpty)
        XCTAssertTrue(try build(reports(eventOffset: 8), policy: .aggressive).callBlocking.isEmpty)
        var undated = reports(days: 30)
        for i in undated.indices { undated[i].observedAt = nil }
        XCTAssertTrue(try build(undated, policy: .aggressive).callBlocking.isEmpty)
        XCTAssertTrue(try build(reports(days: 1, perDay: 1_000), policy: .aggressive).callBlocking.isEmpty)
        let fresh = try build(reports())
        XCTAssertTrue(try build([], previous: fresh).callBlocking.isEmpty)
        let retracted = reports().map { record in var value = record; value.retractedAt = now; return value }
        XCTAssertTrue(try build(retracted, previous: fresh).callBlocking.isEmpty)
        let callback = reports().map { record in var value = record; value.numberRole = .callback; return value }
        XCTAssertTrue(try build(callback).callBlocking.isEmpty)
    }

    func testDuplicateAndForgedSourcesCannotIncreaseBlockAuthority() throws {
        let records = reports()
        XCTAssertEqual(try build(records + records).assessments.first?.result.localBlockingIndex,
                       try build(records).assessments.first?.result.localBlockingIndex)
        var forged = ftc
        forged.url = URL(string: "https://example.org/not-ftc")!
        forged.reviewedTrust?.localInferenceEligible = true
        XCTAssertTrue(try build(records, sources: [forged]).callBlocking.isEmpty)
        XCTAssertEqual(try build(records, sources: [forged]).assessments.first?.localDecision, .sourceNotEligible)
        forged = ftc; forged.id = "mirror"; forged.sourceFamilyID = "different-family"
        let mirrored = records.map { original in var value = original; value.sourceID = "mirror"; return value }
        XCTAssertEqual(try build(records + mirrored, sources: [ftc, forged]).assessments.first?.result.localBlockingIndex,
                       try build(records).assessments.first?.result.localBlockingIndex)
    }

    func testPersistedCoverageDoesNotBecomeFreshFromRecentDownloadOrRecord() throws {
        let state = SourceState(sourceID: ftc.id, lastSuccessAt: now,
            publisherWatermark: now.addingTimeInterval(-8 * 86_400))
        let snapshot = try SnapshotBuilder().build(evidence: reports(), sources: [ftc], rules: [],
            settings: settings(), sourceStates: [state], now: now)
        XCTAssertTrue(snapshot.callBlocking.isEmpty)
        XCTAssertEqual(snapshot.assessments.first?.localDecision, .staleCoverage)
    }

    func testLegacySettingsTrustAndSnapshotDecodeWithoutActivation() throws {
        let legacy = Data(#"{"policy":"aggressive","cadence":"weekly","contactProtection":true}"#.utf8)
        let value = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertFalse(value.automaticBlockingEnabled)
        XCTAssertEqual(value.policy, .aggressive)
        let oldTrust = Data(#"{"familyWeight":1,"confirmationAuthority":false,"allowedConfirmationMethods":[],"maximumConfirmationGrade":0}"#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(ReviewedSourceTrust.self, from: oldTrust).localInferenceEligible)
        let metadata = GenerationMetadata(callIdentificationCount: 0, callBlockCount: 0, policy: .balanced)
        let old = ProtectionSnapshot(metadata: metadata, callIdentification: [], callBlocking: [])
        let decoded = try JSONDecoder().decode(ProtectionSnapshot.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.metadata.scoringVersion)
        try decoded.validate()
        XCTAssertEqual(try build(reports(), enabled: value.automaticBlockingEnabled).callBlocking, [])
    }

    func testCapacityReasonsAndOriginCountsMatchActualExports() throws {
        let records = reports() + reports(identifier: "+12025550101")
        let value = try build(records, capacity: 1)
        XCTAssertEqual(value.metadata.eligibleAutomaticCount, 2)
        XCTAssertEqual(value.metadata.exportedAutomaticCount, 1)
        XCTAssertEqual(value.metadata.personalBlockCount, 0)
        XCTAssertEqual(value.metadata.capacityExcludedCount, 1)
        XCTAssertEqual(value.assessments.last?.localDecision, .capacityExcluded)
        XCTAssertNotEqual(value.assessments.last?.classification, .automaticBlock)
        var corrupt = value; corrupt.metadata.personalBlockCount = 1
        XCTAssertThrowsError(try corrupt.validate())
        XCTAssertThrowsError(try build(records, rules: [.init(identifier: number, action: .block)], capacity: 0))
    }

    func testVersionTwoReferenceParityAndThresholdBoundaries() throws {
        struct Fixture: Decodable { let scoringVersion: Int; let examples: [String: Example] }
        struct Example: Decodable {
            let values: [Double]; let days: Int; let positive: Double; let uncertainty: Double
            let E: Double; let R: Double; let L: Double; let blocks: [String: Bool]
        }
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "local_inference_v2", withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "local_inference_v2", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.scoringVersion, LocalInferenceEngine.scoringVersion)
        for (name, example) in fixture.examples {
            let result = try LocalInferenceEngine.evaluate(independentFamilyValues: example.values,
                observedDays: example.days, positivePenalty: example.positive, uncertaintyPenalty: example.uncertainty)
            XCTAssertEqual(result.evidence, example.E, accuracy: 1e-12, name)
            XCTAssertEqual(result.reportIndex, example.R, accuracy: 1e-12, name)
            XCTAssertEqual(try XCTUnwrap(result.localBlockingIndex), example.L, accuracy: 1e-12, name)
            for policy in PolicyPreset.allCases {
                XCTAssertEqual(LocalInferenceEngine.qualifies(result, policy: policy), example.blocks[policy.rawValue], name)
            }
        }
        for policy in PolicyPreset.allCases {
            let threshold = PolicyThresholds.forPreset(policy)
            var exact = try LocalInferenceEngine.evaluate(independentFamilyValues: [25], observedDays: threshold.minimumObservedDays)
            exact.reportIndex = threshold.blockAssociation; exact.localBlockingIndex = threshold.blockSafety
            XCTAssertTrue(LocalInferenceEngine.qualifies(exact, policy: policy))
            var below = exact; below.reportIndex -= 0.001
            XCTAssertFalse(LocalInferenceEngine.qualifies(below, policy: policy))
            below = exact; below.localBlockingIndex = threshold.blockSafety - 0.001
            XCTAssertFalse(LocalInferenceEngine.qualifies(below, policy: policy))
            below = exact; below.observedDays -= 1
            XCTAssertFalse(LocalInferenceEngine.qualifies(below, policy: policy))
        }
        XCTAssertThrowsError(try LocalInferenceEngine.evaluate(independentFamilyValues: [.nan], observedDays: 4))
        XCTAssertThrowsError(try LocalInferenceEngine.evaluate(independentFamilyValues: [25], observedDays: 15))
    }
}
