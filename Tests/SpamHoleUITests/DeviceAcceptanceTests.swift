import XCTest

/// Opt-in normal-container verification. Never resets data.
/// Run only on an explicitly authorized development device.
@MainActor
final class DeviceAcceptanceTests: XCTestCase {
    func testAcceptAuthorizedPendingContactsConsent() throws {
        guard ProcessInfo.processInfo.environment["SPAMHOLE_DEVICE_CONTACTS_TESTING"] == "1" else {
            throw XCTSkip("Full Contacts consent requires explicit device authorization")
        }
        continueAfterFailure = false
        let monitor = installFullContactsConsentMonitor()
        defer { removeUIInterruptionMonitor(monitor) }
        XCUIApplication(bundleIdentifier: "com.apple.Preferences").activate()
        XCUIApplication(bundleIdentifier: "com.apple.Preferences").swipeUp()
        let allow = fullContactsConsentButton()
        if allow.waitForExistence(timeout: 5) {
            allow.tap()
            print("CONTACTS_FULL_CONSENT_AUTOMATED")
        }
        try testAuthorizedSyntheticContactsCommand()
    }
    func testSetAuthorizedContactProtectionPreference() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SPAMHOLE_DEVICE_CONTACTS_TESTING"] == "1",
              let target = ProcessInfo.processInfo.environment["SPAMHOLE_CONTACT_PROTECTION_TARGET"],
              ["0", "1"].contains(target) else { throw XCTSkip("Contacts preference requires explicit target") }
        let app = XCUIApplication()
        app.launchArguments = ["--device-testing-keep-awake"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Protection"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Protection"].tap()
        waitForIdle(app)
        app.tabBars.buttons["Settings"].tap()
        let control = app.switches["Protect accessible Contacts"]
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        if control.value as? String != target {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(control.value as? String, target)
        app.tabBars.buttons["Protection"].tap()
        waitForIdle(app)
    }
    func testSelectLimitedSyntheticContact() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SPAMHOLE_DEVICE_CONTACTS_TESTING"] == "1" else {
            throw XCTSkip("Limited Contacts selection requires explicit authorization")
        }
        let settings = openNativeContactsControls()
        let edit = settings.buttons["Edit Selected Contacts"]
        if edit.waitForExistence(timeout: 5) { edit.tap() }
        let search = settings.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("SpamHole Acceptance A")
        let fixture = settings.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SpamHole Acceptance A")).firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 10))
        fixture.tap()
        let done = settings.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        XCUIApplication().activate()
    }
    func testAuthorizedSyntheticContactsCommand() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SPAMHOLE_DEVICE_CONTACTS_TESTING"] == "1",
              let action = ProcessInfo.processInfo.environment["SPAMHOLE_CONTACTS_COMMAND"],
              ["inspect", "create", "modify", "delete"].contains(action),
              let expected = ProcessInfo.processInfo.environment["SPAMHOLE_CONTACTS_RESULT"] else {
            throw XCTSkip("Synthetic Contacts command requires explicit authorized action and expectation")
        }
        let app = XCUIApplication()
        app.launchArguments = ["--device-testing-keep-awake", "--device-contacts-acceptance", action == "modify" ? "inspect" : action]
        app.launch()
        let result = app.staticTexts["device.contacts.result"]
        XCTAssertTrue(result.waitForExistence(timeout: 30))
        if action == "modify" {
            let cache = app.staticTexts["device.contacts.cached"]
            expectation(for: NSPredicate(format: "label == %@", "110"), evaluatedWith: cache)
            waitForExpectations(timeout: 60)
            app.tabBars.buttons["Protection"].tap()
            waitForIdle(app)
            app.buttons["device.contacts.modify"].tap()
            expectation(for: NSPredicate(format: "label == %@", expected), evaluatedWith: result)
            waitForExpectations(timeout: 30)
        }
        print("CONTACTS_ACCEPTANCE_CONTEXT: \(app.staticTexts["device.contacts.context"].label)")
        XCTAssertEqual(result.label, expected)
        if let cached = ProcessInfo.processInfo.environment["SPAMHOLE_CONTACTS_CACHED_RESULT"] {
            let cache = app.staticTexts["device.contacts.cached"]
            expectation(for: NSPredicate(format: "label == %@", cached), evaluatedWith: cache)
            waitForExpectations(timeout: 60)
            app.tabBars.buttons["Protection"].tap()
            waitForIdle(app)
            XCTAssertFalse(app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists)
        }
    }
    func testInspectNativeContactsControlsWithoutChangingAccess() throws {
        guard ProcessInfo.processInfo.environment["SPAMHOLE_DEVICE_CONTACTS_TESTING"] == "1" else {
            throw XCTSkip("Native Contacts controls require explicit device-test opt-in")
        }
        let settings = openNativeContactsControls()
        let hierarchy = XCTAttachment(string: settings.debugDescription)
        hierarchy.name = "Private native Settings navigation baseline"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCUIApplication().activate()
    }

    func testSetAuthorizedNativeContactsAccess() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["SPAMHOLE_DEVICE_CONTACTS_TESTING"] == "1",
              let access = ProcessInfo.processInfo.environment["SPAMHOLE_CONTACTS_ACCESS"],
              ["None", "Full Access", "Limited Access"].contains(access) else {
            throw XCTSkip("Native access transition requires explicit authorized target")
        }
        let monitor = installFullContactsConsentMonitor()
        defer { removeUIInterruptionMonitor(monitor) }
        let settings = openNativeContactsControls()
        let key = access == "None" ? "0" : access == "Full Access" ? "2" : "1"
        if key == "2" && settings.cells[key].isSelected {
            settings.cells["0"].tap()
        }
        let option = access == "None" ? settings.cells[key] : settings.buttons[key]
        XCTAssertTrue(option.waitForExistence(timeout: 10))
        option.tap()
        if access == "Full Access" {
            let allow = fullContactsConsentButton()
            if allow.waitForExistence(timeout: 10) {
                allow.tap()
                print("CONTACTS_FULL_CONSENT_AUTOMATED")
            }
        }
        if access == "Limited Access" {
            // Do not export a picker hierarchy containing existing contacts.
            print("LIMITED_CONTROLS search=\(settings.searchFields.firstMatch.exists) edit=\(settings.buttons["Edit Selected Contacts"].exists) done=\(settings.buttons["Done"].exists)")
            XCUIApplication().activate()
            return
        }
        let hierarchy = XCTAttachment(string: settings.debugDescription)
        hierarchy.name = "Private native Contacts transition result"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(settings.cells[key].isSelected)
        let back = settings.buttons["BackButton"]
        if back.exists { back.tap() }
        let app = XCUIApplication()
        app.activate()
        if let cached = ProcessInfo.processInfo.environment["SPAMHOLE_CONTACTS_CACHED_RESULT"] {
            if !app.staticTexts["device.contacts.cached"].waitForExistence(timeout: 2) {
                // Native permission changes can terminate the target process.
                // Reopen the same app with its observation-only Debug overlay.
                app.terminate()
                app.launchArguments = ["--device-testing-keep-awake", "--device-contacts-acceptance", "inspect"]
                app.launch()
            }
            expectation(for: NSPredicate(format: "label == %@", cached), evaluatedWith: app.staticTexts["device.contacts.cached"])
            waitForExpectations(timeout: 60)
            app.tabBars.buttons["Protection"].tap()
            waitForIdle(app)
            XCTAssertFalse(app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists)
        }
    }

    private func openNativeContactsControls() -> XCUIApplication {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for _ in 0..<4 {
            let back = settings.buttons["BackButton"]
            if !back.exists { break }
            back.tap()
        }
        let privacy = settings.buttons["com.apple.settings.privacyAndSecurity"]
        for _ in 0..<8 {
            if privacy.isHittable { break }
            settings.swipeUp()
        }
        if privacy.isHittable {
            privacy.tap()
            let contacts = settings.buttons["CONTACTS"]
            if contacts.waitForExistence(timeout: 10) {
                contacts.tap()
                let entry = settings.buttons.matching(NSPredicate(format: "label CONTAINS %@", "SpamHole")).firstMatch
                for _ in 0..<6 {
                    if entry.exists && entry.isHittable { break }
                    settings.swipeUp()
                }
                if entry.exists && entry.isHittable { entry.tap() }
            }
        }
        XCTAssertTrue(settings.navigationBars["SpamHole"].exists)
        return settings
    }

    private func fullContactsConsentButton() -> XCUIElement {
        let hosts = [XCUIApplication(bundleIdentifier: "com.apple.Preferences"),
                     XCUIApplication(bundleIdentifier: "com.apple.ContactsUI.FullAccessSettingsPromptExtension"),
                     XCUIApplication(bundleIdentifier: "com.apple.springboard"), XCUIApplication()]
        for host in hosts {
            guard host.state == .runningForeground else { continue }
            let button = host.buttons["Allow Full Access"]
            if button.exists { return button }
        }
        return hosts[0].buttons["Allow Full Access"]
    }

    private func installFullContactsConsentMonitor() -> NSObjectProtocol {
        addUIInterruptionMonitor(withDescription: "Authorized SpamHole Contacts consent") { alert in
            let title = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ AND label CONTAINS[c] %@", "SpamHole", "contacts")).firstMatch
            let allow = alert.buttons["Allow Full Access"]
            guard title.exists && allow.exists else { return false }
            allow.tap()
            print("CONTACTS_FULL_CONSENT_AUTOMATED")
            return true
        }
    }

    func testContactsDenialAndInspectNativePermissionControls() throws {
        guard ProcessInfo.processInfo.environment["SPAMHOLE_DEVICE_CONTACTS_TESTING"] == "1" else {
            throw XCTSkip("Contacts permission changes require explicit device-test opt-in")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--device-testing-keep-awake"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Protection"].tap()
        waitForIdle(app)
        app.tabBars.buttons["Settings"].tap()
        let protection = app.switches["Protect accessible Contacts"]
        XCTAssertTrue(protection.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true AND hittable == true"), evaluatedWith: protection)
        waitForExpectations(timeout: 60)
        guard protection.value as? String == "0" else { throw XCTSkip("Preserve existing enabled Contacts preference") }
        // SwiftUI exposes the full row as Switch; tap the trailing native control.
        protection.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let denialLabel = NSPredicate(format: "label == %@ OR label == %@", "Don’t Allow", "Don't Allow")
        let appDeny = app.buttons.matching(denialLabel).firstMatch
        let deny = appDeny.waitForExistence(timeout: 5) ? appDeny : system.buttons.matching(denialLabel).firstMatch
        let prompt = XCTAttachment(string: app.debugDescription + "\n" + system.debugDescription)
        prompt.name = "Private Contacts permission prompt"
        prompt.lifetime = .keepAlways
        add(prompt)
        XCTAssertTrue(deny.waitForExistence(timeout: 15))
        deny.tap()
        if app.alerts.buttons["OK"].waitForExistence(timeout: 5) { app.alerts.buttons["OK"].tap() }
        XCTAssertEqual(protection.value as? String, "0")
        let settings = openNativeContactsControls()
        let controls = XCTAttachment(string: settings.debugDescription)
        controls.name = "Private SpamHole native Contacts controls"
        controls.lifetime = .keepAlways
        add(controls)
        app.activate()
    }

    func testControlledCallerBlockAndAllow() throws {
        guard let number = ProcessInfo.processInfo.environment["SPAMHOLE_CONTROLLED_CALLER"],
              number.hasPrefix("+"), number.dropFirst().allSatisfy({ $0.isNumber }), number.count <= 16 else {
            throw XCTSkip("Supply an authorized owned caller privately in the test runner environment")
        }
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["--device-testing-keep-awake"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Protection"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Protection"].tap()
        waitForIdle(app)
        guard app.staticTexts["Call Directory, Enabled"].exists,
              app.staticTexts["Blocking entries, 0"].exists else {
            throw XCTSkip("Requires enabled extension and zero blocking baseline")
        }
        app.tabBars.buttons["Lookup"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", number)).firstMatch
        guard !row.exists else { throw XCTSkip("Preserve an existing caller rule") }
        // Attempt cleanup on every normal exit, including failed call observations.
        defer {
            app.activate()
            removeCallerRule(app, row: row)
            app.tabBars.buttons["Protection"].tap()
            waitForIdle(app)
            XCTAssertTrue(app.staticTexts["Blocking entries, 0"].exists)
            XCTAssertFalse(app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists)
        }
        saveCallerRule(app, number: number, block: true)
        app.tabBars.buttons["Protection"].tap()
        waitForIdle(app)
        guard app.staticTexts["Blocking entries, 1"].exists,
              !app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists else {
            XCTFail("Require installed block before placing a call"); return
        }
        XCUIDevice.shared.press(.home)
        let callUI = XCUIApplication(bundleIdentifier: "com.apple.InCallService")
        let incoming = callUI.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Accept", "Answer")).firstMatch
        print("CONTROLLED_BLOCK_CALL_READY")
        guard !incoming.waitForExistence(timeout: 45) else {
            XCTFail("Blocked caller reached recipient controls"); return
        }
        print("CONTROLLED_BLOCK_OBSERVATION_COMPLETE")
        app.activate()
        removeCallerRule(app, row: row)
        saveCallerRule(app, number: number, block: false)
        app.tabBars.buttons["Protection"].tap()
        waitForIdle(app)
        guard app.staticTexts["Blocking entries, 0"].exists,
              !app.staticTexts["Computed changes are awaiting a verified iOS installation."].exists else {
            XCTFail("Require installed allow generation before placing a call"); return
        }
        XCUIDevice.shared.press(.home)
        print("CONTROLLED_ALLOW_CALL_READY")
        guard incoming.waitForExistence(timeout: 90) else {
            XCTFail("Allowed caller did not reach recipient controls"); return
        }
        let evidence = XCTAttachment(string: callUI.debugDescription)
        evidence.name = "Private allowed-call recipient hierarchy"
        evidence.lifetime = .keepAlways
        add(evidence)
        print("CONTROLLED_ALLOW_OBSERVED")
        XCTAssertTrue(incoming.waitForNonExistence(timeout: 60))
    }

    private func waitForIdle(_ app: XCUIApplication) {
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["protection.refresh"])
        waitForExpectations(timeout: 60)
    }

    private func saveCallerRule(_ app: XCUIApplication, number: String, block: Bool) {
        app.tabBars.buttons["Lookup"].tap()
        app.buttons["rule.add"].tap()
        let sender = app.textFields["rule.sender"]
        XCTAssertTrue(sender.waitForExistence(timeout: 10))
        sender.tap(); sender.typeText(number)
        let action = block ? "Block" : "Allow"
        if app.buttons["rule.action." + action.lowercased()].exists {
            app.buttons["rule.action." + action.lowercased()].tap()
        } else { app.segmentedControls["rule.action"].buttons[action].tap() }
        app.buttons["rule.save"].tap()
        XCTAssertTrue(app.buttons["rule.save"].waitForNonExistence(timeout: 60))
    }

    private func removeCallerRule(_ app: XCUIApplication, row: XCUIElement) {
        app.tabBars.buttons["Lookup"].tap()
        if row.waitForExistence(timeout: 5) {
            row.swipeLeft()
            let remove = app.buttons["Remove"]
            XCTAssertTrue(remove.waitForExistence(timeout: 5))
            if remove.exists { remove.tap() }
            XCTAssertTrue(row.waitForNonExistence(timeout: 60))
        }
    }

    /// Agent coordinates one owned caller after this test announces readiness.
    /// Attachments remain private; neither caller nor destination is embedded here.
    func testObserveControlledIncomingCall() throws {
        guard ProcessInfo.processInfo.environment["SPAMHOLE_CONTROLLED_CALL_OBSERVATION"] == "1" else {
            throw XCTSkip("Controlled incoming calls require explicit device-test opt-in")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Protection"].waitForExistence(timeout: 20))
        app.tabBars.buttons["Protection"].tap()
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["protection.refresh"])
        waitForExpectations(timeout: 60)
        XCTAssertTrue(app.staticTexts["Call Directory, Enabled"].exists)
        let receipt = XCTAttachment(string: app.debugDescription)
        receipt.name = "Private pre-call receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCUIDevice.shared.press(.home)
        let system = XCUIApplication(bundleIdentifier: "com.apple.InCallService")
        print("CONTROLLED_CALL_OBSERVER_READY")
        let incoming = system.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Accept", "Answer")).firstMatch
        let observed = incoming.waitForExistence(timeout: 90)
        let observation = XCTAttachment(string: system.debugDescription)
        observation.name = "Private recipient incoming-call hierarchy"
        observation.lifetime = .keepAlways
        add(observation)
        let screen = XCTAttachment(screenshot: system.screenshot())
        screen.name = "Private recipient incoming-call screen"
        screen.lifetime = .keepAlways
        add(screen)
        XCTAssertTrue(observed, "Observe recipient call controls; caller ringing is insufficient")
        XCTAssertTrue(incoming.waitForNonExistence(timeout: 60), "Agent must hang up the controlled caller")
        app.activate()
    }

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
    func testReleaseSavedLaunchMeasurements() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        try waitForManualBaseline(app)
        app.terminate()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
            app.launch()
            XCTAssertTrue(app.tabBars.buttons["Protection"].waitForExistence(timeout: 15))
            app.terminate()
        }
    }

    /// Preserve the running Release process for native Instruments attachment.
    func testReleaseExistingProcessInteractions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.activate()
        try waitForManualBaseline(app)
        for _ in 0..<20 { try interactionCycle(app) }
    }

    /// Requires Manual cadence prepared separately; changes no rules or permissions.
    func testReleaseInteractionWorkload() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        for _ in 0..<3 {
            app.terminate()
            app.launch()
            try waitForManualBaseline(app)
            try interactionCycle(app)
        }
        for _ in 0..<20 { try interactionCycle(app) }
    }

    func testReleaseWarmActivations() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        try waitForManualBaseline(app)
        for _ in 0..<3 {
            XCUIDevice.shared.press(.home)
            app.activate()
            try waitForManualBaseline(app)
            try interactionCycle(app)
        }
    }

    private func waitForManualBaseline(_ app: XCUIApplication) throws {
        XCTAssertTrue(app.tabBars.buttons["Protection"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Protection"].tap()
        guard app.staticTexts["Requested cadence, Manual"].waitForExistence(timeout: 10) else {
            throw XCTSkip("Prepare Manual cadence before profiling normal data")
        }
        let refresh = app.buttons["protection.refresh"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: refresh)
        waitForExpectations(timeout: 60)
    }

    private func interactionCycle(_ app: XCUIApplication) throws {
        app.tabBars.buttons["Lookup"].tap()
        let sender = app.textFields["lookup.sender"]
        XCTAssertTrue(sender.waitForExistence(timeout: 10))
        sender.tap()
        if let value = sender.value as? String, !value.isEmpty, value != sender.placeholderValue {
            sender.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        }
        sender.typeText("2025550123")
        app.buttons["lookup.search"].tap()
        XCTAssertTrue(app.staticTexts["lookup.canonicalSender"].waitForExistence(timeout: 10))
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        list.swipeUp()
        list.swipeDown()
        let addRule = app.buttons["rule.add"]
        expectation(for: NSPredicate(format: "hittable == true AND enabled == true"), evaluatedWith: addRule)
        waitForExpectations(timeout: 10)
        addRule.tap()
        XCTAssertTrue(app.textFields["rule.sender"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["rule.add"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Protection"].tap()
    }

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
