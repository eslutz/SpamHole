import Foundation

public struct SnapshotBuilder: Sendable {
    public let maxIdentificationEntries: Int
    public let maxBlockingEntries: Int
    public init(maxIdentificationEntries: Int = 250_000, maxBlockingEntries: Int = 25_000) {
        self.maxIdentificationEntries = max(0, maxIdentificationEntries)
        self.maxBlockingEntries = max(0, maxBlockingEntries)
    }
    public func build(evidence: [EvidenceRecord], sources: [SourceDefinition], rules: [PersonalRule],
                      settings: AppSettings, sourceStates: [SourceState] = [], protectedContacts: Set<String> = [], previous: ProtectionSnapshot? = nil,
                      now: Date = Date()) throws -> ProtectionSnapshot {
        guard now.timeIntervalSince1970.isFinite else { throw SpamHoleCoreError.invalidValue("Invalid rebuild date") }
        for source in sources { try SourceCatalog.validateCallSource(source) }
        guard rules.allSatisfy({ $0.channel == .call }), evidence.allSatisfy({ $0.channel == .call }) else {
            throw SourceImportError.invalidSchema("Only call rules and evidence are supported.")
        }
        let sourceMap = Dictionary(sources.filter(\.enabled).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Local-block authority must survive the exact catalog identity check, even for direct callers.
        let inferenceSources = sourceMap.mapValues(SourceCatalog.canonicalize).filter {
            $0.value.reviewedTrust?.localInferenceEligible == true && ($0.value.reviewedTrust?.familyWeight ?? 0) > 0
        }
        var coverage: [String: Date] = [:]
        for record in evidence where record.publisherWatermark <= now {
            coverage[record.sourceID] = max(coverage[record.sourceID] ?? .distantPast, record.publisherWatermark)
        }
        for state in sourceStates {
            // Persisted coverage is authoritative; successful HTTP contact cannot advance it.
            coverage[state.sourceID] = state.publisherWatermark ?? .distantPast
        }
        let normalizedRules = try rules.map { rule -> PersonalRule in
            var result = rule
            result.identifier = try PhoneNormalizer.callNumber(rule.identifier)
            return result
        }
        let contacts = settings.contactProtection ? Set(protectedContacts.compactMap { try? PhoneNormalizer.callNumber($0) }) : []
        let allowCalls = Set(normalizedRules.filter { $0.action == .allow }.map(\.identifier))
        let blockCalls = Set(normalizedRules.filter { $0.action == .block }.map(\.identifier)).subtracting(allowCalls)
        var callBlocks = try blockCalls.compactMap { identifier -> Int64? in
            guard let normalized = try? PhoneNormalizer.callNumber(identifier) else { return nil }
            return try PhoneNormalizer.callDirectoryNumber(normalized)
        }.sorted()
        guard callBlocks.count <= maxBlockingEntries else {
            throw SpamHoleCoreError.invalidSnapshot("Personal call blocks exceed the selected device capacity; reduce rules before rebuilding")
        }
        // Apply assignment boundaries before scoring; a revoked confirmation cannot survive a rebuild.
        var boundaries: [String: Date] = [:]
        for record in evidence {
            if let boundary = record.assignmentBoundaryAt, boundary <= now,
               sourceMap[record.sourceID]?.reviewedTrust?.confirmationAuthority == true,
               let identifier = try? PhoneNormalizer.callNumber(record.numberE164) {
                boundaries[identifier] = max(boundaries[identifier] ?? .distantPast, boundary)
            }
        }
        var groups: [String: [EvidenceRecord]] = [:]
        var seen: Set<String> = []
        for original in evidence {
            guard let source = sourceMap[original.sourceID], original.numberRole == .displayedSender,
                  original.channel == .call, source.channels == [.call],
                  original.retractedAt == nil,
                  original.reportedAt <= now, original.publisherWatermark <= now,
                  original.observedAt.map({ $0 <= now }) ?? true,
                  let identifier = try? PhoneNormalizer.callNumber(original.numberE164) else { continue }
            let effectiveDate = original.observedAt ?? original.reportedAt
            if let boundary = boundaries[identifier], effectiveDate < boundary { continue }
            let dedupKey = source.sourceFamilyID + "\u{1F}" + original.id + "\u{1F}" + original.channel.rawValue
            guard seen.insert(dedupKey).inserted else { continue }
            var record = original
            record.numberE164 = identifier
            // Source family identity comes from the app-owned catalog, never from feed content.
            record.sourceFamilyID = source.sourceFamilyID
            groups[identifier, default: []].append(record)
        }

        var assessments: [ReputationAssessment] = []
        var automaticCandidates: [(number: Int64, index: Double, report: Double)] = []
        var identificationCandidates: [(Int64, String, Double)] = []
        let previousMap = Dictionary((previous?.assessments ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for identifier in groups.keys.sorted() {
            let records = groups[identifier] ?? []
            let callRecords = records.filter { $0.channel == .call }
            if !callRecords.isEmpty {
                var result = try evaluate(records: callRecords, sources: sourceMap, now: now)
                let approvedRecords = callRecords.filter { inferenceSources[$0.sourceID] != nil }
                let freshRecords = approvedRecords.compactMap { original -> EvidenceRecord? in
                    guard let watermark = coverage[original.sourceID], watermark <= now,
                          days(since: watermark, now: now) <= 7 else { return nil }
                    var record = original; record.publisherWatermark = watermark
                    return record
                }
                let local = try evaluate(records: freshRecords, sources: inferenceSources, now: now, localInference: true)
                result.localBlockingIndex = local.localBlockingIndex
                result.localReportIndex = local.reportIndex
                result.localObservedDays = local.observedDays
                var decision: LocalBlockingDecision = .insufficientEvidence
                if approvedRecords.isEmpty { decision = .sourceNotEligible }
                else if freshRecords.isEmpty { decision = .staleCoverage }
                else if !freshRecords.contains(where: { $0.observedAt.map { days(since: $0, now: now) <= 7 } ?? false }) {
                    decision = .noRecentObservedCall
                } else if LocalInferenceEngine.qualifies(local, policy: settings.policy) {
                    decision = settings.automaticBlockingEnabled ? .automaticBlock : .awaitingActivation
                }
                let lastDate = callRecords.map { $0.observedAt ?? $0.reportedAt }.max()!
                let lastAge = days(since: lastDate, now: now)
                let allow = allowCalls.contains(identifier)
                let manual = blockCalls.contains(identifier)
                let protected = contacts.contains(identifier) && !manual
                var classification = try ReputationEngine.classify(result, policy: settings.policy,
                    trustedInputsFresh: false, lastRelevantEvidenceAgeDays: lastAge,
                    localAllow: allow || protected, localManualBlock: manual)
                if !allow && !manual && !protected && lastAge <= 30,
                   previous?.metadata.policy == settings.policy,
                   boundaries[identifier].map({ $0 > (previous?.metadata.createdAt ?? .distantPast) }) != true,
                   let old = previousMap[identifier] {
                    let thresholds = PolicyThresholds.forPreset(settings.policy)
                    if old.classification == .identifyManySpamReports && result.associationIndex >= thresholds.strongLabel - 5 {
                        classification = .identifyManySpamReports
                    } else if old.classification == .identifyReportedUnwanted && classification == .noAction
                        && result.associationIndex >= thresholds.identify - 5 { classification = .identifyReportedUnwanted }
                }
                let identificationClassification = classification
                if allow { decision = .personalAllow }
                else if manual { decision = .personalBlock }
                else if protected { decision = .protectedContact }
                else if decision == .automaticBlock || decision == .awaitingActivation {
                    let number = try PhoneNormalizer.callDirectoryNumber(identifier)
                    automaticCandidates.append((number, local.localBlockingIndex ?? 0, local.reportIndex))
                    if settings.automaticBlockingEnabled { classification = .automaticBlock }
                }
                assessments.append(.init(identifier: identifier, result: result, classification: classification,
                    sourceIDs: Array(Set(callRecords.map(\.sourceID))).sorted(), lastEvidenceAt: lastDate,
                    explanation: decision.explanation, localDecision: decision))
                if !allow && !manual && !protected, let number = try? PhoneNormalizer.callDirectoryNumber(identifier) {
                    if let label = identificationClassification.label { identificationCandidates.append((number, label, result.associationIndex)) }
                    else if let listed = callRecords.first(where: {
                        $0.identificationLabel != nil && days(since: $0.observedAt ?? $0.reportedAt, now: now) <= 30
                            && days(since: $0.publisherWatermark, now: now) <= 14
                    }) {
                        let sourceName = sourceMap[listed.sourceID]?.name ?? "subscription"
                        identificationCandidates.append((number, safeLabel("Listed by " + sourceName), 0))
                    }
                }
            }

        }
        let selected = automaticCandidates.sorted {
            if $0.index != $1.index { return $0.index > $1.index }
            if $0.report != $1.report { return $0.report > $1.report }
            return $0.number < $1.number
        }.prefix(maxBlockingEntries - callBlocks.count)
        let selectedNumbers = Set(selected.map(\.number))
        let exportedAutomaticCount = settings.automaticBlockingEnabled ? selected.count : 0
        let personalBlockCount = callBlocks.count
        if settings.automaticBlockingEnabled { callBlocks = (callBlocks + selected.map(\.number)).sorted() }
        for i in assessments.indices where assessments[i].localDecision == .automaticBlock || assessments[i].localDecision == .awaitingActivation {
            let number = try PhoneNormalizer.callDirectoryNumber(assessments[i].identifier)
            if !selectedNumbers.contains(number) {
                assessments[i].localDecision = .capacityExcluded
                assessments[i].explanation = LocalBlockingDecision.capacityExcluded.explanation
                assessments[i].classification = try ReputationEngine.classify(assessments[i].result,
                    policy: settings.policy, trustedInputsFresh: false,
                    lastRelevantEvidenceAgeDays: days(since: assessments[i].lastEvidenceAt ?? .distantPast, now: now))
            }
        }
        let blocked = Set(callBlocks)
        let identification = identificationCandidates.filter { !blocked.contains($0.0) }.sorted {
            $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2
        }.prefix(maxIdentificationEntries).map { CallIdentificationEntry(number: $0.0, label: $0.1) }.sorted { $0.number < $1.number }
        let metadata = GenerationMetadata(createdAt: now, callIdentificationCount: identification.count,
            callBlockCount: callBlocks.count, policy: settings.policy, scoringVersion: LocalInferenceEngine.scoringVersion,
            eligibleAutomaticCount: automaticCandidates.count, exportedAutomaticCount: exportedAutomaticCount,
            personalBlockCount: personalBlockCount, capacityExcludedCount: automaticCandidates.count - selected.count)
        let snapshot = ProtectionSnapshot(metadata: metadata, callIdentification: identification, callBlocking: callBlocks,
                                          assessments: assessments)
        try snapshot.validate()
        return snapshot
    }

    private func days(since date: Date, now: Date) -> Double { max(0, now.timeIntervalSince(date) / 86_400) }
    private func safeLabel(_ input: String) -> String {
        let cleaned = input.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        var output = ""
        for character in cleaned { if (output + String(character)).utf8.count > 128 { break }; output.append(character) }
        return output.isEmpty ? "Listed by subscription" : output
    }
    private func approvedConfirmation(_ record: EvidenceRecord, sources: [String: SourceDefinition], now: Date) -> Bool {
        guard let trust = sources[record.sourceID]?.reviewedTrust, trust.confirmationAuthority,
              [0.8, 1].contains(record.confirmationGrade),
              record.confirmationGrade <= trust.maximumConfirmationGrade,
              let method = record.confirmationMethod, trust.allowedConfirmationMethods.contains(method),
              let reviewed = record.confirmationReviewedAt, reviewed <= now, days(since: reviewed, now: now) <= 7,
              let expiry = record.confirmationExpiresAt, expiry > now,
              days(since: record.publisherWatermark, now: now) <= 14 else { return false }
        return true
    }
    private func evaluate(records: [EvidenceRecord], sources: [String: SourceDefinition], now: Date, localInference: Bool = false) throws -> ReputationResult {
        let byFamily = Dictionary(grouping: records, by: \.sourceFamilyID)
        var families: [Double] = []
        var observedDates: Set<Int> = []
        for familyID in byFamily.keys.sorted() {
            let family = byFamily[familyID] ?? []
            var counts: [Int: Double] = [:]
            let weight = family.compactMap { sources[$0.sourceID]?.reviewedTrust?.familyWeight }.max() ?? 0
            let watermark = family.map(\.publisherWatermark).max() ?? .distantPast
            for record in family {
                // Bucket by UTC calendar date; an arbitrary rebuild time must not split a daily cap.
                let eventDay = Int(floor((record.observedAt ?? record.reportedAt).timeIntervalSince1970 / 86_400))
                let age = max(0, Int(floor(now.timeIntervalSince1970 / 86_400)) - eventDay)
                counts[age, default: 0] += record.observedAt == nil ? 0.5 : 1
                if weight > 0, let event = record.observedAt, days(since: event, now: now) < 14 {
                    observedDates.insert(Int(floor(event.timeIntervalSince1970 / 86_400)))
                }
            }
            families.append(try ReputationEngine.familyContribution(dailyWeightedCounts: counts, weight: weight,
                freshness: ReputationEngine.sourceFreshness(watermarkAgeDays: days(since: watermark, now: now))))
        }
        let confirmed = records.filter { approvedConfirmation($0, sources: sources, now: now) }
        let best = confirmed.max { lhs, rhs in
            let left = lhs.confirmationGrade * pow(2, -days(since: lhs.confirmationReviewedAt!, now: now) / 14)
            let right = rhs.confirmationGrade * pow(2, -days(since: rhs.confirmationReviewedAt!, now: now) / 14)
            return left < right
        }
        let trustedRecords = records.filter { sources[$0.sourceID]?.reviewedTrust != nil }
        let datedRecent = trustedRecords.compactMap(\.observedAt).filter { days(since: $0, now: now) < 14 }
        let perDay = Dictionary(grouping: datedRecent, by: { Int(floor($0.timeIntervalSince1970 / 86_400)) })
        let burstPenalty: Double = !datedRecent.isEmpty && perDay.count <= 2
            && Double(perDay.values.map(\.count).max() ?? 0) / Double(datedRecent.count) >= 0.8 ? 0.5 : 0
        let positive = trustedRecords.map(\.positivePenalty).max() ?? 0
        let uncertainty = max(burstPenalty, trustedRecords.map(\.uncertaintyPenalty).max() ?? 0)
        if localInference {
            return try LocalInferenceEngine.evaluate(independentFamilyValues: families,
                observedDays: min(14, observedDates.count), positivePenalty: positive, uncertaintyPenalty: uncertainty)
        }
        return try ReputationEngine.evaluate(independentFamilyValues: families, confirmation: best?.confirmationGrade ?? 0,
            confirmationAgeDays: best.map { days(since: $0.confirmationReviewedAt!, now: now) } ?? 0,
            observedDays: min(14, observedDates.count), positivePenalty: positive, uncertaintyPenalty: uncertainty)
    }
}
