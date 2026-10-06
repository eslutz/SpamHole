import SwiftUI

struct OnboardingView: View {
    var model: AppModel
    @State private var reviewingBlocking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 56)).foregroundStyle(Color("ActionAccent")).accessibilityHidden(true)
                    Text("Your lists.\nYour device.").font(.largeTitle.bold())
                    Text("SpamHole downloads reputation evidence, then keeps call identification and blocking local.")
                        .foregroundStyle(Color("SecondaryText"))
                    InformationCard(title: "Your policy builds your list", message: "SpamHole scores downloaded FTC evidence locally. Conservative, Balanced or Aggressive determines which numbers qualify for automatic blocking. Personal rules are overrides.", symbol: "phone.badge.checkmark")
                    Text("FTC reports are unverified. Scores cannot authenticate a caller, and blocking can suppress wanted calls.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                    Text("\(model.previewAutomaticCount.formatted()) automatic blocks in the current preview · \(model.settings.policy.rawValue.capitalized)")
                    Button("Review Automatic Blocking") { reviewingBlocking = true }
                        .disabled(model.isWorking || model.snapshot == nil)
                    Text("Activate after reviewing once. You can also continue and activate from Protection after the first download.")
                        .font(.footnote).foregroundStyle(Color("SecondaryText"))
                    InformationCard(title: "Enable call protection", message: "After setup, enable SpamHole in Settings under Phone → Call Blocking & Identification. The Protection tab includes instructions.", symbol: "switch.2")
                    InformationCard(title: "Updates are best-effort", message: "iOS controls background execution. Old call entries can remain installed until the next successful reload.", symbol: "clock")
                }.padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                Button("Continue") { model.finishOnboarding() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .frame(maxWidth: .infinity).accessibilityIdentifier("onboarding.continue")
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(.background)
            }.spamHoleBackground().navigationTitle("Welcome to SpamHole").navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $reviewingBlocking) { AutomaticBlockingReviewView(model: model) }
        }
    }
}
