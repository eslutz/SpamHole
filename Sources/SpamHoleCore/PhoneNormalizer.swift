import Foundation

public enum PhoneRegion: String, Codable, Sendable { case us, canada }
public enum SenderIdentifierKind: String, Codable, Sendable { case telephone, shortCode, alphanumeric }
public struct SenderIdentifier: Codable, Sendable, Equatable {
    public var kind: SenderIdentifierKind
    public var value: String
}

public enum PhoneNormalizer {
    /// Conservative bundled metadata: NANP plus fixed-length UK, AU, FR, JP and IN national numbers.
    /// This checks numbering structure, never current assignment or ownership.
    public static func callNumber(_ raw: String, defaultRegion: PhoneRegion = .us) throws -> String {
        _ = defaultRegion // Both supported local regions use country calling code 1.
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let permitted = CharacterSet(charactersIn: "+0123456789()- .\t\n\r")
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy(permitted.contains) else {
            throw SpamHoleCoreError.invalidPhoneNumber
        }
        let cleaned = trimmed.filter { $0 == "+" || ("0"..."9").contains($0) }
        let hasPlus = cleaned.hasPrefix("+")
        let digits = hasPlus ? String(cleaned.dropFirst()) : cleaned
        guard !digits.isEmpty, !digits.contains("+"), digits.count <= 15 else {
            throw SpamHoleCoreError.invalidPhoneNumber
        }
        var canonical: String
        if hasPlus { canonical = digits }
        else if digits.count == 10 { canonical = "1" + digits }
        else if digits.count == 11 && digits.hasPrefix("1") { canonical = digits }
        else { throw SpamHoleCoreError.invalidPhoneNumber }

        if canonical.hasPrefix("1") {
            guard canonical.count == 11 else { throw SpamHoleCoreError.invalidPhoneNumber }
            let national = Array(canonical.dropFirst())
            guard ("2"..."9").contains(national[0]), ("2"..."9").contains(national[3]),
                  !(national[1] == "1" && national[2] == "1"),
                  !(national[4] == "1" && national[5] == "1") else {
                throw SpamHoleCoreError.invalidPhoneNumber
            }
        } else {
            let metadata: [(String, Int)] = [("44", 10), ("61", 9), ("33", 9), ("81", 10), ("91", 10)]
            guard let (country, length) = metadata.first(where: { canonical.hasPrefix($0.0) }) else {
                throw SpamHoleCoreError.unsupportedPhoneRegion
            }
            let national = canonical.dropFirst(country.count)
            guard national.count == length, national.first != "0" else { throw SpamHoleCoreError.invalidPhoneNumber }
        }
        canonical.insert("+", at: canonical.startIndex)
        return canonical
    }
    public static func e164(_ raw: String, defaultRegion: PhoneRegion = .us) throws -> String {
        try callNumber(raw, defaultRegion: defaultRegion)
    }
    public static func callDirectoryNumber(_ raw: String) throws -> Int64 {
        let canonical = try callNumber(raw)
        guard let number = Int64(canonical.dropFirst()) else { throw SpamHoleCoreError.invalidPhoneNumber }
        return number
    }
    public static func sender(_ raw: String, defaultRegion: PhoneRegion = .us) throws -> SenderIdentifier {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let phone = try? callNumber(value, defaultRegion: defaultRegion) {
            return SenderIdentifier(kind: .telephone, value: phone)
        }
        let asciiDigits = CharacterSet(charactersIn: "0123456789")
        if (5...6).contains(value.count), value.unicodeScalars.allSatisfy(asciiDigits.contains) {
            return SenderIdentifier(kind: .shortCode, value: value)
        }
        let alpha = value.uppercased()
        let permitted = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")
        let letters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard (1...11).contains(alpha.count), alpha.unicodeScalars.allSatisfy(permitted.contains),
              alpha.unicodeScalars.contains(where: letters.contains) else {
            throw SpamHoleCoreError.invalidSenderIdentifier
        }
        return SenderIdentifier(kind: .alphanumeric, value: alpha)
    }
    public static func smsIdentifier(_ raw: String, defaultRegion: PhoneRegion = .us) throws -> String {
        try sender(raw, defaultRegion: defaultRegion).value
    }
}
