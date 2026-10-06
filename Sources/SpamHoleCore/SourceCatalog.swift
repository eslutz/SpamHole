import Foundation

public enum SourceCatalog {
    public static var builtIns: [SourceDefinition] {
        [SourceDefinition(id: "ftc-dnc", name: "FTC reported unwanted calls",
                          url: URL(string: "https://www.ftc.gov/policy-notices/open-government/data-sets/do-not-call-data")!,
                          format: .ftcCSV, license: "U.S. government public data; consumer reports are unverified",
                          channels: [.call], sourceFamilyID: "ftc-dnc",
                          reviewedTrust: ReviewedSourceTrust(familyWeight: 1, localInferenceEligible: true)),
         SourceDefinition(id: "fcc-calls", name: "FCC unwanted-call complaints",
             url: URL(string: "https://opendata.fcc.gov/resource/vakf-fz8e.json")!,
             format: .fccCallsJSON, enabled: false, license: "USGOV_WORKS; consumer allegations are unverified",
             channels: [.call], sourceFamilyID: "fcc-calls",
             reviewedTrust: ReviewedSourceTrust(familyWeight: 1, localInferenceEligible: true)),
         SourceDefinition(id: "phoneblock", name: "PhoneBlock community reputation",
             url: URL(string: "https://phoneblock.net/phoneblock/api/blocklist?format=json")!,
             format: .phoneBlockJSON, enabled: false, license: "Publisher registration and database-use clearance pending; direct authenticated use only",
             channels: [.call], sourceFamilyID: "phoneblock",
             reviewedTrust: ReviewedSourceTrust(familyWeight: 0.5, localInferenceEligible: phoneBlockAccessApproved)),
         SourceDefinition(id: "callshield", name: "CallShield community evidence",
             url: URL(string: "https://raw.githubusercontent.com/SysAdminDoc/CallShield/master/data/spam_numbers.manifest.json")!,
             format: .callShieldJSON, enabled: false, license: "MIT project; only reviewed additional community evidence with permitted upstream rights",
             channels: [.call], sourceFamilyID: "callshield-community",
             reviewedTrust: ReviewedSourceTrust(familyWeight: 0.5, localInferenceEligible: true))]

    }
    // Change only after publisher app registration and an explicit data-use review.
    public static let phoneBlockAccessApproved = false
    public static func activationBlocker(for source: SourceDefinition) -> String? {
        source.id == "phoneblock" && !phoneBlockAccessApproved
            ? "PhoneBlock requires publisher app registration and database-use clearance before activation." : nil
    }
    static func permitsAggregates(_ source: SourceDefinition) -> Bool {
        let reviewed = canonicalize(source)
        return reviewed.reviewedTrust != nil && [.phoneBlockJSON, .callShieldJSON].contains(reviewed.format)
    }
    public static let releaseBlockers: [String] = []

    /// Persisted settings and publisher payloads cannot install their own source approval.
    /// Approvals are reattached only for an exact bundled identifier/URL/format match.
    public static func canonicalize(_ source: SourceDefinition) -> SourceDefinition {
        var result = source
        if let reviewed = builtIns.first(where: { $0.id == source.id && $0.url == source.url && $0.format == source.format }) {
            result.reviewedTrust = reviewed.reviewedTrust
            result.sourceFamilyID = reviewed.sourceFamilyID
            result.channels = reviewed.channels
            result.license = reviewed.license
        } else {
            result.reviewedTrust = nil
            result.sourceFamilyID = source.id
        }
        return result
    }

    public static func custom(name: String, url: URL, format: SourceFormat,
                              channels: [CommunicationChannel] = [.call]) throws -> SourceDefinition {
        try validateURL(url)
        guard channels == [.call] else { throw SourceImportError.invalidSchema("Only call subscriptions are supported.") }
        guard [.evidenceJSON, .identificationCSV].contains(format), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SourceImportError.invalidSchema("Custom subscriptions support evidence JSON or exact identification lists.")
        }
        let id = UUID().uuidString
        return SourceDefinition(id: id, name: name, url: url, format: format,
                                channels: channels, sourceFamilyID: id)
    }
    public static func validateCallSource(_ source: SourceDefinition) throws {
        guard source.channels == [.call], source.format != .fccJSON else {
            throw SourceImportError.invalidSchema("Only call subscriptions are supported; legacy text formats and channels cannot be imported.")
        }
    }
    public static func validateURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil,
              url.fragment == nil else { throw SourceImportError.invalidURL }
        let credentialNames: Set<String> = ["token", "apikey", "key", "accesstoken", "authorization", "password", "clientsecret"]
        let parameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard !parameters.contains(where: { item in
            let name = item.name.lowercased().filter { $0 != "_" && $0 != "-" }
            return credentialNames.contains(name)
        }) else { throw SourceImportError.invalidURL }
    }
}
