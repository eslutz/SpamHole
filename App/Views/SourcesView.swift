import SpamHoleCore
import SwiftUI

struct SourcesView: View {
    var model: AppModel
    @State private var presentingAdd = false

    var body: some View {
        List {
            Section {
                Text("Subscriptions are downloaded directly from publishers. Unknown feeds can identify callers, but cannot authorize call blocking.")
                    .font(.subheadline).foregroundStyle(Color("SecondaryText"))
            }
            ReadableSection("Subscriptions") {
                ForEach(model.sources) { source in
                    NavigationLink {
                        SourceDetailView(model: model, sourceID: source.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(source.name).font(.headline)
                                Spacer()
                                Text(SourceCatalog.activationBlocker(for: source) == nil ? (source.enabled ? "Enabled" : "Disabled") : "Unavailable").font(.caption).foregroundStyle(Color("SecondaryText"))
                            }
                            Text(source.url.host ?? "Publisher").font(.subheadline).foregroundStyle(Color("SecondaryText"))
                            if let state = model.sourceStates.first(where: { $0.sourceID == source.id }) {
                                if let error = state.error {
                                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color("WarningText"))
                                } else {
                                    Text("\(state.recordCount.formatted()) records · \(displayedDate(state.lastSuccessAt))")
                                        .font(.caption).foregroundStyle(Color("SecondaryText"))
                                }
                            } else { Text("Not downloaded").font(.caption).foregroundStyle(Color("SecondaryText")) }
                        }.padding(.vertical, 4)
                    }
                }
            }

        }
        .spamHoleBackground().navigationTitle("Sources")
        .toolbar {
            Button("Add Source", systemImage: "plus") { presentingAdd = true }
                .accessibilityIdentifier("source.add")
        }
        .sheet(isPresented: $presentingAdd) { AddSourceView(model: model) }
    }
}

