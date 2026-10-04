import XCTest

@MainActor
final class OfflineLaunchPerformanceTests: XCTestCase {
    func testIsolatedEmptyLaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-light",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
            XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 15))
            app.terminate()
        }
        let context = XCTAttachment(string: "Debug isolated empty-root launch; UI test flag removes only " +
            "SpamHole-UITests temporary root on every launch; no production data/network/Contacts. " +
            "Application launch metric and onboarding existence check; not saved-data launch or Release acceptance.")
        context.name = "Launch measurement context"; context.lifetime = .keepAlways; add(context)
    }
}
