//
//  trackliftsUITests.swift
//  trackliftsUITests
//
//  Smoke tests that drive every screen to catch runtime crashes and confirm
//  the seeded library + logging + progress flows render.
//

import XCTest

final class trackliftsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testTabsAndLoggingFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--reset-store"]
        app.launch()

        let bench = NSPredicate(format: "label CONTAINS 'Barbell Bench Press'")

        // Log tab loaded (data-independent — other tests may have seeded the store).
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'log today'")).firstMatch.waitForExistence(timeout: 5))

        // Exercises tab — seeded library should be present.
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons.matching(bench).firstMatch.waitForExistence(timeout: 5))
        snapshot(app, name: "exercises")

        // Splits tab — create a split (seeds Push/Pull/Legs days).
        app.tabBars.buttons["Library"].tap()
        app.buttons["librarySegment.splits"].tap()
        app.buttons["addSplit"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'push'")).firstMatch.waitForExistence(timeout: 5))
        snapshot(app, name: "split-editor")

        // Progress tab.
        app.tabBars.buttons["Progress"].tap()

        // Log a workout: add an exercise.
        app.tabBars.buttons["Log"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'log today'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Add Exercise"].waitForExistence(timeout: 5))
        app.staticTexts["Add Exercise"].tap()
        let benchInPicker = app.buttons.matching(bench).firstMatch
        XCTAssertTrue(benchInPicker.waitForExistence(timeout: 5))
        benchInPicker.tap()
        app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(bench).firstMatch.waitForExistence(timeout: 5))
        snapshot(app, name: "log-workout")
    }

    @MainActor
    func testProgressEnhancementsWithSeededData() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--reset-store", "--seed-sample"]
        app.launch()

        let prPredicate = NSPredicate(format: "label CONTAINS[c] 'New PR'")
        let deltaPredicate = NSPredicate(format: "label CONTAINS 'vs last'")

        // Open the most recent session — it's the all-time best, so it should
        // show the PR badge and a positive session-over-session delta.
        app.tabBars.buttons["Log"].tap()
        // The most recent session card lists its exercises in its label.
        let topSession = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Barbell Bench Press'")).firstMatch
        XCTAssertTrue(topSession.waitForExistence(timeout: 5))
        snapshot(app, name: "log-history")
        topSession.tap()

        XCTAssertTrue(app.staticTexts.matching(prPredicate).firstMatch.waitForExistence(timeout: 5),
                      "PR badge should appear on a record-setting session")
        XCTAssertTrue(app.staticTexts.matching(deltaPredicate).firstMatch.waitForExistence(timeout: 5),
                      "Session-over-session delta should be shown")
        snapshot(app, name: "pr-and-delta")
        app.navigationBars.buttons.element(boundBy: 0).tap() // back

        // Exercises library.
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Barbell Bench Press'")).firstMatch.waitForExistence(timeout: 5))
        snapshot(app, name: "exercises-library")

        // Exercise chart + time-range picker.
        app.buttons.containing(NSPredicate(format: "label CONTAINS 'Barbell Bench Press'")).firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Range'")).firstMatch.waitForExistence(timeout: 5),
                      "Time-range selector should exist on the chart")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'change'")).firstMatch.waitForExistence(timeout: 5),
                      "Percentage 'Change' stat should be shown")
        snapshot(app, name: "exercise-chart")

        // Splits — open the seeded split to show bulk-favorite + day progress entry.
        app.tabBars.buttons["Library"].tap()
        app.buttons["librarySegment.splits"].tap()
        snapshot(app, name: "splits")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Push Pull Legs'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'favorit'")).firstMatch.waitForExistence(timeout: 5),
                      "Split editor should offer a bulk-favorite action")
        snapshot(app, name: "split-editor")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Progress — defaults to "Tracked" so progress shows with zero setup.
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'tracked'")).firstMatch.waitForExistence(timeout: 5),
                      "Progress should offer a Tracked scope (no favoriting required)")
        snapshot(app, name: "progress-overview")

        // Switch scope to the split → day-grouped progress.
        let splitChip = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Push Pull Legs'")).firstMatch
        if splitChip.waitForExistence(timeout: 3) {
            splitChip.tap()
            snapshot(app, name: "progress-split")
        }
    }

    /// Drives the new publish-readiness features: the branded Settings screen,
    /// logging a bodyweight movement, and the reorder sheet.
    @MainActor
    func testReorderAndBodyweightFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["--reset-store"]
        app.launch()

        // Settings is its own tab — brand lockup + body-weight field.
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["TRACKLIFTS"].waitForExistence(timeout: 5),
                      "Settings should show the TrackLifts brand lockup")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'body weight'")).firstMatch.exists,
                      "Settings should offer a body-weight field")
        snapshot(app, name: "settings-brand-bodyweight")

        // Log a bodyweight exercise (a sit-up).
        app.tabBars.buttons["Log"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'log today'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Add Exercise"].waitForExistence(timeout: 5))
        addExercise(app, label: "Dips (Chest)")

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'Dips (Chest)'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'BW'")).firstMatch.waitForExistence(timeout: 5),
                      "Bodyweight exercises should show a BW badge while logging")
        snapshot(app, name: "bodyweight-logging")

        // Add a second exercise so reordering becomes available.
        addExercise(app, label: "Barbell Bench Press")

        // Reorder sheet.
        let reorder = app.buttons["reorderExercises"]
        XCTAssertTrue(reorder.waitForExistence(timeout: 5),
                      "Reorder control should appear once a workout has 2+ exercises")
        reorder.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'drag the handles'")).firstMatch.waitForExistence(timeout: 5),
                      "Reorder sheet should appear")
        snapshot(app, name: "reorder-exercises")
        app.navigationBars["Reorder Exercises"].buttons["Done"].tap()
        app.navigationBars["New Workout"].buttons["Done"].tap()

        // Exercises library surfaces the BODYWEIGHT tag (non-lazy list, so the
        // tag is in the tree even if a particular row is below the fold).
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == 'BODYWEIGHT'")).firstMatch.waitForExistence(timeout: 5),
                      "Bodyweight exercises should be tagged in the library")
        snapshot(app, name: "library-bodyweight-tag")
    }

    /// Opens the exercise picker, taps the wanted row (picked to sit near the
    /// top of its section so it's hittable without scrolling — and with no
    /// keyboard up to confuse the nav-bar "Add" button), then confirms.
    @MainActor
    private func addExercise(_ app: XCUIApplication, label: String) {
        app.staticTexts["Add Exercise"].tap()
        let picker = app.navigationBars["Add Exercises"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Exercise picker should open")

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Picker should list \(label)")
        row.tap()
        picker.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Add Exercise"].waitForExistence(timeout: 5),
                      "Should return to the workout after adding \(label)")
    }

    /// Saves a full-screen screenshot as a test attachment that is always kept.
    @MainActor
    private func snapshot(_ app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
