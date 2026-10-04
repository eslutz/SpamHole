import SwiftUI

struct OnboardingView: View {
    var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 56)).foregroundStyle(.teal).accessibilityHidden(true)
                    Text("Your lists.\nYour device.").font(.largeTitle.bold())
                    Text("SpamHole downloads reputation evidence, then keeps call identification and sender filtering local.")
                        .foregroundStyle(Color("SecondaryText"))
                    InformationCard(title: "Reports are evidence", message: "FTC complaints produce call warnings. They do not prove that a caller owns the displayed number.", symbol: "phone.badge.checkmark")
                    InformationCard(title: "SMS is a separate decision", message: "Personal sender rules work now. Automatic SMS feed filtering is unavailable until a vetted free source is approved. iMessage is outside the supported filtering APIs.", symbol: "message")
                    InformationCard(title: "Enable both extensions", message: "After setup, enable SpamHole in Settings under Phone → Call Blocking & Identification and Messages → Unknown & Spam. The Protection tab includes instructions.", symbol: "switch.2")
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
            }.navigationTitle("Welcome to SpamHole").navigationBarTitleDisplayMode(.inline)
        }
    }
}
