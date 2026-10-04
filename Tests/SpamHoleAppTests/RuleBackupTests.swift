import XCTest
import SpamHoleCore
@testable import SpamHole

@MainActor
final class RuleBackupTests: XCTestCase {
    private func modelAndBackupURL() throws -> (AppModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (try AppModel(rootURL: root, testing: true), root.appendingPathComponent("backup.json"))
    }

    private func write(_ backup: RuleBackup, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(backup).write(to: url)
    }

    func testMixedLegacyBackupRetainsCallRulesAndReportsOmittedRules() async throws {
        let (model, url) = try modelAndBackupURL()
        let call = PersonalRule(id: "call", identifier: "+12025550100", channel: .call, action: .allow)
        let combined = PersonalRule(id: "combined", identifier: "2025550101", channel: .both, action: .block)
        let message = PersonalRule(id: "message", identifier: "+12025550102", channel: .sms, action: .block)
        var settings = AppSettings()
        settings.contactProtection = true
        try write(RuleBackup(schemaVersion: 1, rules: [call, combined, message], settings: settings), to: url)

        let imported = await model.importBackup(from: url)
        let result = try XCTUnwrap(imported)
        XCTAssertEqual(result.omittedLegacyRuleCount, 1)
        XCTAssertEqual(result.convertedLegacyRuleCount, 1)
        XCTAssertEqual(Set(model.rules.map(\.identifier)), ["+12025550100", "+12025550101"])
        XCTAssertTrue(model.rules.allSatisfy { $0.channel == .call })
        XCTAssertEqual(model.snapshot?.callBlocking, [1_202_555_0101])
        XCTAssertFalse(model.settings.contactProtection)
        XCTAssertTrue(model.message?.contains("Omitted 1 message-only rules") == true)
    }

    func testMessageOnlyLegacyBackupPreservesExistingCallRulesAndGeneration() async throws {
        let (model, url) = try modelAndBackupURL()
        try await model.saveRule(raw: "2025550123", action: .block)
        let previousRules = model.rules
        let previousSnapshot = model.snapshot
        let previousSettings = model.settings
        let message = PersonalRule(identifier: "+12025550100", channel: .sms, action: .allow)
        try write(RuleBackup(schemaVersion: 1, rules: [message], settings: AppSettings()), to: url)

        let result = await model.importBackup(from: url)
        XCTAssertNil(result)
        XCTAssertEqual(model.rules, previousRules)
        XCTAssertEqual(model.snapshot, previousSnapshot)
        XCTAssertEqual(model.settings, previousSettings)
        XCTAssertTrue(model.message?.contains("existing rules were kept") == true)
    }

    func testInvalidLegacyCombinedRuleRejectsEntireBackup() async throws {
        let (model, url) = try modelAndBackupURL()
        try await model.saveRule(raw: "2025550123", action: .allow)
        let previousRules = model.rules
        let invalid = PersonalRule(identifier: "54321", channel: .both, action: .block)
        let valid = PersonalRule(identifier: "+12025550100", channel: .call, action: .block)
        try write(RuleBackup(schemaVersion: 1, rules: [valid, invalid], settings: AppSettings()), to: url)

        let result = await model.importBackup(from: url)
        XCTAssertNil(result)
        XCTAssertEqual(model.rules, previousRules)
    }

    func testExplicitEmptyBackupCanRemoveCallRules() async throws {
        for schema in [1, 2] {
            let (model, url) = try modelAndBackupURL()
            try await model.saveRule(raw: "2025550123", action: .block)
            try write(RuleBackup(schemaVersion: schema, rules: [], settings: AppSettings()), to: url)
            let result = await model.importBackup(from: url)
            XCTAssertNotNil(result)
            XCTAssertTrue(model.rules.isEmpty)
            XCTAssertEqual(model.snapshot?.callBlocking, [])
        }
    }

    func testNewExportUsesCallOnlySchemaAndRejectsLegacyChannels() throws {
        let rule = PersonalRule(identifier: "+12025550100", channel: .call, action: .allow,
                                createdAt: Date(timeIntervalSince1970: 1_791_072_000))
        let document = try RuleBackupDocument(backup: RuleBackup(rules: [rule], settings: AppSettings()))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(RuleBackup.self, from: document.data)
        XCTAssertEqual(exported.schemaVersion, 2)
        XCTAssertEqual(exported.rules, [rule])
        let legacy = PersonalRule(identifier: "+12025550101", channel: .both, action: .block)
        XCTAssertThrowsError(try RuleBackupDocument(backup: RuleBackup(rules: [legacy], settings: AppSettings())))
        XCTAssertThrowsError(try RuleBackup(rules: [legacy], settings: AppSettings()).prepareImport())
    }
}
