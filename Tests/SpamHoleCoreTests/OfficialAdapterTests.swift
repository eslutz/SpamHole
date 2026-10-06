import XCTest
import CryptoKit
@testable import SpamHoleCore

final class OfficialAdapterTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_791_158_400)

    func testCallShieldVerifiesSignedManifestAndRejectsTamperingAndPaths() throws {
        let key = P256.Signing.PrivateKey()
        let data = try JSONSerialization.data(withJSONObject: ["format_version":1,"version":42,"updated":"2026-10-05",
            "shard_directory":"data/spam_number_shards","shard_count":1,"shards":[["id":"00","path":"data/spam_number_shards/00.json",
                "sha256":String(repeating:"a",count:64),"bytes":10,"numbers":0,"prefixes":0]]])
        let signature = try key.signature(for: data).derRepresentation.base64EncodedString()
        let keys = [key.publicKey.derRepresentation.base64EncodedString()]
        let manifest = try CallShieldSourceAdapter.manifest(data, signature: signature, now: now, publicKeys: keys)
        XCTAssertEqual(manifest.version, 42)
        XCTAssertThrowsError(try CallShieldSourceAdapter.manifest(data + Data([32]), signature: signature, now: now, publicKeys: keys))
        XCTAssertThrowsError(try CallShieldSourceAdapter.manifest(data, signature: signature, now: now, publicKeys: []))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any])
        object["shards"] = [["id":"00","path":"../outside.json","sha256":String(repeating:"a",count:64),"bytes":10,"numbers":0,"prefixes":0]]
        let bad = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try CallShieldSourceAdapter.manifest(bad,
            signature: key.signature(for: bad).derRepresentation.base64EncodedString(), now: now, publicKeys: keys))
    }

    func testCallShieldImportsOnlyAdditionalCommunityEvidenceWithoutInventingDays() throws {
        let source = try XCTUnwrap(SourceCatalog.builtIns.first { $0.id == "callshield" })
        let expiry = Int64(now.addingTimeInterval(86400).timeIntervalSince1970 * 1000)
        let evidence: (String, String) -> [String:Any] = { origin, kind in
            ["source_id":origin,"evidence_type":kind,"license":origin == "community_reports" ? "CallShield community report policy" : "CallShield database terms", "last_seen":"2026-10-04","expires_at_epoch_ms":expiry]
        }
        let rows: [[String:Any]] = [
            ["number":"+12025550100","reports":100,"sources":["ftc_complaints","community_reports"],
             "evidence":[evidence("ftc_complaints","unverified_complaint"),evidence("community_reports","user_report")]],
            ["number":"+493012345678","reports":10,"sources":["community_reports"],"evidence":[evidence("community_reports","user_report")]],
            ["number":"+12025550102","reports":100,"sources":["fcc_complaints"],"evidence":[evidence("fcc_complaints","unverified_complaint")]]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["shard_id":"00","numbers":rows,"prefixes":[]])
        let shard = CallShieldManifest.Shard(id: "00", path: "data/spam_number_shards/00.json",
            sha256: RowFingerprint.sha256(Array(data)), bytes: data.count, numbers: 3, prefixes: 0)
        let result = try CallShieldSourceAdapter.shard(data, descriptor: shard, source: source, watermark: now, now: now)
        XCTAssertEqual(result.records.map(\.numberE164), ["+12025550100", "+493012345678"])
        XCTAssertTrue(result.records.allSatisfy { $0.isAggregate && $0.observedAt == nil })
        XCTAssertEqual(result.records.first?.aggregateVotesLowerBound, 1, "Mixed upstream counts cannot become community votes")
        XCTAssertEqual(result.records.last?.aggregateVotesLowerBound, 10)
        XCTAssertThrowsError(try CallShieldSourceAdapter.shard(data + Data([32]), descriptor: shard, source: source, watermark: now, now: now))
    }

    func testStoredRevisionPreventsOlderImportOverwritingNewerEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try EvidenceStore(url: root.appendingPathComponent("test.sqlite"))
        var source = SourceCatalog.builtIns[0]; source.enabled = true
        try store.saveSource(source)
        let record = EvidenceRecord(id: "new", sourceID: source.id, sourceFamilyID: source.sourceFamilyID,
            numberE164: "+12025550100", channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now)
        try store.replaceEvidence([record], source: source, state: .init(sourceID: source.id, publisherWatermark: now), enforceRevision: true)
        XCTAssertThrowsError(try store.replaceEvidence([], source: source,
            state: .init(sourceID: source.id, publisherWatermark: now), enforceRevision: true))
        XCTAssertEqual(try store.evidence().map(\.id), ["new"])
    }
}
