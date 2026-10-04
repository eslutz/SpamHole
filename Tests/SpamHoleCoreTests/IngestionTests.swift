import Foundation
import XCTest
@testable import SpamHoleCore

final class IngestionTests: XCTestCase, @unchecked Sendable {
    private let now = Date(timeIntervalSince1970: 1_791_072_000) // 2026-10-04 UTC
    private func custom(_ format: SourceFormat = .evidenceJSON) -> SourceDefinition {
        SourceDefinition(id: "custom", name: "Custom", url: URL(string: "https://example.org/feed")!,
                         format: format, channels: [.call], sourceFamilyID: "pretend-independent",
                         reviewedTrust: ReviewedSourceTrust(confirmationAuthority: true,
                                                           allowedConfirmationMethods: ["self-claim"], maximumConfirmationGrade: 1))
    }
    private var json: Data {
        Data("""
        {"schemaVersion":1,"snapshot":true,"publisherWatermark":"2026-10-03T00:00:00Z","records":[
        {"id":"a","identifier":"2025550100","channel":"call","reportedAt":"2026-10-02T00:00:00Z",
        "confirmationGrade":1,"confirmationMethod":"self-claim","confirmationExpiresAt":"2026-10-05T00:00:00Z"}]}
        """.utf8)
    }
    func testCustomSourceCannotGrantConfirmationOrIndependentTrust() throws {
        let source = custom()
        let parsed = try SourceAdapters.parse(data: json, source: source, now: now)
        XCTAssertEqual(parsed.records[0].numberE164, "+12025550100")
        XCTAssertEqual(parsed.records[0].sourceFamilyID, "custom")
        XCTAssertEqual(parsed.records[0].confirmationGrade, 0)
        XCTAssertNil(parsed.records[0].confirmationMethod)
        XCTAssertNil(SourceCatalog.canonicalize(source).reviewedTrust)
    }
    func testURLSecretsRemainInKeychainHeadersAndNonsecretQueriesAreAllowed() throws {
        for name in ["token", "api_key", "key", "access-token", "AUTHORIZATION", "Password", "client_secret", "%61pi_key"] {
            let url = try XCTUnwrap(URL(string: "https://example.org/feed?\(name)=secret"))
            XCTAssertThrowsError(try SourceCatalog.validateURL(url), name)
        }
        XCTAssertThrowsError(try SourceCatalog.validateURL(URL(string: "https://user:secret@example.org/feed")!))
        XCTAssertNoThrow(try SourceCatalog.validateURL(URL(string: "https://example.org/feed?format=csv&country=US")!))
    }
    func testSuppliedHTTPDigestMustMatchAndSignedEnvelopeIsRejected() throws {
        // Standard SHA-256 test vector for ASCII abc.
        let data = Data("abc".utf8)
        let value = "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0="
        XCTAssertNoThrow(try SourceAdapters.validateDigest(data: data, contentDigest: "sha-256=:\(value):", legacyDigest: nil))
        XCTAssertNoThrow(try SourceAdapters.validateDigest(data: data, contentDigest: nil, legacyDigest: "SHA-256=\(value)"))
        XCTAssertThrowsError(try SourceAdapters.validateDigest(data: Data("changed".utf8), contentDigest: "sha-256=:\(value):", legacyDigest: nil))
        XCTAssertThrowsError(try SourceAdapters.validateDigest(data: data, contentDigest: "md5=:AA==:", legacyDigest: nil))
        XCTAssertThrowsError(try SourceAdapters.parse(data: json.replacing("\"schemaVersion\":1", with: "\"schemaVersion\":1,\"signature\":\"unreviewed\""), source: custom(), now: now))
    }
    func testSchemaDuplicateIdentifiersAndDatesRejectWholeImport() throws {
        for replacement in [json.replacing("\"schemaVersion\":1", with: "\"schemaVersion\":2"),
                            json.replacing("\"snapshot\":true", with: "\"snapshot\":false"),
                            json.replacing("2025550100", with: "20255501*"),
                            json.replacing("2026-10-03T00:00:00Z", with: "2027-10-03T00:00:00Z"),
                            json.replacing("\"confirmationGrade\":1", with: "\"confirmationGrade\":0.7")] {
            XCTAssertThrowsError(try SourceAdapters.parse(data: replacement, source: custom(), now: now))
        }
        let duplicate = json.replacing("}]}", with: "},{\"id\":\"a\",\"identifier\":\"2025550101\",\"channel\":\"call\",\"reportedAt\":\"2026-10-02T00:00:00Z\"}]}")
        XCTAssertThrowsError(try SourceAdapters.parse(data: duplicate, source: custom(), now: now))
    }
    func testIdentificationListIsNeutralAndRequiresPublisherDate() throws {
        let source = custom(.identificationCSV)
        let data = Data("identifier\r\n2025550100\r\n\"(202) 555-0100\"\r\n".utf8)
        XCTAssertThrowsError(try SourceAdapters.parse(data: data, source: source, now: now))
        let parsed = try SourceAdapters.parse(data: data, source: source, now: now, publisherWatermark: now.addingTimeInterval(-86400))
        XCTAssertEqual(parsed.records.count, 1)
        XCTAssertEqual(parsed.records[0].identificationLabel, "Listed by source")
        XCTAssertEqual(parsed.records[0].confirmationGrade, 0)
        XCTAssertThrowsError(try SourceAdapters.parse(data: Data("\"2025550100".utf8), source: source,
                                                     now: now, publisherWatermark: now))
    }
    func testFTCQuotedRowsDateQualityAndStableDedup() throws {
        let source = SourceCatalog.builtIns[0]
        let data = Data(#"""
        Company_Phone_Number,Created_Date,Violation_Date,Subject
        2025550100,2026-10-02 12:00:00,2026-10-01 12:00:00,"Quote, and ""text"""
        2025550100,2026-10-02 12:00:00,2026-10-01 12:00:00,"Quote, and ""text"""
        2025550101,2026-10-02 13:00:00,,Other
        202*,2026-10-02 13:00:00,,Other
        """#.utf8)
        let parsed = try SourceAdapters.parse(data: data, source: source, now: now)
        XCTAssertEqual(parsed.records.count, 2)
        XCTAssertEqual(parsed.rejectedRecordCount, 1)
        XCTAssertNil(parsed.records[1].observedAt)
        XCTAssertEqual(parsed.records[0].id.count, 64)
        XCTAssertEqual(parsed.records[0].id, "331e2aa886566d84b430faa10e423ae9e38de7332d6f556b23cc99ed458c194d")
        XCTAssertEqual(parsed.publisherWatermark, SourceAdapters.parseDate("2026-10-02T13:00:00Z"))
        XCTAssertEqual(parsed.records[0].confirmationGrade, 0)
    }
    func testFTCDiscoveryUsesOnlyPublishedSameHostHTTPSCSVLinks() throws {
        let url = SourceCatalog.builtIns[0].url
        let links = try SourceDownloader.discoverFTCFiles(html: """
        <a href='/sites/default/files/published.csv'>Data</a>
        <a href='/sites/default/files/published.csv'>Duplicate</a>
        <a href='https://evil.test/stolen.csv'>Ignore</a>
        <a href='http://www.ftc.gov/insecure.csv'>Ignore</a>
        """, pageURL: url)
        XCTAssertEqual(links.map(\.absoluteString), ["https://www.ftc.gov/sites/default/files/published.csv"])
    }
    func testDownloaderRollbackAnd304DoNotRefreshEvidenceWatermark() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EvidenceStore(url: directory.appendingPathComponent("test.sqlite"))
        let source = custom()
        try store.saveSource(source)
        let transport = StubTransport(responses: [SourceHTTPResponse(data: json, statusCode: 200, headers: ["ETag": "v1"], finalURL: source.url),
                                                 SourceHTTPResponse(data: Data(), statusCode: 304, finalURL: source.url),
                                                 SourceHTTPResponse(data: Data("bad".utf8), statusCode: 200, finalURL: source.url)])
        let downloader = SourceDownloader(store: store, transport: transport)
        let first = try await downloader.refresh(source: source, now: now)
        let second = try await downloader.refresh(source: source, now: now.addingTimeInterval(86400))
        XCTAssertEqual(first.publisherWatermark, second.publisherWatermark)
        do { try await downloader.refresh(source: source, now: now.addingTimeInterval(172800)); XCTFail("Malformed update accepted") }
        catch { }
        XCTAssertEqual(try store.evidence().count, 1)
        XCTAssertEqual(try store.sourceState(id: source.id)?.publisherWatermark, first.publisherWatermark)
        XCTAssertEqual(try store.sourceState(id: source.id)?.lastSuccessAt, now.addingTimeInterval(86400))
        XCTAssertNotNil(try store.sourceState(id: source.id)?.error)
    }
    func testDownloaderRejectsCrossHostRedirectAndKeepsCredentialOutOfStoredError() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EvidenceStore(url: directory.appendingPathComponent("test.sqlite")); let source = custom()
        try store.saveSource(source)
        let transport = StubTransport(responses: [SourceHTTPResponse(data: json, statusCode: 200, finalURL: URL(string: "https://evil.test/?token=secret")!)])
        let downloader = SourceDownloader(store: store, transport: transport)
        do { try await downloader.refresh(source: source, now: now, headers: ["Authorization": "Bearer secret"]); XCTFail("Cross host accepted") }
        catch { XCTAssertEqual(error as? SourceImportError, .invalidURL) }
        XCTAssertFalse(try XCTUnwrap(store.sourceState(id: source.id)?.error).contains("secret"))
    }
    func testFTCSlidingPublicationWindowRetainsHistoryAndPrunesAt90Days() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EvidenceStore(url: directory.appendingPathComponent("test.sqlite"))
        let source = SourceCatalog.builtIns[0]
        try store.saveSource(source)
        let fileURL = URL(string: "https://www.ftc.gov/published.csv")!
        func csv(_ date: String, _ number: String) -> Data {
            Data("Company_Phone_Number,Created_Date,Violation_Date\n\(number),\(date),\(date)\n".utf8)
        }
        let landing = SourceHTTPResponse(data: Data("<a href='/published.csv'>Published</a>".utf8), statusCode: 200, finalURL: source.url)
        let transport = StubTransport(responses: [landing,
            SourceHTTPResponse(data: csv("2026-10-01", "2025550100"), statusCode: 200, finalURL: fileURL),
            landing, SourceHTTPResponse(data: csv("2026-10-02", "2025550101"), statusCode: 200, finalURL: fileURL),
            landing, SourceHTTPResponse(data: csv("2027-01-03", "2025550102"), statusCode: 200, finalURL: fileURL)])
        let downloader = SourceDownloader(store: store, transport: transport)
        try await downloader.refresh(source: source, now: now)
        try await downloader.refresh(source: source, now: now.addingTimeInterval(86400))
        XCTAssertEqual(try store.evidence().count, 2)
        XCTAssertEqual(Set(try store.evidence().map(\.publisherWatermark)).count, 1)
        try await downloader.refresh(source: source, now: try XCTUnwrap(SourceAdapters.parseDate("2027-01-04T00:00:00Z")))
        XCTAssertEqual(try store.evidence().map(\.numberE164), ["+12025550102"])
    }
    func testDownloadCompletionPreservesSourceDisableAndDoesNotRecreateRemovedSource() async throws {
        for remove in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try EvidenceStore(url: directory.appendingPathComponent("test.sqlite")); let source = custom()
            try store.saveSource(source)
            let response = SourceHTTPResponse(data: json, statusCode: 200, finalURL: source.url)
            let transport = MutatingTransport(response: response) {
                if remove { try store.removeSource(id: source.id) }
                else { var disabled = source; disabled.enabled = false; try store.saveSource(disabled) }
            }
            let downloader = SourceDownloader(store: store, transport: transport)
            if remove {
                do { try await downloader.refresh(source: source, now: now); XCTFail("Removed source recreated") }
                catch { XCTAssertEqual(error as? SourceImportError, .sourceChanged) }
                XCTAssertTrue(try store.sources().isEmpty)
            } else {
                try await downloader.refresh(source: source, now: now)
                XCTAssertEqual(try store.sources().first?.enabled, false)
                XCTAssertEqual(try store.evidence(enabledOnly: false).count, 1)
            }
            XCTAssertTrue(try store.evidence().isEmpty)
        }
    }
    func testRefreshEntryDoesNotRecreateRemovedSourceOrEnableDisabledSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try EvidenceStore(url: directory.appendingPathComponent("test.sqlite")); let source = custom()
        let transport = StubTransport(responses: [])
        let downloader = SourceDownloader(store: store, transport: transport)
        do { try await downloader.refresh(source: source, now: now); XCTFail("Unregistered source recreated") }
        catch { XCTAssertEqual(error as? SourceImportError, .sourceChanged) }
        XCTAssertTrue(try store.sources().isEmpty)
        var disabled = source; disabled.enabled = false; try store.saveSource(disabled)
        do { try await downloader.refresh(source: source, now: now); XCTFail("Disabled source reenabled") }
        catch { XCTAssertEqual(error as? SourceImportError, .sourceChanged) }
        XCTAssertEqual(try store.sources().first?.enabled, false)
        XCTAssertTrue(try store.sourceStates().isEmpty)
    }
}

private actor StubTransport: SourceHTTPTransport {
    var responses: [SourceHTTPResponse]
    init(responses: [SourceHTTPResponse]) { self.responses = responses }
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> SourceHTTPResponse {
        guard !responses.isEmpty else { throw SourceImportError.httpStatus(500) }; return responses.removeFirst()
    }
}
private struct MutatingTransport: SourceHTTPTransport {
    let response: SourceHTTPResponse
    let mutation: @Sendable () throws -> Void
    init(response: SourceHTTPResponse, mutation: @escaping @Sendable () throws -> Void) {
        self.response = response; self.mutation = mutation
    }
    func fetch(url: URL, headers: [String: String], maximumBytes: Int) async throws -> SourceHTTPResponse {
        try mutation(); return response
    }
}
private extension Data {
    func replacing(_ old: String, with new: String) -> Data { Data(String(decoding: self, as: UTF8.self).replacingOccurrences(of: old, with: new).utf8) }
}
