import Foundation

public enum SourceCatalog {
    public static var builtIns: [SourceDefinition] {
        [SourceDefinition(id: "ftc-dnc", name: "FTC reported unwanted calls",
                          url: URL(string: "https://www.ftc.gov/policy-notices/open-government/data-sets/do-not-call-data")!,
                          format: .ftcCSV, license: "U.S. government public data; consumer reports are unverified",
                          channels: [.call], sourceFamilyID: "ftc-dnc",
                          reviewedTrust: ReviewedSourceTrust(familyWeight: 1)),
         SourceDefinition(id: "fcc-text-complaints", name: "FCC text complaints (research only)",
                          url: URL(string: "https://opendata.fcc.gov/resource/vakf-fz8e.json")!, format: .fccJSON,
                          enabled: false, license: "Public Domain U.S. Government", channels: [.sms],
                          sourceFamilyID: "fcc-complaints", reviewedTrust: ReviewedSourceTrust(familyWeight: 0))]
    }
    public static let releaseBlockers = [
        "No reviewed free/open source provides confirmed exact SMS senders with expiry and corrections. Feed-based SMS Junk classification and public release remain gated.",
        "FTC downloads and complete refreshes still need physical iPhone network verification; a full host Swift import has been checked."
    ]

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
        guard [.evidenceJSON, .identificationCSV].contains(format), !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw SourceImportError.invalidSchema("Custom subscriptions support evidence JSON or exact identification lists.")
        }
        let id = UUID().uuidString
        return SourceDefinition(id: id, name: name, url: url, format: format,
                                channels: channels, sourceFamilyID: id)
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
