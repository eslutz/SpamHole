import BackgroundTasks
import UIKit
import SpamHoleCore

@MainActor
final class BackgroundDelegate: NSObject, UIApplicationDelegate {
    static weak var model: AppModel?
    static var refreshID: String { AppIdentity.current?.refreshIdentifier ?? "unconfigured.SpamHole.refresh" }
    static var processingID: String { AppIdentity.current?.processingIdentifier ?? "unconfigured.SpamHole.processing" }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return true }
        #endif
        guard AppIdentity.current != nil else { return true }
        for id in [Self.refreshID, Self.processingID] {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
                Task { @MainActor in Self.handle(task) }
            }
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == BackgroundSourceTransport.identifier else { completionHandler(); return }
        BackgroundSourceTransport.shared.reconnect(completion: completionHandler)
    }

    private static func handle(_ task: BGTask) {
        guard let model else { task.setTaskCompleted(success: false); return }
        schedule(model: model)
        let operation = Task { @MainActor in
            let succeeded = await model.refresh(onlyDue: true)
            task.setTaskCompleted(success: succeeded && !Task.isCancelled)
        }
        task.expirationHandler = { operation.cancel() }
    }

    static func schedule(model: AppModel) {
        guard !model.testing else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: processingID)
        guard let interval = model.cadenceInterval else { return }
        let earliest = Date(timeIntervalSinceNow: interval)
        let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
        refresh.earliestBeginDate = earliest
        let processing = BGProcessingTaskRequest(identifier: processingID)
        processing.requiresNetworkConnectivity = true
        processing.earliestBeginDate = earliest
        do {
            try BGTaskScheduler.shared.submit(refresh)
            try BGTaskScheduler.shared.submit(processing)
            model.backgroundStatus = "Requested; iOS chooses execution time."
        } catch {
            model.backgroundStatus = "Background scheduling unavailable. Foreground and manual refresh still work."
        }
    }
}
