#if DEBUG
import Contacts
import Foundation
import SpamHoleCore

/// Explicit development-device harness, omitted entirely from Release builds.
/// Reports only authorization and reserved-number membership. Never exports contacts.
enum DebugContactsAcceptance {
    private struct Fixture: Codable { let identifier: String; let givenName: String; let familyName: String }
    private static let numbers = ["+12025550191", "+12025550192", "+12025550193"]
    private static var journal: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateContactsAcceptance.json")
    }
    private static func fixtures() throws -> [Fixture] {
        try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: journal))
    }
    static func run(_ action: String) throws -> String {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if action == "inspect" {
            let accessible = try ContactsProtection.numbers()
            try verifySnapshotPrecedence(protected: accessible)
            return "status=\(status.rawValue);membership=" + numbers.map { accessible.contains($0) ? "1" : "0" }.joined()
        }
        guard status == .authorized else { throw CocoaError(.fileReadNoPermission) }
        switch action {
        case "create":
            guard !FileManager.default.fileExists(atPath: journal.path),
                  try ContactsProtection.numbers().isDisjoint(with: numbers) else { throw CocoaError(.fileWriteFileExists) }
            try FileManager.default.createDirectory(at: journal.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Preassign identities before saving, so an interrupted save has recoverable IDs.
            let contacts = (0..<2).map { index -> CNMutableContact in
                let contact = CNMutableContact()
                contact.givenName = "SpamHole Acceptance \(index == 0 ? "A" : "B")"
                contact.familyName = UUID().uuidString
                contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                    value: CNPhoneNumber(stringValue: numbers[index]))]
                return contact
            }
            let entries = contacts.map { Fixture(identifier: $0.identifier, givenName: $0.givenName, familyName: $0.familyName) }
            try JSONEncoder().encode(entries).write(to: journal, options: .atomic)
            var privateJournal = journal
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try privateJournal.setResourceValues(values)
            let save = CNSaveRequest()
            for contact in contacts { save.add(contact, toContainerWithIdentifier: nil) }
            try store.execute(save)
        case "modify", "delete":
            let entries = try fixtures()
            for (index, fixture) in entries.enumerated() {
                if action == "modify" && index != 0 { continue }
                let contact: CNMutableContact
                do {
                    contact = try store.unifiedContact(withIdentifier: fixture.identifier,
                        keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor, CNContactFamilyNameKey as CNKeyDescriptor,
                                      CNContactPhoneNumbersKey as CNKeyDescriptor]).mutableCopy() as! CNMutableContact
                } catch let error as NSError where action == "delete" && error.domain == CNErrorDomain && error.code == CNError.Code.recordDoesNotExist.rawValue {
                    continue
                }
                guard contact.givenName == fixture.givenName && contact.familyName == fixture.familyName else {
                    throw CocoaError(.validationMissingMandatoryProperty)
                }
                let save = CNSaveRequest()
                if action == "delete" { save.delete(contact) }
                else {
                    contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: numbers[2]))]
                    save.update(contact)
                }
                try store.execute(save)
            }
            if action == "delete" { try FileManager.default.removeItem(at: journal) }
        default: throw CocoaError(.validationMissingMandatoryProperty)
        }
        return try run("inspect")
    }

    /// Synthetic evidence is built in memory, never written into normal data.
    private static func verifySnapshotPrecedence(protected: Set<String>) throws {
        let now = Date()
        let source = SourceDefinition(id: "device-fixture", name: "Synthetic fixture",
            url: URL(string: "https://example.com/fixture")!, format: .evidenceJSON,
            channels: [.call], sourceFamilyID: "device-fixture", reviewedTrust: .init(familyWeight: 1))
        let evidence = numbers.flatMap { number in
            (0..<5).map { index in
                EvidenceRecord(id: "\(number)-\(index)", sourceID: source.id, sourceFamilyID: source.sourceFamilyID,
                    numberE164: number, channel: .call, observedAt: now, reportedAt: now, publisherWatermark: now)
            }
        }
        let builder = SnapshotBuilder()
        let settings = AppSettings(contactProtection: true)
        let fixtureProtection = protected.intersection(numbers)
        let snapshot = try builder.build(evidence: evidence, sources: [source], rules: [], settings: settings,
            protectedContacts: fixtureProtection, now: now)
        for number in numbers {
            let directoryNumber = Int64(number.dropFirst())!
            guard snapshot.callIdentification.contains(where: { $0.number == directoryNumber }) != protected.contains(number) else {
                throw CocoaError(.validationMissingMandatoryProperty)
            }
        }
        let block = PersonalRule(identifier: numbers[1], action: .block)
        let blocked = try builder.build(evidence: evidence, sources: [source], rules: [block], settings: settings,
            protectedContacts: fixtureProtection, now: now)
        guard blocked.callBlocking.contains(Int64(numbers[1].dropFirst())!) else { throw CocoaError(.validationMissingMandatoryProperty) }
        let allow = PersonalRule(identifier: numbers[1], action: .allow)
        let allowed = try builder.build(evidence: evidence, sources: [source], rules: [block, allow], settings: settings,
            protectedContacts: fixtureProtection, now: now)
        guard allowed.callBlocking.isEmpty,
              !allowed.callIdentification.contains(where: { $0.number == Int64(numbers[1].dropFirst())! }) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
    }
}
#endif
