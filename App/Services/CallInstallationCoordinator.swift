import CallKit
import Foundation
import SpamHoleCore

@MainActor
final class CallInstallationCoordinator {
    static var extensionID: String { AppIdentity.current?.callDirectoryIdentifier ?? "unconfigured.SpamHole.CallDirectory" }
    private var installing = false

    func status() async -> CXCallDirectoryManager.EnabledStatus {
        await withCheckedContinuation { continuation in
            CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: Self.extensionID) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func install() async throws {
        guard !installing else { return }
        installing = true
        defer { installing = false }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: Self.extensionID) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    static func isCapacityFailure(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == CXErrorDomainCallDirectoryManager &&
            error.code == CXErrorCodeCallDirectoryManagerError.Code.maximumEntriesExceeded.rawValue
    }

    func openSettings() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CXCallDirectoryManager.sharedInstance.openSettings { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
