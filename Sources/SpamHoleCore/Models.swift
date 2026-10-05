import Foundation

public enum CommunicationChannel: String, Codable, Sendable, CaseIterable {
    case call
    // Decode-only compatibility for the version 1 database; new writes reject these cases.
    case sms, both
    public static let allCases: [CommunicationChannel] = [.call]
}
public enum NumberRole: String, Codable, Sendable { case displayedSender, callback, advertised }
public enum RuleAction: String, Codable, Sendable { case allow, block }
public enum SourceFormat: String, Codable, Sendable, CaseIterable {
    case evidenceJSON, identificationCSV, ftcCSV
    // Decode-only compatibility: the retired text-complaint source is removed on migration.
    case fccJSON
    public static let allCases: [SourceFormat] = [.evidenceJSON, .identificationCSV, .ftcCSV]
}
public enum PolicyPreset: String, Codable, Sendable, CaseIterable { case conservative, balanced, aggressive }
public enum RefreshCadence: String, Codable, Sendable, CaseIterable { case manual, daily, weekly }

/// This approval belongs to the app's reviewed source registry. It is never read from a feed.
public struct ReviewedSourceTrust: Codable, Sendable, Equatable {
    public var familyWeight: Double
    public var confirmationAuthority: Bool
    public var allowedConfirmationMethods: [String]
    public var maximumConfirmationGrade: Double
    public init(familyWeight: Double = 1, confirmationAuthority: Bool = false,
                allowedConfirmationMethods: [String] = [], maximumConfirmationGrade: Double = 0) {
        self.familyWeight = familyWeight; self.confirmationAuthority = confirmationAuthority
        self.allowedConfirmationMethods = allowedConfirmationMethods
        self.maximumConfirmationGrade = maximumConfirmationGrade
    }
}

public struct SourceDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var url: URL
    public var format: SourceFormat
    public var enabled: Bool
    public var license: String?
    public var channels: [CommunicationChannel]
    public var sourceFamilyID: String
    public var reviewedTrust: ReviewedSourceTrust?
    public init(id: String, name: String, url: URL, format: SourceFormat, enabled: Bool = true, license: String? = nil,
                channels: [CommunicationChannel] = [.call], sourceFamilyID: String, reviewedTrust: ReviewedSourceTrust? = nil) {
        self.id = id; self.name = name; self.url = url; self.format = format; self.enabled = enabled
        self.license = license; self.channels = channels; self.sourceFamilyID = sourceFamilyID; self.reviewedTrust = reviewedTrust
    }
}

public struct EvidenceRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var sourceID: String
    public var sourceFamilyID: String
    /// Canonical exact E.164 telephone number.
    public var numberE164: String
    public var channel: CommunicationChannel
    public var numberRole: NumberRole
    public var observedAt: Date?
    public var reportedAt: Date
    public var publisherWatermark: Date
    public var confirmationGrade: Double
    public var confirmationMethod: String?
    public var confirmationExpiresAt: Date?
    public var confirmationReviewedAt: Date?
    public var retractedAt: Date?
    public var assignmentBoundaryAt: Date?
    /// Raw publisher dates preserve provenance when an upstream calendar date has no timezone.
    public var originalReportedDate: String?
    public var originalObservedDate: String?
    public var positivePenalty: Double
    public var uncertaintyPenalty: Double
    public var identificationLabel: String?
    public init(id: String, sourceID: String, sourceFamilyID: String, numberE164: String, channel: CommunicationChannel,
                numberRole: NumberRole = .displayedSender, observedAt: Date? = nil, reportedAt: Date,
                publisherWatermark: Date, confirmationGrade: Double = 0, confirmationMethod: String? = nil,
                confirmationExpiresAt: Date? = nil, confirmationReviewedAt: Date? = nil,
                retractedAt: Date? = nil, assignmentBoundaryAt: Date? = nil,
                originalReportedDate: String? = nil, originalObservedDate: String? = nil,
                positivePenalty: Double = 0, uncertaintyPenalty: Double = 0, identificationLabel: String? = nil) {
        self.id = id; self.sourceID = sourceID; self.sourceFamilyID = sourceFamilyID; self.numberE164 = numberE164
        self.channel = channel; self.numberRole = numberRole; self.observedAt = observedAt; self.reportedAt = reportedAt
        self.publisherWatermark = publisherWatermark; self.confirmationGrade = confirmationGrade
        self.confirmationMethod = confirmationMethod; self.confirmationExpiresAt = confirmationExpiresAt
        self.confirmationReviewedAt = confirmationReviewedAt; self.retractedAt = retractedAt
        self.assignmentBoundaryAt = assignmentBoundaryAt; self.positivePenalty = positivePenalty
        self.originalReportedDate = originalReportedDate; self.originalObservedDate = originalObservedDate
        self.uncertaintyPenalty = uncertaintyPenalty; self.identificationLabel = identificationLabel
    }
}

