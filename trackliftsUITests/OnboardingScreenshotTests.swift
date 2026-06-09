//
//  OnboardingScreenshotTests.swift
//  trackliftsUITests
//
//  Walks the first-run onboarding flow and saves a screenshot of every step
//  (incl. the keyboard-up states) so layout/cropping can be verified.
//

import XCTest

final class OnboardingScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor
    func testOnboardingScreens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--show-onboarding"]
        app.launch()

        // 1 — Welcome
        let build = app.buttons["BUILD MY PLAN"]
        XCTAssertTrue(build.waitForExistence(timeout: 15), "welcome step should appear")
        shot(app, "01-welcome")
        build.tap()

        // 2 — Goal (pick the new Lean bulk option)
        let goalCard = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Lean bulk'")).firstMatch
        XCTAssertTrue(goalCard.waitForExistence(timeout: 5), "goal step should appear")
        shot(app, "02-goal")
        goalCard.tap()
        tapContinue(app)

        // 3 — About (+ keyboard over the weight field)
        let weightField = app.textFields.firstMatch
        XCTAssertTrue(weightField.waitForExistence(timeout: 5), "about step should appear")
        shot(app, "03-about")
        weightField.tap()
        _ = app.keyboards.element.waitForExistence(timeout: 3)
        shot(app, "04-about-keyboard")
        tapContinue(app)

        // 4 — Activity
        let activityCard = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Moderately'")).firstMatch
        XCTAssertTrue(activityCard.waitForExistence(timeout: 5), "activity step should appear")
        shot(app, "05-activity")
        activityCard.tap()
        tapContinue(app)

        // 5 — Target & pace
        let goalWeight = app.textFields.firstMatch
        XCTAssertTrue(goalWeight.waitForExistence(timeout: 5), "target step should appear")
        shot(app, "06-target")

        // 6 — Custom pace control
        let customCard = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Custom'")).firstMatch
        if customCard.waitForExistence(timeout: 3) {
            customCard.tap()
            shot(app, "07-target-custom")
        }

        // 7 — Keyboard over the goal-weight field
        goalWeight.tap()
        _ = app.keyboards.element.waitForExistence(timeout: 3)
        shot(app, "08-target-keyboard")
        tapContinue(app)

        // 8 — Plan
        XCTAssertTrue(app.buttons["START TRACKING"].waitForExistence(timeout: 5), "plan step should appear")
        shot(app, "09-plan")
    }

    @MainActor private func tapContinue(_ app: XCUIApplication) {
        let c = app.buttons["CONTINUE"]
        if c.waitForExistence(timeout: 5) { c.tap() }
    }

    @MainActor private func shot(_ app: XCUIApplication, _ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
