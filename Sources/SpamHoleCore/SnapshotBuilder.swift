import Foundation

public struct SnapshotBuilder: Sendable {
    public let maxIdentificationEntries: Int
    public let maxBlockingEntries: Int
    public init(maxIdentificationEntries: Int = 250_000, maxBlockingEntries: Int = 25_000) {
        self.maxIdentificationEntries = max(0, maxIdentificationEntries)
        self.maxBlockingEntries = max(0, maxBlockingEntries)
    }
    public func build(evidence: [EvidenceRecord], sources: [SourceDefinition], rules: [PersonalRule],
                      settings: AppSettings, protectedContacts: Set<String> = [], previous: ProtectionSnapshot? = nil,
                      now: Date = Date()) throws -> ProtectionSnapshot {
        guard now.timeIntervalSince1970.isFinite else { throw SpamHoleCoreError.invalidValue("Invalid rebuild date") }
        let sourceMap = Dictionary(sources.filter(\.enabled).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let normalizedRules = rules.compactMap { rule -> PersonalRule? in
            var result = rule
            guard let identifier = try? PhoneNormalizer.smsIdentifier(rule.identifier) else { return nil }
            result.identifier = identifier
            return result
        }
        let contacts = settings.contactProtection ? Set(protectedContacts.compactMap { try? PhoneNormalizer.smsIdentifier($0) }) : []
        let allowCalls = Set(normalizedRules.filter { $0.action == .allow && $0.channel.includes(.call) }.map(\.identifier))
        let allowSMS = Set(normalizedRules.filter { $0.action == .allow && $0.channel.includes(.sms) }.map(\.identifier))
        let blockCalls = Set(normalizedRules.filter { $0.action == .block && $0.channel.includes(.call) }.map(\.identifier)).subtracting(allowCalls)
        let blockSMS = Set(normalizedRules.filter { $0.action == .block && $0.channel.includes(.sms) }.map(\.identifier)).subtracting(allowSMS)
        let callBlocks = try blockCalls.compactMap { identifier -> Int64? in
            guard let normalized = try? PhoneNormalizer.callNumber(identifier) else { return nil }
            return try PhoneNormalizer.callDirectoryNumber(normalized)
        }.sorted()
        guard callBlocks.count <= maxBlockingEntries else {
            throw SpamHoleCoreError.invalidSnapshot("Personal call blocks exceed the selected device capacity; reduce rules before rebuilding")
        }
        var smsMap: [String: SMSDecisionEntry] = [:]
        for identifier in contacts.union(allowSMS) {
            smsMap[identifier] = .init(identifier: identifier, action: .allow, reason: allowSMS.contains(identifier) ? "Personal allow rule" : "Protected contact")
        }
        for identifier in blockSMS { smsMap[identifier] = .init(identifier: identifier, action: .junk, reason: "Personal Junk rule") }

        // Apply assignment boundaries before scoring; a revoked confirmation cannot survive a rebuild.
        var boundaries: [String: Date] = [:]
        for record in evidence {
            if let boundary = record.assignmentBoundaryAt, boundary <= now,
               sourceMap[record.sourceID]?.reviewedTrust?.confirmationAuthority == true,
               let identifier = try? PhoneNormalizer.smsIdentifier(record.numberE164) {
                boundaries[identifier] = max(boundaries[identifier] ?? .distantPast, boundary)
            }
        }
        var groups: [String: [EvidenceRecord]] = [:]
        var seen: Set<String> = []
        for original in evidence {
            guard let source = sourceMap[original.sourceID], original.numberRole == .displayedSender,
                  original.channel != .both, source.channels.contains(where: { $0.includes(original.channel) }),
                  original.retractedAt == nil,
                  original.reportedAt <= now, original.publisherWatermark <= now,
                  original.observedAt.map({ $0 <= now }) ?? true,
                  let identifier = try? PhoneNormalizer.smsIdentifier(original.numberE164) else { continue }
            if original.channel == .call, (try? PhoneNormalizer.callNumber(identifier)) == nil { continue }
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
        var identificationCandidates: [(Int64, String, Double)] = []
        let previousMap = Dictionary((previous?.assessments ?? []).map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for identifier in groups.keys.sorted() {
            let records = groups[identifier] ?? []
            let callRecords = records.filter { $0.channel == .call }
            if !callRecords.isEmpty {
                let result = try evaluate(records: callRecords, sources: sourceMap, now: now)
                let lastDate = callRecords.map { $0.observedAt ?? $0.reportedAt }.max()!
                let lastAge = days(since: lastDate, now: now)
                let allow = allowCalls.contains(identifier)
                let manual = blockCalls.contains(identifier)
                let protected = contacts.contains(identifier) && !manual
                var classification = try ReputationEngine.classify(result, policy: settings.policy,
                    trustedInputsFresh: false, lastRelevantEvidenceAgeDays: lastAge,
                    localAllow: allow || protected, localManualBlock: manual)
                // V1 exports no feed-derived automatic blocks. The pure reference classifier remains parity-tested.
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
                let explanation = result.confirmation == 0
                    ? "Complaint association index; no approved current origin confirmation. Call blocking requires your personal rule."
                    : "Origin evidence is evaluated locally. V1 feed-derived automatic call blocking remains disabled."
                assessments.append(.init(identifier: identifier, result: result, classification: classification,
                                         sourceIDs: Array(Set(callRecords.map(\.sourceID))).sorted(), lastEvidenceAt: lastDate, explanation: explanation))
                if !allow && !manual && !protected, let number = try? PhoneNormalizer.callDirectoryNumber(identifier) {
                    if let label = classification.label { identificationCandidates.append((number, label, result.associationIndex)) }
                    else if let listed = callRecords.first(where: {
                        $0.identificationLabel != nil && days(since: $0.observedAt ?? $0.reportedAt, now: now) <= 30
                            && days(since: $0.publisherWatermark, now: now) <= 14
                    }) {
                        let sourceName = sourceMap[listed.sourceID]?.name ?? "subscription"
                        identificationCandidates.append((number, safeLabel("Listed by " + sourceName), 0))
                    }
                }
            }
            if smsMap[identifier] == nil {
                let confirmed = records.filter { record in
                    record.channel == .sms && approvedConfirmation(record, sources: sourceMap, now: now, sms: true)
                        && record.positivePenalty == 0 && record.uncertaintyPenalty == 0
                }
                // Contradictory wanted/spoof evidence vetoes source-based Junk, even from a different SMS source.
                let conflict = records.contains {
                    $0.channel == .sms && sourceMap[$0.sourceID]?.reviewedTrust != nil
                        && ($0.positivePenalty > 0 || $0.uncertaintyPenalty > 0)
                }
                if !conflict, let best = confirmed.max(by: { ($0.confirmationReviewedAt ?? .distantPast) < ($1.confirmationReviewedAt ?? .distantPast) }),
                   let reviewed = best.confirmationReviewedAt, let expires = best.confirmationExpiresAt {
                    let validity = min(expires, reviewed.addingTimeInterval(7 * 86_400), best.publisherWatermark.addingTimeInterval(14 * 86_400))
                    if validity > now { smsMap[identifier] = .init(identifier: identifier, action: .junk, expiresAt: validity, reason: "Approved current SMS sender confirmation") }
                }
            }
        }
        let identification = identificationCandidates.sorted {
            $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2
        }.prefix(maxIdentificationEntries).map { CallIdentificationEntry(number: $0.0, label: $0.1) }.sorted { $0.number < $1.number }
        let smsDecisions = smsMap.values.sorted { $0.identifier < $1.identifier }
        let metadata = GenerationMetadata(createdAt: now, callIdentificationCount: identification.count,
            callBlockCount: callBlocks.count, smsDecisionCount: smsDecisions.count, policy: settings.policy)
        let snapshot = ProtectionSnapshot(metadata: metadata, callIdentification: identification, callBlocking: callBlocks,
                                          smsDecisions: smsDecisions, assessments: assessments)
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
    private func approvedConfirmation(_ record: EvidenceRecord, sources: [String: SourceDefinition], now: Date, sms: Bool) -> Bool {
        guard let trust = sources[record.sourceID]?.reviewedTrust, trust.confirmationAuthority,
              !sms || trust.smsJunkAuthority, [0.8, 1].contains(record.confirmationGrade),
              record.confirmationGrade <= trust.maximumConfirmationGrade,
              let method = record.confirmationMethod, trust.allowedConfirmationMethods.contains(method),
              let reviewed = record.confirmationReviewedAt, reviewed <= now, days(since: reviewed, now: now) <= 7,
              let expiry = record.confirmationExpiresAt, expiry > now,
              days(since: record.publisherWatermark, now: now) <= 14 else { return false }
        return true
    }
    private func evaluate(records: [EvidenceRecord], sources: [String: SourceDefinition], now: Date) throws -> ReputationResult {
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
        let confirmed = records.filter { approvedConfirmation($0, sources: sources, now: now, sms: false) }
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
        return try ReputationEngine.evaluate(independentFamilyValues: families, confirmation: best?.confirmationGrade ?? 0,
            confirmationAgeDays: best.map { days(since: $0.confirmationReviewedAt!, now: now) } ?? 0,
            observedDays: min(14, observedDates.count), positivePenalty: trustedRecords.map(\.positivePenalty).max() ?? 0,
            uncertaintyPenalty: max(burstPenalty, trustedRecords.map(\.uncertaintyPenalty).max() ?? 0))
    }
}
