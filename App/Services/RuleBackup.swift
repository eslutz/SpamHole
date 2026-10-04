import Foundation
import SpamHoleCore
import SwiftUI
import UniformTypeIdentifiers

struct RuleBackupImport: Equatable {
    let rules: [PersonalRule]
    let omittedLegacyRuleCount: Int
    let convertedLegacyRuleCount: Int

    var notice: String {
        var parts = ["Imported \(rules.count) call rules."]
        if convertedLegacyRuleCount > 0 {
            parts.append("Converted \(convertedLegacyRuleCount) combined rules to calls only.")
        }
        if omittedLegacyRuleCount > 0 {
            parts.append("Omitted \(omittedLegacyRuleCount) message-only rules.")
        }
        return parts.joined(separator: " ")
    }
}

struct RuleBackup: Codable {
    var schemaVersion = 2
    var rules: [PersonalRule]
    var settings: AppSettings

    func prepareImport() throws -> RuleBackupImport {
        guard [1, 2].contains(schemaVersion), rules.count <= 10_000,
              Set(rules.map(\.id)).count == rules.count,
              rules.allSatisfy({ !$0.id.isEmpty && $0.id.utf8.count <= 128 }) else {
            throw SpamHoleCoreError.invalidValue("This backup has an unsupported format or invalid rules.")
        }
        var callRules: [PersonalRule] = []
        var omitted = 0
        var converted = 0
        for original in rules {
            var rule = original
            if schemaVersion == 1 && rule.channel == .sms {
                omitted += 1
                continue
            }
            guard rule.channel == .call || (schemaVersion == 1 && rule.channel == .both) else {
                throw SpamHoleCoreError.invalidValue("This backup contains an unsupported rule. New backups must contain only call rules.")
            }
            let expected = try PhoneNormalizer.callNumber(rule.identifier)
            if rule.channel == .both {
                rule.identifier = expected
                rule.channel = .call
                converted += 1
            } else if expected != rule.identifier {
                throw SpamHoleCoreError.invalidValue("The backup contains a noncanonical phone-number rule.")
            }
            callRules.append(rule)
        }
        guard rules.isEmpty || !callRules.isEmpty else {
            throw SpamHoleCoreError.invalidValue("Omitted \(omitted) message-only rules. This backup has no call rules; existing rules were kept.")
        }
        return RuleBackupImport(rules: callRules, omittedLegacyRuleCount: omitted,
                                convertedLegacyRuleCount: converted)
    }
}

struct RuleBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(backup: RuleBackup) throws {
        guard backup.schemaVersion == 2, backup.rules.allSatisfy({ $0.channel == .call }) else {
            throw SpamHoleCoreError.invalidValue("New backups must contain only call rules.")
        }
        _ = try backup.prepareImport()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        data = try encoder.encode(backup)
    }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 2_000_000 else {
            throw SpamHoleCoreError.invalidValue("The backup must be a JSON file smaller than 2 MB.")
        }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension AppModel {
    @discardableResult
    func importBackup(from url: URL) async -> RuleBackupImport? {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 2_000_001) ?? Data()
            guard data.count <= 2_000_000 else { throw SpamHoleCoreError.invalidValue("The backup exceeds 2 MB.") }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let backup = try decoder.decode(RuleBackup.self, from: data)
            let imported = try backup.prepareImport()
            // Restoring a preference never grants Contacts permission.
            var restoredSettings = backup.settings
            restoredSettings.contactProtection = false
            try store.restorePersonalState(rules: imported.rules, settings: restoredSettings)
            settings = restoredSettings
            try loadState()
            let rebuilt = await rebuild()
            if rebuilt { message = imported.notice }
            else { message = [message, imported.notice].compactMap { $0 }.joined(separator: " ") }
            return imported
        } catch { message = error.localizedDescription; return nil }
    }
}
