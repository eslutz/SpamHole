import CallKit
import Contacts
import Foundation
import Observation
import SpamHoleCore

@MainActor @Observable
final class AppModel {
    var sources: [SourceDefinition] = []
    var sourceStates: [SourceState] = []
    var rules: [PersonalRule] = []
    var settings = AppSettings()
    private var preparedSnapshot: PreparedProtectionSnapshot?
    var snapshot: ProtectionSnapshot? { preparedSnapshot?.snapshot }
    var installed: CallInstallationReceipt?
    var onboardingComplete = false
    var isWorking = false
    var message: String?
    var callStatus: CXCallDirectoryManager.EnabledStatus = .unknown
    var backgroundStatus: String?

    let testing: Bool
    let store: EvidenceStore
    let files: SnapshotFiles
    let pipeline: ProtectionPipeline
    let callInstaller = CallInstallationCoordinator()
    var assessmentCount: Int { preparedSnapshot?.assessmentPositions.count ?? 0 }
    func assessment(for identifier: String) -> ReputationAssessment? {
        preparedSnapshot?.assessment(for: identifier)
    }
    private var loadedSavedSnapshot = false
    private var protectedContacts: Set<String> = []
    private var rebuildPending = false

    init(rootURL: URL, testing: Bool = false) throws {
        #if DEBUG
        self.testing = testing
        #else
        self.testing = false
        #endif
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        if !self.testing {
            // Shared exports must remain readable for locked-screen calls after first unlock.
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                  ofItemAtPath: rootURL.path)
            var directory = rootURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        }
        store = try EvidenceStore(url: rootURL.appendingPathComponent("evidence.sqlite"))
        files = SnapshotFiles(rootURL: rootURL.appendingPathComponent("Protection"))
        pipeline = ProtectionPipeline(store: store, files: files)
        for source in SourceCatalog.builtIns where !(try store.sources()).contains(where: { $0.id == source.id }) {
            try store.saveSource(source)
        }
        settings = try store.setting(forKey: "app-settings", as: AppSettings.self) ?? AppSettings()
        onboardingComplete = try store.setting(forKey: "onboarding-complete", as: Bool.self) ?? false
        try loadState()
    }

    func loadState() throws {
        let loadedSources = try store.sources()
        let loadedStates = try store.sourceStates()
        let loadedRules = try store.rules()
        sources = loadedSources
        sourceStates = loadedStates
        rules = loadedRules
    }

    func becomeActive() async {
        guard !isWorking else { return }
        if !testing { callStatus = await callInstaller.status() }
        await rebuild()
        let due = RefreshPolicy.dueSourceIDs(sources: sources, states: sourceStates,
            cadence: settings.cadence, now: Date())
        if !testing, !isWorking, !due.isEmpty {
            await refresh(onlyDue: true)
        }
    }

    var cadenceInterval: TimeInterval? {
        switch settings.cadence {
        case .manual: nil
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }

    @discardableResult
    func refresh(onlyDue: Bool = false) async -> Bool {
        guard !isWorking, !Task.isCancelled else { return false }
        let due = onlyDue ? RefreshPolicy.dueSourceIDs(sources: sources, states: sourceStates,
            cadence: settings.cadence, now: Date()) : nil
        if let due, due.isEmpty { return await rebuild() }
        isWorking = true
        let errors = await pipeline.refresh(now: Date(), testing: testing, sourceIDs: due)
        let rebuilt = await drainRebuilds()
        isWorking = false
        if !errors.isEmpty { message = errors.joined(separator: "\n") }
        return errors.isEmpty && rebuilt && !Task.isCancelled
    }

    @discardableResult
    func rebuild() async -> Bool {
        guard !isWorking else { rebuildPending = true; return false }
        guard !Task.isCancelled else { return false }
        isWorking = true
        let succeeded = await drainRebuilds()
        isWorking = false
        return succeeded
    }

    private func drainRebuilds() async -> Bool {
        var succeeded = false
        repeat {
            rebuildPending = false
            succeeded = await rebuildWork()
        } while rebuildPending && !Task.isCancelled
        return succeeded && !Task.isCancelled
    }

    private func rebuildWork() async -> Bool {
        do {
            try Task.checkCancellation()
            if !loadedSavedSnapshot {
                do {
                    let saved = try await pipeline.loadSavedSnapshot()
                    try Task.checkCancellation()
                    publish(saved)
                    installed = try await pipeline.installationReceipt()
                    loadedSavedSnapshot = true
                } catch is CancellationError { return false }
                catch { message = "The saved protection generation could not be read. Rebuilding from local evidence." }
            }
            let rebuildSettings = settings
            protectedContacts = rebuildSettings.contactProtection && !testing ? try await pipeline.contactNumbers() : []
            let rebuilt = try await pipeline.rebuild(settings: rebuildSettings, protectedContacts: protectedContacts, now: Date())
            try Task.checkCancellation()
            try loadState()
            publish(rebuilt)
            loadedSavedSnapshot = true
            guard !testing else { return true }
            try Task.checkCancellation()
            callStatus = await callInstaller.status()
            guard callStatus == .enabled else { return true }
            do { try await callInstaller.install() }
            catch where CallInstallationCoordinator.isCapacityFailure(error) {
                let smaller = try await pipeline.rebuild(settings: rebuildSettings, protectedContacts: protectedContacts,
                    now: Date(), identificationLimit: 50_000, blockLimit: 5_000)
                try Task.checkCancellation()
                publish(smaller)
                try await callInstaller.install()
                message = "iOS accepted a smaller protection database. Explicit rules keep priority."
            }
            installed = try await pipeline.installationReceipt()
            if installed?.generationID != snapshot?.metadata.id {
                message = "iOS completed the reload, but an installation receipt is unavailable. Installation is not yet verified."
                return false
            }
            if let snapshot { try store.saveGeneration(snapshot.metadata, installed: true) }
            return true
        } catch is CancellationError { return false }
        catch { message = error.localizedDescription; return false }
    }

    private func publish(_ prepared: PreparedProtectionSnapshot?) {
        // Snapshot and its index are published together without suspension.
        preparedSnapshot = prepared
    }

    func saveRule(raw: String, action: RuleAction, note: String? = nil) async throws {
        let identifier = try PhoneNormalizer.callNumber(raw)
        let existing = rules.first { $0.identifier == identifier && $0.channel == .call }
        let rule = PersonalRule(id: existing?.id ?? UUID().uuidString, identifier: identifier, channel: .call,
                                action: action, note: note)
        try store.saveRule(rule)
        try loadState()
        await rebuild()
    }

    func deleteRule(_ rule: PersonalRule) async {
        do { try store.deleteRule(id: rule.id); try loadState(); await rebuild() }
        catch { message = error.localizedDescription }
    }

    func saveSettings() async {
        do {
            try store.setSetting(settings, forKey: "app-settings")
            await rebuild()
        } catch { message = error.localizedDescription }
    }

    func setContactProtection(_ enabled: Bool) async {
        do {
            let allowed = !enabled || testing ? true : try await ContactsProtection.requestAccess()
            settings.contactProtection = enabled && allowed
            if !allowed { message = "Contacts access was not granted. Personal allow rules are still available." }
            await saveSettings()
        } catch { message = error.localizedDescription }
    }

    func finishOnboarding() {
        do { try store.setSetting(true, forKey: "onboarding-complete"); onboardingComplete = true }
        catch { message = error.localizedDescription }
    }

    func setSource(_ source: SourceDefinition, enabled: Bool) async {
        var updated = source
        updated.enabled = enabled
        do { try store.saveSource(updated); try loadState(); await rebuild() }
        catch { message = error.localizedDescription }
    }

    func addSource(name: String, url: String, format: SourceFormat, token: String) async throws {
        guard let url = URL(string: url) else {
            throw SpamHoleCoreError.invalidValue("Enter an HTTPS feed URL without embedded credentials.")
        }
        let source = try SourceCatalog.custom(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url, format: format, channels: [.call])
        try KeychainCredentials.save(token: token, for: source.id)
        do { try store.saveSource(source) }
        catch { try? KeychainCredentials.remove(for: source.id); throw error }
        try loadState()
        await refresh()
    }

    func removeSource(_ source: SourceDefinition) async {
        do {
            try KeychainCredentials.remove(for: source.id)
            try store.removeSource(id: source.id)
            try loadState()
            await rebuild()
        } catch { message = error.localizedDescription }
    }

    func openCallSettings() async {
        do { try await callInstaller.openSettings() }
        catch { message = error.localizedDescription }
    }
}
