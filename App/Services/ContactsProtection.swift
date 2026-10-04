import Contacts
import Foundation
import SpamHoleCore

enum ContactsProtection {
    static func requestAccess() async throws -> Bool {
        try await CNContactStore().requestAccess(for: .contacts)
    }

    /// Limited access naturally returns only accessible contacts. Never cache names.
    static func numbers() throws -> Set<String> {
        try Task.checkCancellation()
        let status = CNContactStore.authorizationStatus(for: .contacts)
        guard status == .authorized || status == .limited else { return [] }
        var numbers: Set<String> = []
        let request = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
        request.unifyResults = true
        try CNContactStore().enumerateContacts(with: request) { contact, stop in
            if Task.isCancelled { stop.pointee = true; return }
            for phone in contact.phoneNumbers {
                if let normalized = try? PhoneNormalizer.callNumber(phone.value.stringValue) {
                    numbers.insert(normalized)
                }
            }
        }
        try Task.checkCancellation()
        return numbers
    }
}
