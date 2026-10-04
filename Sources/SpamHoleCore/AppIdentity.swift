import Foundation

/// Build-time identity shared by the containing app and both extensions.
public struct AppIdentity: Sendable, Equatable {
    public let bundleIdentifier: String
    public let appGroupIdentifier: String
    public var callDirectoryIdentifier: String { bundleIdentifier + ".CallDirectory" }
    public var refreshIdentifier: String { bundleIdentifier + ".refresh" }
    public var processingIdentifier: String { bundleIdentifier + ".processing" }
    public var downloadIdentifier: String { bundleIdentifier + ".source-downloads" }
    public var keychainService: String { bundleIdentifier + ".sources" }

    public init(infoDictionary: [String: Any]) throws {
        func identifier(_ key: String) throws -> String {
            guard let value = infoDictionary[key] as? String, !value.isEmpty,
                  value.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else {
                throw SpamHoleCoreError.invalidValue("Missing or invalid build setting: \(key)")
            }
            return value
        }
        bundleIdentifier = try identifier("SpamHoleContainingAppIdentifier")
        appGroupIdentifier = try identifier("SpamHoleAppGroupIdentifier")
        guard appGroupIdentifier.hasPrefix("group.") else {
            throw SpamHoleCoreError.invalidValue("App Group identifier must begin with group.")
        }
    }

    public static var current: AppIdentity? {
        try? AppIdentity(infoDictionary: Bundle.main.infoDictionary ?? [:])
    }
}
