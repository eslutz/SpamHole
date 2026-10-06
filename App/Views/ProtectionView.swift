import CallKit
import SwiftUI

struct ProtectionView: View {
    var model: AppModel
    @State private var reviewingBlocking = false

    var body: some View {
        List {
            Section {
                InformationCard(title: "Protection stays local", message: "Incoming calls never trigger a server lookup.", symbol: "lock.shield")
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            ReadableSection("Automatic reputation blocking") {
                StatusDetail(title: "Selected policy", value: model.settings.policy.rawValue.capitalized)
                StatusDetail(title: "Automatic blocking", value: model.settings.automaticBlockingEnabled ? "Activated" : "Awaiting review")
                StatusDetail(title: "Eligible automatic blocks", value: (model.snapshot?.metadata.eligibleAutomaticCount ?? 0).formatted())
                StatusDetail(title: "Computed automatic blocks", value: (model.snapshot?.metadata.exportedAutomaticCount ?? 0).formatted())
                    .accessibilityIdentifier("blocking.computedAutomatic")
                StatusDetail(title: "Computed personal blocks", value: (model.snapshot?.metadata.personalBlockCount ?? 0).formatted())
                if let excluded = model.snapshot?.metadata.capacityExcludedCount, excluded > 0 {
                    Text("\(excluded.formatted()) eligible numbers excluded by capacity.")
                }
                if !model.settings.automaticBlockingEnabled {
                    Button("Review Automatic Blocking") { reviewingBlocking = true }
                        .accessibilityIdentifier("blocking.review").disabled(model.isWorking || model.snapshot == nil)
                }
                Text("Blocks are generated from locally scored evidence. Personal rules are overrides. Computed changes take effect after a verified iOS installation.")
                    .font(.footnote).foregroundStyle(Color("SecondaryText"))
            }
            ReadableSection("Calls") {
                StatusDetail(title: "Call Directory", value: callStatus, symbol: "phone")
                Button("Open Call Blocking Settings") { Task { await model.openCallSettings() } }
                StatusDetail(title: "Installed in iOS", value: displayedDate(model.installed?.installedAt))
                if let installed = model.installed {
                    StatusDetail(title: "Identification entries", value: installed.identificationCount.formatted())
                    StatusDetail(title: "Blocking entries", value: installed.blockingCount.formatted())
                    if let metadata = model.installedBreakdown, metadata.scoringVersion == 2 {
                        StatusDetail(title: "Installed automatic blocks", value: (metadata.exportedAutomaticCount ?? 0).formatted())
                        StatusDetail(title: "Installed personal blocks", value: (metadata.personalBlockCount ?? 0).formatted())
                    } else {
                        Text("Block origin counts are available after the current generation is installed.")
                            .font(.footnote).foregroundStyle(Color("SecondaryText"))
                    }
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
            .sheet(isPresented: $reviewingBlocking) { AutomaticBlockingReviewView(model: model) }
    }

    private var callStatus: String {
        switch model.callStatus {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        default: model.testing ? "UI test mode" : "Not verified"
        }
    }
}
