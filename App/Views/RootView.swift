import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            Tab("Protection", systemImage: "shield.lefthalf.filled") {
                NavigationStack { ProtectionView(model: model) }
            }
            Tab("Sources", systemImage: "tray.and.arrow.down") {
                NavigationStack { SourcesView(model: model) }
            }
            Tab("Lookup", systemImage: "magnifyingglass") {
                NavigationStack { LookupView(model: model) }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack { SettingsView(model: model) }
            }
        }
        .sheet(isPresented: Binding(get: { !model.onboardingComplete }, set: { _ in })) {
            OnboardingView(model: model).interactiveDismissDisabled()
        }
        .alert("SpamHole", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}
