import Contacts
import SpamHoleCore
import SwiftUI
import UIKit

@main
struct SpamHoleApp: App {
    @UIApplicationDelegateAdaptor(BackgroundDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel?
    private let startupError: String?
    private let testingColorScheme: ColorScheme?
    private let keepAwakeForTesting: Bool

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing")
        keepAwakeForTesting = testing || arguments.contains("--device-testing-keep-awake")
        testingColorScheme = arguments.contains("--ui-testing")
            ? (arguments.contains("--ui-testing-dark") ? .dark : arguments.contains("--ui-testing-light") ? .light : nil)
            : nil
        #else
        let testing = false
        testingColorScheme = nil
        keepAwakeForTesting = false
        #endif
        #if DEBUG
        UIApplication.shared.isIdleTimerDisabled = keepAwakeForTesting
        #endif
        do {
            let root: URL
            if testing {
                root = FileManager.default.temporaryDirectory.appendingPathComponent("SpamHole-UITests", isDirectory: true)
                try? FileManager.default.removeItem(at: root)
            } else if let identity = AppIdentity.current, let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identity.appGroupIdentifier) {
                root = group.appendingPathComponent("SpamHole", isDirectory: true)
            } else {
                throw SpamHoleCoreError.invalidValue("The shared protection container is unavailable. Configure the SpamHole App Group for the app and Call Directory extension, then reinstall.")
            }
            let appModel = try AppModel(rootURL: root, testing: testing)
            _model = State(initialValue: appModel)
            startupError = nil
            BackgroundDelegate.model = appModel
        } catch {
            _model = State(initialValue: nil)
            startupError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView(model: model)
                    .tint(Color("ActionAccent"))
                    .preferredColorScheme(testingColorScheme)
                    .task { await model.becomeActive() }
                    .onChange(of: scenePhase) { _, phase in
                        #if DEBUG
                        UIApplication.shared.isIdleTimerDisabled = keepAwakeForTesting && phase == .active
                        #endif
                        if phase == .active { Task { await model.becomeActive() } }
                        if phase == .background { BackgroundDelegate.schedule(model: model) }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .CNContactStoreDidChange)) { _ in
                        Task { await model.rebuild() }
                    }
            } else {
                ContentUnavailableView("Protection unavailable", systemImage: "exclamationmark.shield",
                    description: Text(startupError ?? "The local database could not be opened."))
            }
        }
    }
}
