import XCTest

@MainActor
final class SpamHoleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingAndAllTabsAreAccessible() {
        let app = launchApp()
        completeOnboarding(in: app)

        for title in ["Protection", "Sources", "Lookup", "Settings"] {
            let tab = app.tabBars.buttons[title]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing tab: \(title)")
            tab.tap()
        }
        app.tabBars.buttons["Lookup"].tap()
        XCTAssertTrue(app.textFields["lookup.sender"].waitForExistence(timeout: 5))
    }

    func testPersonalRuleCanBeSavedAndFoundOffline() {
        let app = launchApp()
        completeOnboarding(in: app)
        app.tabBars.buttons["Lookup"].tap()
        app.buttons["rule.add"].tap()

        let sender = app.textFields["rule.sender"]
        XCTAssertTrue(sender.waitForExistence(timeout: 5))
        sender.tap()
        sender.typeText("2025550123")
        app.buttons["rule.save"].tap()

        let lookup = app.textFields["lookup.sender"]
        XCTAssertTrue(lookup.waitForExistence(timeout: 5))
        lookup.tap()
        lookup.typeText("2025550123")
        app.buttons["lookup.search"].tap()
        let canonical = app.staticTexts["lookup.canonicalSender"]
        XCTAssertTrue(canonical.waitForExistence(timeout: 5))
        XCTAssertEqual(canonical.label, "+12025550123")
        let decision = app.descendants(matching: .any)["lookup.callRule"]
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        XCTAssertTrue(decision.label.contains("Allow"), "The saved call allow rule must appear in the local lookup")
    }

    func testPersonalCallBlockRuleCanBeSavedAndFoundOffline() {
        let app = launchApp()
        completeOnboarding(in: app)
        app.tabBars.buttons["Lookup"].tap()
        app.buttons["rule.add"].tap()

        let sender = app.textFields["rule.sender"]
        XCTAssertTrue(sender.waitForExistence(timeout: 5))
        sender.tap()
        sender.typeText("2025550123")
        if app.buttons["rule.action.block"].exists {
            app.buttons["rule.action.block"].tap()
        } else {
            app.segmentedControls["rule.action"].buttons["Block"].tap()
        }
        app.buttons["rule.save"].tap()

        let lookup = app.textFields["lookup.sender"]
        XCTAssertTrue(lookup.waitForExistence(timeout: 5))
        lookup.tap()
        lookup.typeText("2025550123")
        app.buttons["lookup.search"].tap()
        let decision = app.descendants(matching: .any)["lookup.callRule"]
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        XCTAssertTrue(decision.label.contains("Block"), "The saved call block rule must appear in the local lookup")
    }

    func testRemediatedActionsLight() throws {
        try reviewActions(style: "Light", category: "UICTContentSizeCategoryL")
    }

    func testRemediatedActionsDark() throws {
        try reviewActions(style: "Dark", category: "UICTContentSizeCategoryL")
    }

    func testLargestTextChoicesLight() throws {
        try reviewLargestChoices(style: "Light")
    }

    func testLargestTextChoicesDark() throws {
        try reviewLargestChoices(style: "Dark")
    }

    func testFollowupLargestFormsLight() throws { try reviewLargestForms(style: "Light") }
    func testFollowupLargestFormsDark() throws { try reviewLargestForms(style: "Dark") }

    private func reviewLargestForms(style: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--ui-testing-" + style.lowercased()]
        app.launch()
        completeOnboarding(in: app)
        app.tabBars.buttons["Sources"].tap(); app.buttons["source.add"].tap()
        XCTAssertEqual(app.textFields["source.name"].label, "Publisher name")
        XCTAssertEqual(app.textFields["source.url"].label, "HTTPS feed URL")
        capture(app, "followup-source-largest-\(style)")
        let json = app.buttons["source.format.json"]
        scrollIntoView(json, in: app)
        XCTAssertTrue(json.isHittable)
        json.tap()
        XCTAssertTrue(json.isSelected)
        let csv = app.buttons["source.format.csv"]
        scrollIntoView(csv, in: app); csv.tap()
        XCTAssertTrue(csv.isSelected)
        capture(app, "followup-source-choices-\(style)")
        try audit(app, "FollowupSource-\(style)")
        app.buttons["Cancel"].tap()
        app.terminate(); app.launch()
        completeOnboarding(in: app)
        app.tabBars.buttons["Lookup"].tap()
        let input = app.textFields["lookup.sender"]
        scrollIntoView(input, in: app); input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        waitForHittable(input); input.tap()
        input.typeText("2025550123")
        XCTAssertEqual(input.value as? String, "2025550123")
        app.swipeUp()
        let search = app.buttons["lookup.search"]
        scrollIntoView(search, in: app); search.tap()
        XCTAssertTrue(app.staticTexts["lookup.canonicalSender"].waitForExistence(timeout: 5))
        let correction = app.buttons["Correct This Listing"]
        scrollIntoView(correction, in: app); correction.tap()
        XCTAssertTrue(app.navigationBars["Correct Listing"].waitForExistence(timeout: 5))
        let reason = app.buttons["correction.reason.4"]
        scrollIntoView(reason, in: app); reason.tap()
        XCTAssertTrue(reason.isSelected)
        capture(app, "followup-correction-largest-\(style)")
        try audit(app, "FollowupCorrection-\(style)")
        app.buttons["Cancel"].tap()
    }

    private func reviewActions(style: String, category: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", category, "--ui-testing-" + style.lowercased()]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["onboarding.continue"].isHittable, "Continue must be visible without scrolling")
        capture(app, "remediation-onboarding-\(style)")
        try audit(app, "Onboarding-\(style)")
        app.buttons["onboarding.continue"].tap()
        app.tabBars.buttons["Sources"].tap()
        app.buttons["source.add"].tap()
        capture(app, "remediation-add-source-\(style)")
        try audit(app, "AddSource-\(style)")
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Lookup"].tap()
        try audit(app, "Lookup-\(style)")
        capture(app, "remediation-lookup-\(style)")
        app.buttons["rule.add"].tap()
        app.textFields["rule.sender"].tap()
        app.textFields["rule.sender"].typeText("2025550123")
        // Dismiss the keyboard through its submit key before checking controls.
        app.buttons["rule.save"].tap()
        let input = app.textFields["lookup.sender"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        waitForHittable(input)
        input.tap(); input.typeText("2025550123\n")
        XCTAssertTrue(app.staticTexts["lookup.canonicalSender"].waitForExistence(timeout: 5))
        let correct = app.buttons["Correct This Listing"]
        for _ in 0..<6 where !correct.isHittable { app.swipeUp() }
        correct.tap()
        XCTAssertTrue(app.navigationBars["Correct Listing"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Save"].isHittable)
        capture(app, "remediation-correction-\(style)")
        try audit(app, "Correction-\(style)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.textFields["lookup.sender"].waitForExistence(timeout: 5))
    }

    private func reviewLargestChoices(style: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "--ui-testing-" + style.lowercased()]
        app.launch()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10)); XCTAssertTrue(next.isHittable)
        capture(app, "remediation-onboarding-largest-\(style)")
        next.tap()
        app.tabBars.buttons["Lookup"].tap(); app.buttons["rule.add"].tap()
        let sender = app.textFields["rule.sender"]
        XCTAssertTrue(sender.waitForExistence(timeout: 5))
        capture(app, "remediation-rule-largest-top-\(style)")
        // Call decisions remain body-size rows at accessibility sizes.
        let block = app.buttons["rule.action.block"]
        scrollIntoView(block, in: app)
        XCTAssertTrue(block.isHittable); block.tap()
        capture(app, "remediation-rule-largest-decisions-\(style)")
        // Capture the scaled choices before the audit temporarily changes font settings.
        scrollIntoView(sender, in: app, startGoingUp: false)
        sender.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        waitForHittable(sender)
        sender.tap() // Reacquire the field after the keyboard changes the form viewport.
        sender.typeText("2025550123")
        app.swipeUp() // The form dismisses the keyboard immediately when scrolling.
        app.buttons["rule.save"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["Personal Rule"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        let lookup = app.textFields["lookup.sender"]
        XCTAssertTrue(lookup.waitForExistence(timeout: 5))
        scrollIntoView(lookup, in: app)
        waitForHittable(lookup)
        lookup.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        lookup.typeText("2025550123")
        app.swipeUp()
        let search = app.buttons["lookup.search"]
        scrollIntoView(search, in: app)
        search.tap()
        let decision = app.descendants(matching: .any)["lookup.callRule"]
        for _ in 0..<8 where !decision.isHittable { app.swipeUp() }
        XCTAssertTrue(decision.exists); XCTAssertTrue(decision.label.contains("Block"))
        app.buttons["rule.add"].tap()
        XCTAssertTrue(app.textFields["rule.sender"].waitForExistence(timeout: 5))
        try audit(app, "LargestRule-\(style)")
    }

    private func waitForHittable(_ element: XCUIElement) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
    }

    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication, startGoingUp: Bool = true) {
        for _ in 0..<20 where !element.isHittable {
            let goingUp = element.exists && element.frame != .zero
                ? element.frame.minY > 100 : startGoingUp
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: goingUp ? 0.72 : 0.45))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: goingUp ? 0.45 : 0.72))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    private func audit(_ app: XCUIApplication, _ screen: String) throws {
        var issues: [String] = []
        try app.performAccessibilityAudit { issue in
            let entry = "\(screen): \(issue.auditType.rawValue): \(issue.compactDescription) | \(issue.detailedDescription) | \(issue.element?.label ?? "no element")"
            issues.append(entry); print("REMEDIATION_AUDIT: \(entry)")
            return true // Keep every issue for attribution; do not claim a blanket accessibility pass.
        }
        let attachment = XCTAttachment(string: issues.isEmpty ? "No issues reported on \(screen)" : issues.joined(separator: "\n"))
        attachment.name = "Accessibility-\(screen)"; attachment.lifetime = .keepAlways; add(attachment)
        let failedActions = issues.filter {
            $0.contains("Contrast") && ["| Look Up", "| Continue"].contains(where: $0.hasSuffix)
        }
        XCTAssertTrue(failedActions.isEmpty, failedActions.joined(separator: "\n"))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    private func completeOnboarding(in app: XCUIApplication) {
        let button = app.buttons["onboarding.continue"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        for _ in 0..<6 where !button.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable, "Continue must be reachable by scrolling onboarding")
        button.tap()
    }
}
