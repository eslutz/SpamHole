import XCTest
import SpamHoleCore
import Contacts

/// Opt-in read-only diagnostics for an explicitly authorized physical device.
/// Reports sizes and error categories, never sender identifiers or file contents.
@MainActor
final class DeviceSnapshotDiagnosticsTests: XCTestCase {
    func testContactsPermissionBaselineWithoutRequestingAccess() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        // Never request access or enumerate the user's contacts in diagnostics.
        print("CONTACTS_PERMISSION_BASELINE: \(status.rawValue)")
        XCTAssertTrue([CNAuthorizationStatus.notDetermined, .restricted, .denied, .authorized, .limited].contains(status))
    }
    func testNormalSavedGenerationCanBeReadInRelease() throws {
        let identity = try XCTUnwrap(AppIdentity.current)
        let container = try XCTUnwrap(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identity.appGroupIdentifier))
        let root = container.appendingPathComponent(SnapshotFiles.sharedRelativePath)
        let generations = root.appendingPathComponent("generations")
        for generation in try FileManager.default.contentsOfDirectory(at: generations, includingPropertiesForKeys: nil) {
            let snapshot = generation.appendingPathComponent("snapshot.json")
            let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.path)
            print("SAVED_SNAPSHOT_BYTES: \(attributes[.size] ?? 0)")
        }
        let snapshot = try SnapshotFiles(rootURL: root).loadCurrent()
        XCTAssertFalse(snapshot.assessments.isEmpty)
        print("SAVED_ASSESSMENTS: \(snapshot.assessments.count)")
    }
}
