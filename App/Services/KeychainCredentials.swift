import Foundation
import SpamHoleCore
import Security

/// Source secrets stay outside subscription metadata and rule backups.
enum KeychainCredentials {
    private static var service: String { AppIdentity.current?.keychainService ?? "unconfigured.SpamHole.sources" }

    static func token(for sourceID: String) throws -> String? {
        var query = base(sourceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialError.operationFailed
        }
        return value
    }

    static func save(token: String, for sourceID: String) throws {
        try remove(for: sourceID)
        guard !token.isEmpty else { return }
        var attributes = base(sourceID)
        attributes[kSecValueData as String] = Data(token.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else {
            throw CredentialError.operationFailed
        }
    }

    static func remove(for sourceID: String) throws {
        let result = SecItemDelete(base(sourceID) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw CredentialError.operationFailed
        }
    }

    private static func base(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id]
    }

    enum CredentialError: LocalizedError {
        case operationFailed
        var errorDescription: String? { "The source credential could not be accessed securely." }
    }
}
