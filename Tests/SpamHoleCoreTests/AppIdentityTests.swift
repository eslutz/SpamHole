import XCTest
@testable import SpamHoleCore

final class AppIdentityTests: XCTestCase {
    func testCustomIdentityKeepsAppAndExtensionsConsistent() throws {
        let value = try AppIdentity(infoDictionary: [
            "SpamHoleContainingAppIdentifier": "org.example.CustomApp",
            "SpamHoleAppGroupIdentifier": "group.org.example.Shared"
        ])
        XCTAssertEqual(value.appGroupIdentifier, "group.org.example.Shared")
        XCTAssertEqual(value.callDirectoryIdentifier, "org.example.CustomApp.CallDirectory")
        XCTAssertEqual(value.refreshIdentifier, "org.example.CustomApp.refresh")
        XCTAssertEqual(value.processingIdentifier, "org.example.CustomApp.processing")
        XCTAssertEqual(value.downloadIdentifier, "org.example.CustomApp.source-downloads")
        XCTAssertEqual(value.keychainService, "org.example.CustomApp.sources")
    }
    func testMissingUnexpandedOrInvalidIdentityIsRejected() {
        for info in [[:], ["SpamHoleContainingAppIdentifier": "$(MISSING)", "SpamHoleAppGroupIdentifier": "group.example"],
                     ["SpamHoleContainingAppIdentifier": "org.example.App", "SpamHoleAppGroupIdentifier": "example"]] {
            XCTAssertThrowsError(try AppIdentity(infoDictionary: info))
        }
    }
}
