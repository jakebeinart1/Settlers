import XCTest

/// Starts before the actual dice transaction; directly seeding a discard
/// would miss the incorrect Naval threshold reported by the player.
@MainActor
final class NavalSevenDiscardFlowTests: XCTestCase {
    func testRolledSevenRequiresFourDiscardsAndColdResumeCannotBypassThem() {
        let app = launch()
        let before = committedQuantities(in: app)
        XCTAssertTrue(before.contains("resources=8;human=1;threshold=7"))
        retainScreenshot("Naval seven — eight resources and Knight before the roll", app: app)
        app.buttons["Roll Dice"].tap()
        assertDiscardIsRequired(in: app)
        retainScreenshot("Naval seven — actual roll opens the four-card discard", app: app)
        app.buttons["discard.hand.lumber"].tap()
        app.buttons["discard.minimize"].tap()
        XCTAssertTrue(app.buttons["discard.dock"].waitForExistence(timeout: 3))
        assertGameCommandsAreAbsent(in: app)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
        XCTAssertFalse(app.buttons["board-decision.confirm"].exists)
        XCTAssertTrue(committedQuantities(in: app).contains("resources=8;human=1;threshold=7"))
        retainScreenshot("Naval seven — board inspection preserves the uncommitted hand", app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart", "-qaNavalSevenPosition"]
        app.launch()
        assertDiscardIsRequired(in: app)
        XCTAssertTrue(app.staticTexts["0 of 4 selected"].exists)
        retainScreenshot("Naval seven — cold resume retains the actual obligation", app: app)
        selectFourAndSubmit(in: app)
        assertCompletedDiscard(before: before, in: app)
        retainScreenshot("Naval seven — four cards returned to the bank before robber movement", app: app)
    }

    func testMaximumTextKeepsRealNavalDiscardSubmissionReachable() {
        let app = launch(maximumText: true)
        let before = committedQuantities(in: app)
        app.buttons["Roll Dice"].tap()
        assertDiscardIsRequired(in: app)
        let submit = app.buttons["discard.submit"]
        XCTAssertTrue(submit.exists && submit.isHittable)
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(app.buttons["discard.minimize"].isHittable)
        retainScreenshot("Naval seven — maximum-text mandatory discard actions", app: app)
        selectFourAndSubmit(in: app)
        assertCompletedDiscard(before: before, in: app)
        retainScreenshot("Naval seven — maximum-text actual discard and robber continuation", app: app)
    }

    private func launch(maximumText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalSevenPosition", "-qaHumanSeatTwo"]
        if maximumText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["Roll Dice"].waitForExistence(timeout: 10))
        return app
    }

    private func assertDiscardIsRequired(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["discard.editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 4 selected"].exists)
        XCTAssertFalse(app.buttons["discard.submit"].isEnabled)
        assertGameCommandsAreAbsent(in: app)
    }

    private func selectFourAndSubmit(in app: XCUIApplication) {
        let lumber = app.buttons["discard.hand.lumber"]
        for _ in 0..<4 {
            if !lumber.isHittable { app.swipeUp() }
            XCTAssertTrue(lumber.isEnabled && lumber.isHittable)
            lumber.tap()
        }
        XCTAssertTrue(app.staticTexts["4 of 4 selected"].exists)
        let submit = app.buttons["discard.submit"]
        XCTAssertTrue(submit.isEnabled && submit.isHittable)
        submit.tap()
    }

    private func assertCompletedDiscard(before: String, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["discard.editor"].waitForNonExistence(timeout: 3))
        let after = committedQuantities(in: app)
        XCTAssertTrue(after.contains("resources=4;human=1;threshold=7;phase=movingRobber"))
        XCTAssertEqual(bankCount(in: after), bankCount(in: before) + 4)
        let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", "board.tile.")).firstMatch
        XCTAssertTrue(target.exists, "The original roller must get the robber decision after every discard")
        XCTAssertEqual(app.otherElements["human-resource.lumber"].value as? String, "0")
        XCTAssertEqual(app.otherElements["human-resource.brick"].value as? String, "1")
        XCTAssertEqual(app.otherElements["human-resource.ore"].value as? String, "1")
        XCTAssertEqual(app.otherElements["human-resource.wool"].value as? String, "2")
    }

    private func assertGameCommandsAreAbsent(in app: XCUIApplication) {
        for title in ["Roll Dice", "Trade", "Build", "End Turn"] {
            XCTAssertFalse(app.buttons[title].exists, "\(title) must wait for the mandatory discard")
        }
        XCTAssertFalse(app.buttons["dev-cards.shelf"].exists)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
        for prefix in ["board.vertex.", "board.edge.", "board.tile."] {
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).count, 0)
        }
    }

    private func committedQuantities(in app: XCUIApplication) -> String {
        let marker = app.otherElements["qa.naval-seven.state"]
        XCTAssertTrue(marker.waitForExistence(timeout: 3))
        guard let value = marker.value as? String else {
            XCTFail("The committed-state leaf must expose real quantities")
            return ""
        }
        return value
    }

    private func bankCount(in value: String) -> Int {
        let field = value.split(separator: ";").first { $0.hasPrefix("bank=") }
        guard let field, let count = Int(field.dropFirst("bank=".count)) else {
            XCTFail("No committed bank count in \(value)")
            return 0
        }
        return count
    }

    private func retainScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
