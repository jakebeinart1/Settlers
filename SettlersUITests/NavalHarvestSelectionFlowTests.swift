import XCTest

/// Real quantity taps keep the hand unchanged, expose completion in both
/// locations, permit editing, and collect the whole obligation with one tap.
@MainActor
final class NavalHarvestSelectionFlowTests: XCTestCase {
    func testCityHarvestDraftResetsOnColdResumeAndBothChoicesCollectOnce() {
        let app = launch("-qaNavalCityResourcePosition")
        let ore = app.buttons["naval.resource.ore"]
        XCTAssertEqual(app.staticTexts["naval.resource.source"].label, "City harvest")
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 2 resources"))
        XCTAssertEqual(app.descendants(matching: .any)["naval.resource.progress"].value as? String, "0 of 2 selected. 2 remaining.")
        retain("Voyages — city chooses two resources with clear progress", app: app)
        let before = resource("ore", in: app)
        let grainBefore = resource("grain", in: app)
        ore.tap()
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].exists)
        XCTAssertEqual(resource("ore", in: app), before)
        XCTAssertEqual(app.descendants(matching: .any)["naval.resource.progress"].value as? String, "1 of 2 selected. 1 remaining.")
        XCTAssertEqual(app.buttons["naval.resource.confirm"].value as? String, "1 of 2 selected")
        XCTAssertFalse(app.buttons["naval.resource.confirm"].isEnabled, "Every card must be selected before one confirmation")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(ore.waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), before)
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 2 resources"))
        XCTAssertEqual(app.descendants(matching: .any)["naval.resource.progress"].value as? String, "0 of 2 selected. 2 remaining.")
        retain("Voyages — uncommitted city harvest resets after cold resume", app: app)
        XCTAssertFalse(app.buttons["naval.resource.confirm"].isEnabled)
        ore.tap()
        app.buttons["naval.resource.grain"].tap()
        XCTAssertEqual(app.buttons["naval.resource.confirm"].value as? String, "2 of 2 selected")
        retain("Voyages — complete city choice before one collection", app: app)
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), before + 1)
        XCTAssertEqual(resource("grain", in: app), grainBefore + 1)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), before + 1)
        XCTAssertEqual(resource("grain", in: app), grainBefore + 1)
    }

    func testMixedHarvestCountsEveryPickAndAllowsEditingAtFullAllocation() {
        let app = launch()
        let confirm = app.buttons["naval.resource.confirm"]
        let before = holdings(app)
        XCTAssertEqual(app.staticTexts["naval.resource.source"].label, "1 settlement + 1 city")
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 3 resources"))
        assertProgress(0, required: 3, app: app)
        retain("Harvest — mixed buildings before selection", app: app)
        app.buttons["naval.resource.ore"].tap()
        assertProgress(1, required: 3, app: app)
        retain("Harvest — one of three selected", app: app)
        app.buttons["naval.resource.ore"].tap()
        assertProgress(2, required: 3, app: app)
        retain("Harvest — two identical resources selected", app: app)
        app.buttons["naval.resource.grain"].tap()
        assertProgress(3, required: 3, app: app)
        XCTAssertEqual(holdings(app), before)
        XCTAssertFalse(app.buttons["naval.resource.ore"].isEnabled)
        let remove = app.buttons["naval.resource.remove.ore"]
        XCTAssertTrue(remove.isEnabled && remove.isHittable)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.width, 44)
        retain("Harvest — complete three-card choice", app: app)
        remove.tap()
        assertProgress(2, required: 3, app: app)
        app.buttons["naval.resource.lumber"].tap()
        assertProgress(3, required: 3, app: app)
        XCTAssertEqual(holdings(app), before)
        confirm.tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        let after = holdings(app)
        XCTAssertEqual(after, before.enumerated().map { index, count in count + ([1, 2, 3].contains(index) ? 1 : 0) })
        retain("Harvest — one collection credits all three resources", app: app)
        coldResume(app)
        XCTAssertEqual(holdings(app), after)
        XCTAssertFalse(app.buttons["naval.resource.confirm"].exists)
    }

    func testBankShortageAllowsOnlyStockedQuantitiesAndExplainsReducedCollection() {
        let app = launch(extra: ["-qaNavalHarvestBankScarce"])
        XCTAssertTrue(app.staticTexts["naval.resource.bank-shortage"].exists)
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 2 resources"))
        assertProgress(0, required: 2, app: app)
        XCTAssertFalse(app.buttons["naval.resource.brick"].isEnabled)
        app.buttons["naval.resource.ore"].tap()
        XCTAssertFalse(app.buttons["naval.resource.ore"].isEnabled, "The only Ore is already reserved")
        assertProgress(1, required: 2, app: app)
        app.buttons["naval.resource.grain"].tap()
        assertProgress(2, required: 2, app: app)
        retain("Harvest — scarce bank explains two available cards", app: app)
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5), "Empty supply cannot leave a mandatory harvest blocked")
    }

    func testPreviouslyCollectedUnitSurvivesColdResumeWithoutBeingCollectedAgain() {
        let app = launch(extra: ["-qaNavalHarvestPartial"])
        XCTAssertEqual(app.staticTexts["naval.resource.previous-collection"].label, "1 of 3 already collected")
        let before = holdings(app)
        assertProgress(0, required: 2, app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["naval.resource.previous-collection"].label, "1 of 3 already collected")
        XCTAssertEqual(holdings(app), before)
        app.buttons["naval.resource.ore"].tap()
        app.buttons["naval.resource.ore"].tap()
        assertProgress(2, required: 2, app: app)
        retain("Harvest — a legacy partial collection keeps its credited card", app: app)
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(holdings(app)[2], before[2] + 2)
    }

    func testMaximumTextKeepsProgressEditingAndConfirmationReachable() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let confirm = app.buttons["naval.resource.confirm"]
        XCTAssertTrue(confirm.isHittable)
        assertProgress(0, required: 3, app: app)
        for index in 1...3 {
            reveal("naval.resource.wool", app: app)
            app.buttons["naval.resource.wool"].tap()
            assertProgress(index, required: 3, app: app)
            XCTAssertTrue(confirm.isHittable, "The complete-choice action must stay pinned")
        }
        let remove = app.buttons["naval.resource.remove.wool"]
        XCTAssertTrue(remove.isEnabled && remove.isHittable)
        remove.tap()
        assertProgress(2, required: 3, app: app)
        reveal("naval.resource.ore", app: app, downward: true)
        app.buttons["naval.resource.ore"].tap()
        assertProgress(3, required: 3, app: app)
        retain("Harvest — maximum text preserves editable quantities and pinned collection", app: app)
        confirm.tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
    }

    private func launch(_ fixture: String = "-qaNavalMixedResourcePosition", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               fixture] + extra
        app.launch()
        XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 15))
        return app
    }

    private func assertProgress(_ selected: Int, required: Int, app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) {
        let progress = app.descendants(matching: .any)["naval.resource.progress"]
        XCTAssertEqual(progress.value as? String, "\(selected) of \(required) selected. \(required - selected) remaining.", file: file, line: line)
        let confirm = app.buttons["naval.resource.confirm"]
        XCTAssertEqual(confirm.value as? String, "\(selected) of \(required) selected", file: file, line: line)
        XCTAssertEqual(confirm.isEnabled, selected == required, file: file, line: line)
    }

    private func resource(_ resource: String, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) -> Int {
        NavalResourceOracle.ownedCount(resource, in: app, file: file, line: line)
    }

    private func holdings(_ app: XCUIApplication) -> [Int] {
        ["brick", "lumber", "ore", "grain", "wool"].map {
            resource($0, in: app)
        }
    }

    private func reveal(_ identifier: String, app: XCUIApplication, downward: Bool = false) {
        for _ in 0..<10 where !app.buttons[identifier].isHittable {
            let scroll = app.scrollViews["naval.resource.scroll"]
            if downward { scroll.swipeDown() } else { scroll.swipeUp() }
        }
        XCTAssertTrue(app.buttons[identifier].isHittable)
    }

    private func coldResume(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
