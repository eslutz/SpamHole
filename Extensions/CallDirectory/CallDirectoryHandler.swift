import CallKit
import Foundation
import SpamHoleCore

/// Installs a single immutable generation. Downloading and scoring belong to the app.
final class CallDirectoryHandler: CXCallDirectoryProvider, CXCallDirectoryExtensionContextDelegate {
    private let requestState = RequestState()

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self
        requestState.reset()

        do {
            guard let identity = AppIdentity.current, let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identity.appGroupIdentifier
            ) else {
                throw InstallationError.unavailableContainer
            }
            let files = SnapshotFiles(rootURL: container.appendingPathComponent(SnapshotFiles.sharedRelativePath))
            let snapshot = try files.callDirectoryReader()

            // A reset is safe even if a previous acknowledgement was lost. Removal APIs
            // are legal only when iOS requests incremental data.
            if context.isIncremental {
                context.removeAllBlockingEntries()
                context.removeAllIdentificationEntries()
            }
            try snapshot.streamBlocking { number in
                context.addBlockingEntry(withNextSequentialPhoneNumber: number)
            }
            try snapshot.streamIdentification { entry in
                context.addIdentificationEntry(
                    withNextSequentialPhoneNumber: entry.number,
                    label: entry.label
                )
            }

            let state = requestState
            let generationID = snapshot.metadata.id
            let identificationCount = snapshot.metadata.callIdentificationCount
            let blockingCount = snapshot.metadata.callBlockCount
            context.completeRequest { expired in
                // Apple's completion Boolean means "expired", not "succeeded".
                // Never advance the receipt for a failed or expired request.
                guard !expired, !state.failed else { return }
                let receipt = CallInstallationReceipt(
                    generationID: generationID,
                    installedAt: Date(),
                    identificationCount: identificationCount,
                    blockingCount: blockingCount
                )
                try? files.writeInstallationReceipt(receipt)
            }
        } catch {
            requestState.markFailed()
            // Cancel rather than clearing the previous installed generation when a
            // snapshot is missing or corrupt. Do not include phone numbers in errors.
            context.cancelRequest(withError: NSError(
                domain: AppIdentity.current?.callDirectoryIdentifier ?? "SpamHole.CallDirectory",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The call snapshot could not be installed. Open SpamHole and rebuild protection."]
            ))
        }
    }

    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: any Error) {
        requestState.markFailed()
    }

}

private enum InstallationError: Error {
    case unavailableContainer
}

/// CallKit may report failure from a different queue than its completion handler.
private final class RequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var didFail = false

    var failed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didFail
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        didFail = false
    }

    func markFailed() {
        lock.lock()
        defer { lock.unlock() }
        didFail = true
    }
}
