import XCTest

/// Opt-in normal-container verification. Never resets data or opens Contacts.
/// Run only on an explicitly authorized development device.
@MainActor
final class DeviceAcceptanceTests: XCTestCase {
    func testPersonalBlockInstallsAndRemovalRestoresBaseline() throws {
        continueAfterFailure = true // Always attempt removal of the synthetic rule.
        let app = XCUIApplication()
        app.launchArguments = ["--device-testing-keep-awake"]
        app.launch()
        app.tabBars.buttons["Protection"].tap()
        let refresh = app.buttons["protection.refresh"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: refresh)
        waitForExpectations(timeout: 900)
        guard app.staticTexts["Call Directory, Enabled"].exists,
              app.staticTexts["Blocking entries, 0"].exists else {
            throw XCTSkip("Requires enabled Call Directory and an empty blocking baseline")
        }
        app.tabBars.buttons["Lookup"].tap()
        let canonical = "+12025550123"
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", canonical)).firstMatch
        guard !row.exists else { throw XCTSkip("Preserve an existing rule for the reserved test number") }
        app.buttons["rule.add"].tap()
        let sender = app.textFields["rule.sender"]
        sender.tap()
        sender.typeText("2025550123")
        if app.buttons["rule.action.block"].exists {
            app.buttons["rule.action.block"].tap()
        } else {
            app.segmentedControls["rule.action"].buttons["Block"].tap()
        }
        app.buttons["rule.save"].tap()
        XCTAssertTrue(app.buttons["rule.save"].waitForNonExistence(timeout: 60), "Save must finish and dismiss the editor before navigating")
        app.tabBars.buttons["Protection"].tap()
        XCTAssertTrue(app.tabBars.buttons["Protection"].isSelected)
        XCTAssertTrue(app.staticTexts["Blocking entries, 1"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists)
        app.tabBars.buttons["Lookup"].tap()
        if row.waitForExistence(timeout: 10) {
            row.swipeLeft()
            let remove = app.buttons["Remove"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            if remove.exists { remove.tap() }
        } else { XCTFail("Synthetic rule must remain available for cleanup") }
        app.tabBars.buttons["Protection"].tap()
        XCTAssertTrue(app.staticTexts["Blocking entries, 0"].waitForExistence(timeout: 60))
        XCTAssertFalse(app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists)
    }

    func testNormalContainerAndPublisherRefresh() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "SpamHole status notice") { alert in
            guard alert.staticTexts["SpamHole"].exists, alert.buttons["OK"].exists else { return false }
            let notice = XCTAttachment(string: alert.debugDescription)
            notice.name = "SpamHole status notice"
            notice.lifetime = .keepAlways
            self.add(notice)
            alert.buttons["OK"].tap()
            return true
        }
        let app = XCUIApplication()
        // Only suppress auto-lock; retain normal App Group, network and installer.
        app.launchArguments = ["--device-testing-keep-awake"]
        if app.state == .runningForeground || app.state == .runningBackground {
            app.activate()
        } else {
            app.launch()
        }
        let welcome = app.buttons["onboarding.continue"]
        if welcome.waitForExistence(timeout: 3) { welcome.tap() }
        let sources = app.tabBars.buttons["Sources"]
        XCTAssertTrue(sources.waitForExistence(timeout: 20), "Normal shared-container startup must succeed")
        XCTAssertFalse(app.staticTexts["UI test mode"].exists)
        app.tabBars.buttons["Protection"].tap()
        let refresh = app.buttons["protection.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        let idle = NSPredicate(format: "enabled == true")
        expectation(for: idle, evaluatedWith: refresh)
        waitForExpectations(timeout: 900)
        sources.tap()
        let publisher = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "FTC reported unwanted calls")).firstMatch
        XCTAssertTrue(publisher.waitForExistence(timeout: 10))
        publisher.tap()
        // Capture only this public publisher's health, without lookup/rule/contact data.
        let health = XCTAttachment(string: app.debugDescription)
        health.name = "Normal publisher health"
        health.lifetime = .keepAlways
        add(health)
        XCTAssertFalse(app.staticTexts["Last downloaded, Not yet"].exists, "The FTC import must finish successfully")
        XCTAssertFalse(app.staticTexts["Accepted records, 0"].exists, "The real FTC source must contain accepted records")
        app.tabBars.buttons["Protection"].tap()
        let protection = XCTAttachment(string: app.debugDescription)
        protection.name = "Normal protection installation state"
        protection.lifetime = .keepAlways
        add(protection)
        XCTAssertTrue(app.buttons["Open Call Blocking Settings"].exists)
        XCTAssertTrue(app.staticTexts["Call Directory, Enabled"].exists)
        XCTAssertFalse(app.staticTexts["Installed in iOS, Not yet"].exists)
        XCTAssertFalse(app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists)
    }
}

/// Selected only by the profiling scheme, one method at a time. The agent must
/// restore Daily after capture; these methods require that observed baseline.
@MainActor
final class ReleaseTraceSetupTests: XCTestCase {
    func testPrepareManualCadence() throws { try setCadence(from: "Daily", to: "Manual") }
    func testRestoreDailyCadence() throws { try setCadence(from: "Manual", to: "Daily") }

    private func setCadence(from prior: String, to requested: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        app.tabBars.buttons["Protection"].tap()
        let refresh = app.buttons["protection.refresh"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: refresh)
        waitForExpectations(timeout: 30)
        guard app.staticTexts["Requested cadence, " + prior].exists else {
            throw XCTSkip("Preserve unexpected cadence instead of changing it")
        }
        app.tabBars.buttons["Settings"].tap()
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Requested cadence")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons[requested].tap()
        app.tabBars.buttons["Protection"].tap()
        XCTAssertTrue(app.staticTexts["Requested cadence, " + requested].waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: refresh)
        waitForExpectations(timeout: 30)
    }
}
