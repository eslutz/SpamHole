import CallKit
import SwiftUI

struct ProtectionView: View {
    var model: AppModel

    var body: some View {
        List {
            Section {
                InformationCard(title: "Protection stays local", message: "Your calls and messages never trigger a server lookup.", symbol: "lock.shield")
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            ReadableSection("Calls") {
                StatusDetail(title: "Call Directory", value: callStatus, symbol: "phone")
                Button("Open Call Blocking Settings") { Task { await model.openCallSettings() } }
                StatusDetail(title: "Installed in iOS", value: displayedDate(model.installed?.installedAt))
                if let installed = model.installed {
                    StatusDetail(title: "Identification entries", value: installed.identificationCount.formatted())
                    StatusDetail(title: "Blocking entries", value: installed.blockingCount.formatted())
                }
                if model.installed?.generationID != model.snapshot?.metadata.id {
                    Label("Computed changes are awaiting a verified iOS installation.", systemImage: "clock.arrow.circlepath")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                }
                if let installed = model.installed, Date().timeIntervalSince(installed.installedAt) > 3 * 86_400 {
                    Label("Installed data is more than three days old. Entries remain active until a successful reload.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Color("WarningText"))
                }
            }
            ReadableSection("SMS & MMS") {
                Label("Personal sender rules available", systemImage: "message")
                NavigationLink("Enable the Message Filter") { MessageSetupView() }
                Text("Automatic feed filtering awaits a vetted SMS source. SMS enablement cannot be verified by this app.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
            ReadableSection("Updates") {
                StatusDetail(title: "Last source download", value: displayedDate(model.sourceStates.compactMap(\.lastSuccessAt).max()), symbol: "tray.and.arrow.down")
                StatusDetail(title: "Computed generation", value: displayedDate(model.snapshot?.metadata.createdAt), symbol: "square.stack.3d.up")
                StatusDetail(title: "Requested cadence", value: model.settings.cadence.rawValue.capitalized)
                Button { Task { await model.refresh() } } label: {
                    HStack {
                        Label("Refresh Now", systemImage: "arrow.clockwise")
                        Spacer()
                        if model.isWorking { ProgressView() }
                    }
                }.disabled(model.isWorking).accessibilityIdentifier("protection.refresh")
                Text("Publisher updates and iOS background scheduling determine actual freshness.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
            Section {
                Label("Development build · public release gated", systemImage: "exclamationmark.shield")
                Text("A free/open SMS feed and physical-device acceptance are required before public release.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
        }.navigationTitle("Protection").refreshable { _ = await model.refresh() }
    }

    private var callStatus: String {
        switch model.callStatus {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        default: model.testing ? "UI test mode" : "Not verified"
        }
    }
}

struct MessageSetupView: View {
    var body: some View {
        List {
            ReadableSection("Enable in Settings") {
                Text("Open Settings → Apps → Messages → Unknown & Spam. Enable filtering for unknown senders, then choose SpamHole as the Message Filter. Settings labels may vary by iOS version.")
            }
            ReadableSection("Verify with a test sender") {
                Text("Add a personal SMS Junk rule for a number you control. Receive an SMS from that number while it is outside Contacts, then inspect its placement in Messages. Remove the test rule afterward.")
            }
            ReadableSection("Coverage") {
                Text("Apple applies this extension to SMS/MMS from unknown senders. Messages from Contacts and iMessage are outside this filter. SpamHole does not collect or display received messages.")
            }
        }.navigationTitle("Message Filter").navigationBarTitleDisplayMode(.inline)
    }
}