struct SourceDetailView: View {
    var model: AppModel
    let sourceID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let source = model.sources.first(where: { $0.id == sourceID }) {
            List {
                Section {
                    Toggle("Use this source", isOn: Binding(get: { source.enabled }, set: { enabled in
                        Task { await model.setSource(source, enabled: enabled) }
                    })).disabled(model.isWorking || SourceCatalog.activationBlocker(for: source) != nil)
                    if let blocker = SourceCatalog.activationBlocker(for: source) {
                        Text(blocker).font(.footnote).foregroundStyle(Color("SecondaryText"))
                    }
                    Link("Publisher", destination: source.url)
                    StatusDetail(title: "Evidence", value: evidenceDescription(source.format))
                    if source.format == .phoneBlockJSON {
                        NavigationLink("Access token") { SourceCredentialView(model: model, sourceID: source.id) }
                    }
                    StatusDetail(title: "Evidence family", value: source.sourceFamilyID)
                    Text(source.license ?? "Dataset rights have not been reviewed. You are responsible for the subscription's permitted use.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
                ReadableSection("Health") {
                    let state = model.sourceStates.first { $0.sourceID == sourceID }
                    StatusDetail(title: "Last attempted", value: displayedDate(state?.lastAttemptAt))
                    StatusDetail(title: "Last downloaded", value: displayedDate(state?.lastSuccessAt))
                    StatusDetail(title: source.format == .phoneBlockJSON ? "Latest known activity" : "Published coverage",
                        value: displayedDate(state?.publisherWatermark.flatMap { $0.timeIntervalSince1970 >= 0 ? $0 : nil }))
                    if let events = state?.eventRecordCount { StatusDetail(title: "Report records", value: events.formatted()) }
                    if let aggregates = state?.aggregateRecordCount { StatusDetail(title: "Community summaries", value: aggregates.formatted()) }
                    if let rejected = state?.rejectedRecordCount { StatusDetail(title: "Excluded records", value: rejected.formatted()) }
                    if let due = state?.nextRefreshAt { StatusDetail(title: "Next permitted refresh", value: displayedDate(due)) }
                    StatusDetail(title: "Accepted records", value: (state?.recordCount ?? 0).formatted())
                    if let error = state?.error { Text(error).foregroundStyle(Color("WarningText")) }
                }
                ReadableSection("Authority") {
                    Text(source.reviewedTrust?.localInferenceEligible == true
                        ? "Reviewed for local-inference blocking. Reports are unverified; the selected policy computes eligibility on this device."
                        : "Identification evidence only. This source is not reviewed for automatic local blocking.")
                    Text("Refreshing an unchanged list does not make its allegations new. Mirrors do not add independent corroboration.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
                if !SourceCatalog.builtIns.contains(where: { $0.id == sourceID }) {
                    Section {
                        Button("Remove Source", role: .destructive) {
                            Task { await model.removeSource(source); dismiss() }
                        }.disabled(model.isWorking)
                    }
                }
            }.spamHoleBackground().navigationTitle(source.name).navigationBarTitleDisplayMode(.inline)
        } else { ContentUnavailableView("Source removed", systemImage: "tray") }
    }
}

struct AddSourceView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""
    @State private var format: SourceFormat = .evidenceJSON
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                ReadableSection("Publisher") {
                    Text("Name").font(.body)
                    TextField("Publisher name", text: $name).font(.body).accessibilityLabel("Publisher name").accessibilityIdentifier("source.name")
                    Text("HTTPS feed URL").font(.body)
                    TextField("https://publisher.example/feed", text: $url).font(.body).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().keyboardType(.URL).accessibilityLabel("HTTPS feed URL").accessibilityIdentifier("source.url")
                    if dynamicTypeSize.isAccessibilitySize {
                        Text("Format").font(.headline)
                        AccessibleChoice(title: "Evidence JSON v1", selected: format == .evidenceJSON, identifier: "source.format.json") { format = .evidenceJSON }
                        AccessibleChoice(title: "Plain phone-number list", selected: format == .identificationCSV, identifier: "source.format.csv") { format = .identificationCSV }
                    } else {
                        Picker("Format", selection: $format) {
                            Text("Evidence JSON v1").tag(SourceFormat.evidenceJSON)
                            Text("Plain phone-number list").tag(SourceFormat.identificationCSV)
                        }
                    }
                    Text("Bearer token (optional)").font(.body)
                    SecureField("Enter a token if required", text: $token).font(.body)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Bearer token, optional").accessibilityIdentifier("source.token")
                }
                Section {
                    Text("Custom lists produce neutral caller identification. Source approval and confirmation authority cannot be set by a subscription.")
                    Text("A token is stored in Keychain and sent only to this feed's publisher. Do not place secrets in the URL.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
                if let error { Section { Text(error).foregroundStyle(Color("ErrorText")) } }
            }
            .spamHoleBackground().navigationTitle("Add Source").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(.primary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saving = true
                        Task {
                            do { try await model.addSource(name: name, url: url, format: format, token: token); dismiss() }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(saving || model.isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || url.isEmpty)
                }
            }
        }
    }
}

private func evidenceDescription(_ format: SourceFormat) -> String {
    switch format {
    case .ftcCSV, .fccCallsJSON: "Dated unwanted-call reports"
    case .phoneBlockJSON: "Community ratings and vote buckets"
    case .callShieldJSON: "Community reports and reviews"
    case .evidenceJSON: "Publisher evidence"
    case .identificationCSV: "Exact phone-number list"
    case .fccJSON: "Retired source"
    }
}

private struct SourceCredentialView: View {
    var model: AppModel
    let sourceID: String
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var error: String?
    @State private var saving = false
    @State private var confirmingRemoval = false

    var body: some View {
        Form {
            ReadableSection("Publisher access") {
                SecureField("New bearer token", text: $token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("New publisher bearer token").accessibilityIdentifier("source.credential")
                Text("Stored in Keychain and sent only to this publisher. Changing access removes the previous account's cached reputation data.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
                if let source = model.sources.first(where: { $0.id == sourceID }), let blocker = SourceCatalog.activationBlocker(for: source) {
                    Text(blocker).font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
                Button("Save Token") { save(token) }
                    .disabled(saving || model.isWorking || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("source.credential.save")
                Button("Remove Token", role: .destructive) { confirmingRemoval = true }.disabled(saving || model.isWorking)
            }
            if let error { Section { Text(error).foregroundStyle(Color("ErrorText")) } }
        }
        .spamHoleBackground().navigationTitle("Publisher access").navigationBarTitleDisplayMode(.inline)
        .alert("Remove publisher access?", isPresented: $confirmingRemoval) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) { save("") }
        } message: { Text("This removes the token and cached reputation data for this source.") }
    }
    private func save(_ replacement: String) {
        saving = true
        Task {
            do { try await model.saveSourceCredential(sourceID: sourceID, token: replacement); token = ""; dismiss() }
            catch let failure { error = failure.localizedDescription }
            saving = false
        }
    }
}