public struct PersonalRule: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var identifier: String
    public var channel: CommunicationChannel
    public var action: RuleAction
    public var createdAt: Date
    public var note: String?
    public init(id: String = UUID().uuidString, identifier: String, channel: CommunicationChannel = .call,
                action: RuleAction, createdAt: Date = Date(), note: String? = nil) {
        self.id = id; self.identifier = identifier; self.channel = channel; self.action = action; self.createdAt = createdAt
        self.note = note
    }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var policy: PolicyPreset
    public var cadence: RefreshCadence
    public var contactProtection: Bool
    public init(policy: PolicyPreset = .balanced, cadence: RefreshCadence = .daily, contactProtection: Bool = false) {
        self.policy = policy; self.cadence = cadence; self.contactProtection = contactProtection
    }
}

public struct SourceState: Codable, Sendable, Equatable, Identifiable {
    public var id: String { sourceID }
    public var sourceID: String
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var publisherWatermark: Date?
    public var etag: String?
    public var lastModified: String?
    public var recordCount: Int
    public var error: String?
    public init(sourceID: String, lastAttemptAt: Date? = nil, lastSuccessAt: Date? = nil, publisherWatermark: Date? = nil,
                etag: String? = nil, lastModified: String? = nil, recordCount: Int = 0, error: String? = nil) {
        self.sourceID = sourceID; self.lastAttemptAt = lastAttemptAt; self.lastSuccessAt = lastSuccessAt
        self.publisherWatermark = publisherWatermark; self.etag = etag; self.lastModified = lastModified
        self.recordCount = recordCount; self.error = error
    }
}

public enum ReputationClassification: String, Codable, Sendable {
    case noAction = "no_action", manualBlock = "manual_block", automaticBlock = "automatic_block"
    case identifyManySpamReports = "identify_many_spam_reports", identifyReportedUnwanted = "identify_reported_unwanted"
    public var label: String? {
        switch self {
        case .identifyManySpamReports: "Many spam reports"
        case .identifyReportedUnwanted: "Reported unwanted"
        default: nil
        }
    }
}

public struct ReputationResult: Codable, Sendable, Equatable {
    public var evidence: Double
    public var reportIndex: Double
    public var associationIndex: Double
    public var blockSafetyIndex: Double
    public var confirmation: Double
    public var confirmationFreshness: Double
    public var observedDays: Int
    public var positivePenalty: Double
    public var uncertaintyPenalty: Double
}
public struct ReputationAssessment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { identifier }
    public var identifier: String
    public var result: ReputationResult
    public var classification: ReputationClassification
    public var sourceIDs: [String]
    public var lastEvidenceAt: Date?
    public var explanation: String
}

