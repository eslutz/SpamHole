import Foundation
import SpamHoleCore
import SwiftUI
import UniformTypeIdentifiers

struct RuleBackup: Codable {
    var schemaVersion = 1
    var rules: [PersonalRule]
    var settings: AppSettings

    func validate() throws {
        guard schemaVersion == 1, rules.count <= 10_000, Set(rules.map(\.id)).count == rules.count else {
            throw SpamHoleCoreError.invalidValue("This backup has an unsupported format or too many rules.")
        }
        for rule in rules {
            let expected = try rule.channel == .sms ? PhoneNormalizer.smsIdentifier(rule.identifier) : PhoneNormalizer.callNumber(rule.identifier)
            guard expected == rule.identifier, rule.id.utf8.count <= 128 else {
                throw SpamHoleCoreError.invalidValue("The backup contains a noncanonical sender rule.")
            }
        }
    }
}

struct RuleBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(backup: RuleBackup) throws {
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
    func importBackup(from url: URL) async {
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
            try backup.validate()
            // Restoring a preference never grants Contacts permission.
            var restoredSettings = backup.settings
            restoredSettings.contactProtection = false
            try store.restorePersonalState(rules: backup.rules, settings: restoredSettings)
            settings = restoredSettings
            try loadState()
            await rebuild()
        } catch { message = error.localizedDescription }
    }
}
