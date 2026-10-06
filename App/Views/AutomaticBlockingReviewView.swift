import SpamHoleCore
import SwiftUI

struct AutomaticBlockingReviewView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ReadableSection("Your local blocklist") {
                    Picker("Policy", selection: $model.settings.policy) {
                        ForEach(PolicyPreset.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.onChange(of: model.settings.policy) { _, _ in Task { await model.saveSettings() } }
                    Text("\(model.previewAutomaticCount.formatted()) numbers would be blocked automatically.")
                        .accessibilityIdentifier("blocking.previewCount")
                    Text("Computed from downloaded evidence on this device. Personal Allow rules and protected Contacts are excluded; personal Block rules retain priority.")
                    if let excluded = model.snapshot?.metadata.capacityExcludedCount, excluded > 0 {
                        Text("\(excluded.formatted()) additional eligible numbers exceed the selected database capacity.")
                    }
                    if model.snapshot?.metadata.eligibleAutomaticCount == 0 {
                        Text("No numbers currently qualify. After activation, future refreshes can add qualifying blocks automatically.")
                    } else if model.previewAutomaticCount == 0 {
                        Text("Personal blocks currently fill the available capacity. Qualifying automatic blocks can be added when capacity becomes available.")
                    }
                }
                ReadableSection("Before activating") {
                    Text("FTC reports are unverified and caller IDs can be spoofed. This policy can block wanted calls. Scores are inference indices, not proof of caller identity.")
                    Text("Conservative requires higher scores and more observed call dates; Aggressive accepts lower thresholds. You can change policy, allow a number, or turn automatic blocking off.")
                    Text("iOS applies changes after a successful installation. Updates are best-effort; old entries can remain active until the next successful reload.")
                }
                if let message = model.message { Section { Text(message).foregroundStyle(Color("WarningText")) } }
            }
            .disabled(model.isWorking)
            .spamHoleBackground().navigationTitle("Review").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.tint(.primary) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Activate") {
                        let reviewed = model.snapshot?.metadata.id
                        Task {
                            if await model.setAutomaticBlocking(true, reviewedGenerationID: reviewed) { dismiss() }
                        }
                    }.accessibilityIdentifier("blocking.activate")
                    .disabled(model.isWorking || model.snapshot?.metadata.scoringVersion != 2
                        || model.snapshot?.metadata.policy != model.settings.policy)
                }
            }
        }
    }
}