public struct CallIdentificationEntry: Codable, Sendable, Equatable {
    public var number: Int64
    public var label: String
    public init(number: Int64, label: String) { self.number = number; self.label = label }
}
public struct GenerationMetadata: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var createdAt: Date
    public var callIdentificationCount: Int
    public var callBlockCount: Int
    public var policy: PolicyPreset
    public var schemaVersion: Int
    public init(id: UUID = UUID(), createdAt: Date = Date(), callIdentificationCount: Int,
                callBlockCount: Int, policy: PolicyPreset, schemaVersion: Int = 1) {
        self.id = id; self.createdAt = createdAt; self.callIdentificationCount = callIdentificationCount
        self.callBlockCount = callBlockCount
        self.policy = policy; self.schemaVersion = schemaVersion
    }
}
public struct CallInstallationReceipt: Codable, Sendable, Equatable {
    public var generationID: UUID
    public var installedAt: Date
    public var identificationCount: Int
    public var blockingCount: Int
    public init(generationID: UUID, installedAt: Date = Date(), identificationCount: Int, blockingCount: Int) {
        self.generationID = generationID; self.installedAt = installedAt
        self.identificationCount = identificationCount; self.blockingCount = blockingCount
    }
}

public struct ProtectionSnapshot: Codable, Sendable, Equatable {
    public var metadata: GenerationMetadata
    public var callIdentification: [CallIdentificationEntry]
    public var callBlocking: [Int64]
    public var assessments: [ReputationAssessment]
    public init(metadata: GenerationMetadata, callIdentification: [CallIdentificationEntry], callBlocking: [Int64],
                assessments: [ReputationAssessment] = []) {
        self.metadata = metadata; self.callIdentification = callIdentification; self.callBlocking = callBlocking
        self.assessments = assessments
    }
    public func validate() throws {
        guard metadata.schemaVersion == 1 else { throw SpamHoleCoreError.unsupportedSchema }
        guard metadata.callIdentificationCount == callIdentification.count,
              metadata.callBlockCount == callBlocking.count else {
            throw SpamHoleCoreError.invalidSnapshot("Entry counts disagree with metadata")
        }
        let identified = callIdentification.map(\.number)
        guard zip(identified, identified.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw SpamHoleCoreError.invalidSnapshot("Identification entries must be sorted and unique")
        }
        guard zip(callBlocking, callBlocking.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw SpamHoleCoreError.invalidSnapshot("Blocking entries must be sorted and unique")
        }
        guard identified.allSatisfy({ $0 > 0 && (try? PhoneNormalizer.callDirectoryNumber("+\($0)")) == $0 }) else {
            throw SpamHoleCoreError.invalidSnapshot("Identification numbers must be valid")
        }
        guard callBlocking.allSatisfy({ $0 > 0 && (try? PhoneNormalizer.callDirectoryNumber("+\($0)")) == $0 }) else {
            throw SpamHoleCoreError.invalidSnapshot("Blocking numbers must be valid")
        }
        guard Set(identified).isDisjoint(with: callBlocking) else {
            throw SpamHoleCoreError.invalidSnapshot("Identification and blocking entries must be disjoint")
        }
        let controls = CharacterSet.controlCharacters
        for entry in callIdentification {
            guard !entry.label.isEmpty, entry.label.utf8.count <= 128 else {
                throw SpamHoleCoreError.invalidSnapshot("Identification label length is invalid")
            }
            guard !entry.label.unicodeScalars.contains(where: { controls.contains($0) }) else {
                throw SpamHoleCoreError.invalidSnapshot("Identification labels must not contain control characters")
            }
        }

    }
}

public enum SpamHoleCoreError: Error, LocalizedError, Equatable {
    case invalidValue(String), invalidPhoneNumber, unsupportedPhoneRegion
    case unsupportedSchema, invalidSnapshot(String), snapshotUnavailable
    public var errorDescription: String? {
        switch self {
        case .invalidValue(let value), .invalidSnapshot(let value): value
        case .invalidPhoneNumber: "Enter a complete valid phone number; ranges and prefixes are not supported."
        case .unsupportedPhoneRegion: "This number's country is not supported by the bundled metadata."
        case .unsupportedSchema: "The snapshot format is not supported."
        case .snapshotUnavailable: "No valid protection snapshot is available."
        }
    }
}
