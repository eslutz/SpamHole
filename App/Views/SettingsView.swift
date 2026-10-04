import SpamHoleCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var exporting = false
    @State private var importing = false
    @State private var backup: RuleBackupDocument?

    var body: some View {
        Form {
            ReadableSection("Reputation") {
                Picker("Policy", selection: $model.settings.policy) {
                    ForEach(PolicyPreset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.onChange(of: model.settings.policy) { _, _ in Task { await model.saveSettings() } }
                Text("Presets change identification thresholds. Automatic feed blocking is unavailable until a qualifying confirmation source is reviewed.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
            ReadableSection("Refresh") {
                Picker("Requested cadence", selection: $model.settings.cadence) {
                    ForEach(RefreshCadence.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.onChange(of: model.settings.cadence) { _, _ in
                    Task { await model.saveSettings(); BackgroundDelegate.schedule(model: model) }
                }
                if let status = model.backgroundStatus { Text(status).font(.footnote).foregroundStyle(Color("SecondaryText")) }
                Text("Foreground refresh runs when due. Manual-only disables scheduled network refresh. Evidence is still recomputed when the app opens.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
            ReadableSection("Protection") {
                Toggle("Protect accessible Contacts", isOn: Binding(get: { model.settings.contactProtection }, set: { value in
                    Task { await model.setContactProtection(value) }
                }))
                Text("Contacts stay on-device. Explicit personal rules take priority; limited access protects only the contacts available to SpamHole.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
            ReadableSection("Personal rule backup") {
                Button("Export Rules & Settings") {
                    do {
                        backup = try RuleBackupDocument(backup: RuleBackup(rules: model.rules, settings: model.settings))
                        exporting = true
                    } catch { model.message = error.localizedDescription }
                }
                Button("Import Rules & Settings") { importing = true }
                Text("Import replaces personal rules. Backups contain phone numbers and preferences; they exclude source credentials, contacts, and downloaded evidence.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
            ReadableSection("About") {
                NavigationLink("Privacy") { PrivacyView() }
                NavigationLink("Release Requirements") { ReleaseRequirementsView() }
                Button("Show Setup Again") { model.onboardingComplete = false }
                Text("SpamHole 1.0 · Open source · MIT\niPhone, iOS 26 or later")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
        }
        .disabled(model.isWorking)
        .navigationTitle("Settings")
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json, defaultFilename: "SpamHole-Rules") { result in
            if case .failure(let error) = result { model.message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): Task { await model.importBackup(from: url) }
            case .failure(let error): model.message = error.localizedDescription
            }
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            ReadableSection("On your device") {
                Text("Personal call rules, preferences, source credentials, evidence, and protection generations are stored locally. Contacts are accessed only when you enable protection and are never uploaded.")
            }
            ReadableSection("Publisher downloads") {
                Text("Subscribed publishers see ordinary download metadata, including IP address and timing. Requests retrieve non-personalized datasets, never the number that just called.")
            }
            ReadableSection("Incoming calls") {
                Text("iOS matches caller numbers against installed entries. SpamHole does not collect call history or upload incoming numbers.")
            }
            ReadableSection("Your control") {
                Text("No accounts, ads, or analytics SDKs. Exporting rules puts personal phone numbers into a file at a destination you choose. Credentials and contact data are excluded.")
            }
        }.navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
    }
}

struct ReleaseRequirementsView: View {
    var body: some View {
        List {
            ReadableSection("Device acceptance · pending") {
                Text("Real cellular call behavior, App Group access, Contacts conflicts, stale-entry removal, and database capacity must be verified on physical iPhones. Simulator testing does not establish these outcomes.")
            }
            ReadableSection("Distribution · pending") {
                Text("Signing, TestFlight delivery, hosted privacy/support pages, source attribution, and metadata review remain separate release requirements. This build has not been submitted to the App Store.")
            }
        }.navigationTitle("Release Requirements").navigationBarTitleDisplayMode(.inline)
    }
}
