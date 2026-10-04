import CallKit
import SwiftUI

struct ProtectionView: View {
    var model: AppModel

    var body: some View {
        List {
            Section {
                InformationCard(title: "Protection stays local", message: "Incoming calls never trigger a server lookup.", symbol: "lock.shield")
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
                Text("Physical-device acceptance and distribution checks are required before public release.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
        }.spamHoleBackground().navigationTitle("Protection").refreshable { _ = await model.refresh() }
    }

    private var callStatus: String {
        switch model.callStatus {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        default: model.testing ? "UI test mode" : "Not verified"
        }
    }
}
