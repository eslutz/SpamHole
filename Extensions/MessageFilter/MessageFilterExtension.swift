import Foundation
import IdentityLookup
import SpamHoleCore

/// Reads sender decisions only. This target does not inspect message bodies,
/// log senders, write the App Group, or defer a query to a network service.
final class MessageFilterExtension: ILMessageFilterExtension, ILMessageFilterQueryHandling {
    func handle(
        _ queryRequest: ILMessageFilterQueryRequest,
        context: ILMessageFilterExtensionContext,
        completion: @escaping (ILMessageFilterQueryResponse) -> Void
    ) {
        let response = ILMessageFilterQueryResponse()
        response.action = .none

        if let sender = queryRequest.sender,
           let identity = AppIdentity.current,
           let container = FileManager.default.containerURL(
               forSecurityApplicationGroupIdentifier: identity.appGroupIdentifier
           ),
           let snapshot = try? SnapshotFiles(rootURL: container.appendingPathComponent(SnapshotFiles.sharedRelativePath)).loadSMSSnapshot() {
            switch snapshot.smsAction(for: sender, now: Date()) {
            case .allow: response.action = .allow
            case .junk: response.action = .junk
            case nil: break
            }
        }

        completion(response)
    }
}
