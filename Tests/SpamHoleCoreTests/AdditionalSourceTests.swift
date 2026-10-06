import XCTest
@testable import SpamHoleCore

final class AdditionalSourceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_791_158_400)

    func testOfficialSourcesAreAvailableWithoutChangingFTCDefault() throws {
        XCTAssertEqual(Set(SourceCatalog.builtIns.map(\.id)), ["ftc-dnc", "fcc-calls", "phoneblock", "callshield"])
        XCTAssertTrue(SourceCatalog.builtIns[0].enabled)
        XCTAssertTrue(SourceCatalog.builtIns.dropFirst().allSatisfy { !$0.enabled })
    }

    func testLegacyEvidenceAndSourceStateDecodeWithoutNewMetadata() throws {
        let record = EvidenceRecord(id: "legacy", sourceID: "ftc-dnc", sourceFamilyID: "ftc-dnc",
            numberE164: "+12025550100", channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now)
        let decoded = try JSONDecoder().decode(EvidenceRecord.self, from: JSONEncoder().encode(record))
        XCTAssertNil(decoded.evidenceKind)
        XCTAssertFalse(decoded.isAggregate)
        XCTAssertEqual(decoded.observedAt, now)
        let state = try JSONDecoder().decode(SourceState.self, from: Data(#"{"sourceID":"ftc-dnc","recordCount":5}"#.utf8))
        XCTAssertNil(state.publisherVersion)
        XCTAssertNil(state.importRevision)
        XCTAssertEqual(state.recordCount, 5)
    }

    func testInternationalPublisherNumbersKeepTheirCountryCode() throws {
        XCTAssertEqual(try PhoneNormalizer.e164("+49 30 12345678"), "+493012345678")
        XCTAssertEqual(try PhoneNormalizer.e164("+39 06 12345678"), "+390612345678")
        XCTAssertThrowsError(try PhoneNormalizer.e164("03012345678"))
        XCTAssertThrowsError(try PhoneNormalizer.e164("+49 03012345678"))
        XCTAssertThrowsError(try PhoneNormalizer.e164("+4930*"))
    }

    func testFCCNormalizesVoiceCallerIDAndExcludesCallbackAndTexts() throws {
        let source = try XCTUnwrap(SourceCatalog.builtIns.first { $0.id == "fcc-calls" })
        let data = Data(#"[{"id":"1","issue_date":"2026-10-04T00:00:00.000","type_of_call_or_messge":"Live Voice","caller_id_number":"(202) 555-0100","advertiser_business_phone_number":"2025550199"},{"id":"2","issue_date":"2026-10-04T00:00:00.000","type_of_call_or_messge":"Text Message","caller_id_number":"2025550101"},{"id":"3","issue_date":"9999-12-15T00:00:00.000","type_of_call_or_messge":"Prerecorded Voice","caller_id_number":"2025550102"}]"#.utf8)
        let parsed = try SourceAdapters.parse(data: data, source: source, now: now, publisherWatermark: now)
        XCTAssertEqual(parsed.records.map(\.numberE164), ["+12025550100"])
        XCTAssertEqual(parsed.records.first?.observedAt, now.addingTimeInterval(-86400))
        XCTAssertEqual(parsed.rejectedRecordCount, 2)
    }
    func testPhoneBlockPreservesBucketsWithoutMakingCallDates() throws {
        let source = try XCTUnwrap(SourceCatalog.builtIns.first { $0.id == "phoneblock" })
        let data = Data("""
        {"version":42,"numbers":[
          {"phone":"+493012345678","rating":"G_FRAUD","votes":100,"lastActivity":1791158400000},
          {"phone":"+390612345678","rating":"E_ADVERTISING","votes":4},
          {"phone":"+12025550100","rating":"A_LEGITIMATE","votes":0},
          {"phone":"+12025550101","rating":"B_MISSED","votes":10},
          {"phone":"+12025550102","rating":"NEW_CATEGORY","votes":100},
          {"phone":"+12025550103","rating":"G_FRAUD","votes":3}]}
        """.utf8)
        let parsed = try SourceAdapters.parse(data: data, source: source, now: now)
        XCTAssertEqual(parsed.records.map(\.numberE164), ["+493012345678", "+390612345678"])
        XCTAssertTrue(parsed.records.allSatisfy { $0.isAggregate && $0.observedAt == nil })
        XCTAssertEqual(parsed.records.first?.aggregateVotesLowerBound, 100)
        XCTAssertNil(parsed.records.last?.activityAt)
        XCTAssertEqual(parsed.rejectedRecordCount, 2)
    }

    func testAggregateVotesContributeWithoutFabricatedObservedDays() throws {
        var source = try XCTUnwrap(SourceCatalog.builtIns.first { $0.id == "callshield" }); source.enabled = true
        var record = EvidenceRecord(id: "community", sourceID: source.id, sourceFamilyID: source.sourceFamilyID,
            numberE164: "+12025550100", channel: .call, reportedAt: now, publisherWatermark: now)
        record.evidenceKind = .aggregateMembership; record.aggregateVotesLowerBound = 100; record.activityAt = now
        let snapshot = try SnapshotBuilder().build(evidence: [record], sources: [source], rules: [],
            settings: .init(policy: .aggressive, automaticBlockingEnabled: true), now: now)
        let result = try XCTUnwrap(snapshot.assessments.first?.result)
        XCTAssertEqual(result.evidence, try ReputationEngine.aggregateMembershipContribution(votesLowerBound: 100) * 0.5, accuracy: 0.000001)
        XCTAssertEqual(result.localObservedDays, 0)
        XCTAssertEqual(snapshot.assessments.first?.aggregateRecordCount, 1)
        XCTAssertEqual(snapshot.assessments.first?.eventRecordCount, 0)
        XCTAssertTrue(snapshot.callBlocking.isEmpty)
    }

    func testAggregateCannotBorrowAClaimedObservedDate() throws {
        var source = try XCTUnwrap(SourceCatalog.builtIns.first { $0.id == "callshield" }); source.enabled = true
        let records = (0..<7).map { day -> EvidenceRecord in
            var record = EvidenceRecord(id: "aggregate-\(day)", sourceID: source.id, sourceFamilyID: source.sourceFamilyID,
                numberE164: "+12025550100", channel: .call, observedAt: now.addingTimeInterval(-Double(day) * 86400),
                reportedAt: now, publisherWatermark: now)
            record.evidenceKind = .aggregateMembership; record.aggregateVotesLowerBound = 100; record.activityAt = now
            return record
        }
        let value = try SnapshotBuilder().build(evidence: records, sources: [source], rules: [],
            settings: .init(policy: .aggressive, automaticBlockingEnabled: true), now: now)
        XCTAssertEqual(value.assessments.first?.result.localObservedDays, 0)
        XCTAssertEqual(value.assessments.first?.result.evidence, try ReputationEngine.aggregateMembershipContribution(votesLowerBound: 100) * 0.5)
        XCTAssertTrue(value.callBlocking.isEmpty)
    }

    func testExpiryAndUnknownSourceCannotSupplyAggregateAuthority() throws {
        var source = try XCTUnwrap(SourceCatalog.builtIns.first { $0.id == "callshield" }); source.enabled = true
        var record = EvidenceRecord(id: "x", sourceID: source.id, sourceFamilyID: source.sourceFamilyID,
            numberE164: "+12025550100", channel: .call, reportedAt: now, publisherWatermark: now)
        record.evidenceKind = .aggregateMembership; record.aggregateVotesLowerBound = 100; record.activityAt = now
        record.expiresAt = now
        XCTAssertTrue(try SnapshotBuilder().build(evidence: [record], sources: [source], rules: [], settings: .init(), now: now).assessments.isEmpty)
        record.expiresAt = nil; source.url = URL(string: "https://example.org/forged")!
        let value = try SnapshotBuilder().build(evidence: [record], sources: [source], rules: [], settings: .init(), now: now)
        XCTAssertEqual(value.assessments.first?.result.evidence, 0)
        XCTAssertEqual(value.assessments.first?.result.localObservedDays, 0)
    }

}
