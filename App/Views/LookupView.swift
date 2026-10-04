import SpamHoleCore
import SwiftUI

struct LookupView: View {
    var model: AppModel
    @State private var sender = ""
    @FocusState private var senderFocused: Bool
    @State private var canonical: String?
    @State private var error: String?
    @State private var showingRule = false
    @State private var correction: CorrectionSelection?

    var body: some View {
        List {
            ReadableSection("Search your local database") {
                Text("Phone number or SMS sender").font(.body)
                TextField("Enter an exact identifier", text: $sender)
                    .font(.body).focused($senderFocused)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Phone number or SMS sender").accessibilityIdentifier("lookup.sender").submitLabel(.search).onSubmit(lookup)
                Button("Look Up", action: lookup).accessibilityIdentifier("lookup.search")
                if let error { Text(error).font(.footnote).foregroundStyle(Color("ErrorText")) }
            }
            if let canonical {
                ReadableSection("Exact identifier") {
                    Text(canonical).font(.headline).textSelection(.enabled).accessibilityIdentifier("lookup.canonicalSender")
                    if let assessment = model.assessment(for: canonical) {
                        StatusDetail(title: "Association index", value: assessment.result.associationIndex.formatted(.number.precision(.fractionLength(1))))
                        StatusDetail(title: "Block-safety index", value: assessment.result.blockSafetyIndex.formatted(.number.precision(.fractionLength(1))))
                        Text(assessment.explanation).font(.subheadline)
                        StatusDetail(title: "Latest evidence", value: displayedDate(assessment.lastEvidenceAt))
                        Text("Sources: " + assessment.sourceIDs.map { id in model.sources.first(where: { $0.id == id })?.name ?? id }.joined(separator: ", "))
                            .font(.footnote).foregroundStyle(Color("SecondaryText"))
                    } else {
                        Text("No scored evidence in the latest local generation. Absence from a list does not verify that a call or message is legitimate.")
                            .foregroundStyle(Color("SecondaryText"))
                    }
                    if let action = model.snapshot?.smsAction(for: canonical) {
                        StatusDetail(title: "SMS decision", value: action == .allow ? "Allow" : "Junk")
                            .accessibilityIdentifier("lookup.smsDecision")
                    }
                    Text("Indices describe evidence and policy. They are not percentages or caller authentication.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                    Button("Correct This Listing") { correction = CorrectionSelection(sender: canonical) }
                        .disabled(model.isWorking)
                }
            }
            ReadableSection("Personal rules") {
                if model.rules.isEmpty { Text("No personal rules yet").foregroundStyle(Color("SecondaryText")) }
                ForEach(model.rules) { rule in
                    HStack(alignment: .top) {
                        Image(systemName: rule.action == .allow ? "checkmark.shield" : "hand.raised")
                            .foregroundStyle(rule.action == .allow ? Color.teal : Color.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.identifier).font(.headline)
                            Text("\(rule.action == .allow ? "Allow" : "Block / Junk") · \(rule.channel.displayName)")
                                .font(.caption).foregroundStyle(Color("SecondaryText"))
                            if let note = rule.note { Text(note).font(.caption).foregroundStyle(Color("SecondaryText")) }
                        }
                    }.accessibilityElement(children: .combine)
                    .swipeActions { Button("Remove", role: .destructive) { Task { await model.deleteRule(rule) } } }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Lookup")
        .toolbar { Button("Add Rule", systemImage: "plus") { senderFocused = false; showingRule = true }.accessibilityIdentifier("rule.add") }
        .sheet(isPresented: $showingRule) { RuleEditorView(model: model, initialSender: sender) }
        .sheet(item: $correction) { selection in
            CorrectionView(model: model, sender: selection.sender)
        }
    }

    private func lookup() {
        senderFocused = false
        do { canonical = try PhoneNormalizer.smsIdentifier(sender); error = nil }
        catch { canonical = nil; self.error = error.localizedDescription }
    }
}

private struct CorrectionSelection: Identifiable {
    let sender: String
    var id: String { sender }
}

struct CorrectionView: View {
    var model: AppModel
    let sender: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var reason = "Wanted caller or sender"
    @State private var error: String?
    @State private var saving = false

    private let reasons = ["Wanted caller or sender", "Wrong number", "Number reassigned", "Number being spoofed", "Source record withdrawn"]
    var body: some View {
        NavigationStack {
            Form {
                ReadableSection("Personal correction") {
                    Text(sender).textSelection(.enabled)
                    if dynamicTypeSize.isAccessibilitySize {
                        Text("Reason").font(.headline)
                        ForEach(Array(reasons.enumerated()), id: \.offset) { index, value in
                            AccessibleChoice(title: value, selected: reason == value, identifier: "correction.reason.\(index)") { reason = value }
                        }
                    } else {
                        Picker("Reason", selection: $reason) {
                            ForEach(reasons, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    Text("This saves a private allow rule for this exact sender. It does not verify its owner or send a report to the publisher. Installed call entries change only after a successful reload.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
                if let error { Section { Text(error).foregroundStyle(Color("ErrorText")) } }
            }
            .navigationTitle("Correct Listing").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(.primary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            do {
                                let channel: CommunicationChannel = (try? PhoneNormalizer.callNumber(sender)) == nil ? .sms : .both
                                try await model.saveRule(raw: sender, channel: channel, action: .allow, note: reason)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(saving || model.isWorking)
                }
            }
        }
    }
}

struct RuleEditorView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var sender: String
    @FocusState private var senderFocused: Bool
    @State private var channel: CommunicationChannel = .both
    @State private var action: RuleAction = .allow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var error: String?
    @State private var saving = false

    init(model: AppModel, initialSender: String = "") {
        self.model = model
        _sender = State(initialValue: initialSender)
    }

    var body: some View {
        NavigationStack {
            Form {
                ReadableSection("Exact sender") {
                    Text("Phone number or SMS sender").font(.body)
                    TextField("Enter an exact identifier", text: $sender)
                        .font(.body).focused($senderFocused).textInputAutocapitalization(.never)
                        .onSubmit { senderFocused = false }
                        .autocorrectionDisabled().submitLabel(.done).accessibilityLabel("Phone number or SMS sender").accessibilityIdentifier("rule.sender")
                }
                if dynamicTypeSize.isAccessibilitySize {
                    ReadableSection("Applies to") {
                        ForEach(CommunicationChannel.allCases, id: \.self) { value in
                            choice(value.displayName, selected: channel == value, id: "rule.channel.\(value.rawValue)") { channel = value }
                        }
                    }
                    ReadableSection("Decision") {
                        choice("Allow", selected: action == .allow, id: "rule.action.allow") { action = .allow }
                        choice("Block / Junk", selected: action == .block, id: "rule.action.block") { action = .block }
                    }
                } else {
                    ReadableSection("Rule choices") {
                        Picker("Applies to", selection: $channel) {
                            ForEach(CommunicationChannel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }.pickerStyle(.menu).accessibilityIdentifier("rule.channel")
                        Picker("Decision", selection: $action) {
                            Text("Allow").tag(RuleAction.allow)
                            Text("Block / Junk").tag(RuleAction.block)
                        }.pickerStyle(.segmented).accessibilityIdentifier("rule.action")
                    }
                }
                Section {
                    Text("Allow rules take priority. A Block / Junk rule blocks calls and/or sends SMS to Junk for the selected channel. It affects only SpamHole.")
                    Text("Use SMS only for short codes and alphanumeric senders. Complete numbers are required for calls; prefixes and ranges are rejected.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
                if let error { Section { Text(error).foregroundStyle(Color("ErrorText")) } }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Personal Rule").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { senderFocused = false; dismiss() }.tint(.primary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        senderFocused = false
                        saving = true
                        Task {
                            do { try await model.saveRule(raw: sender, channel: channel, action: action); dismiss() }
                            catch { self.error = error.localizedDescription }
                            saving = false
                        }
                    }.disabled(sender.isEmpty || saving || model.isWorking).accessibilityIdentifier("rule.save")
                }
            }
        }
    }
    private func choice(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.frame(minHeight: 44)
        }
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

extension CommunicationChannel {
    var displayName: String {
        switch self { case .call: "Calls"; case .sms: "SMS"; case .both: "Both" }
    }
}
