import XCTest

/// Exercises presentation settings through the same controls a player uses.
@MainActor
final class InGameSettingsFlowTests: XCTestCase {
    func testPacingChangesPersistAfterClosingTheScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart"]
        app.launch()

        let settingsButton = app.buttons["game.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        XCTAssertTrue(app.otherElements["screen.in-game-settings"].waitForExistence(timeout: 2))

        app.buttons["Fast"].tap()
        app.buttons["No Limit"].tap()
        XCTAssertTrue(app.buttons["Fast"].isSelected)
        XCTAssertTrue(app.buttons["No Limit"].isSelected)

        app.buttons["in-game-settings.close"].tap()
        XCTAssertFalse(app.otherElements["screen.in-game-settings"].exists)
        settingsButton.tap()
        XCTAssertTrue(app.buttons["Fast"].isSelected)
        XCTAssertTrue(app.buttons["No Limit"].isSelected)
    }

    /// Auto Robber sits below the fold, under the two Skipping switches.
    func testAutoRobberIsReachableAndPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowPauseMenu"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.in-game-settings"].waitForExistence(timeout: 5))

        let on = app.buttons["in-game-settings.auto-robber.on"]
        app.swipeUp()
        XCTAssertTrue(on.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["in-game-settings.auto-robber.off"].isSelected, "off by default")
        on.tap()
        XCTAssertTrue(on.isSelected)
        add(XCTAttachment(screenshot: app.screenshot()))

        app.buttons["in-game-settings.close"].tap()
        app.buttons["game.settings"].tap()
        app.swipeUp()
        XCTAssertTrue(on.waitForExistence(timeout: 2))
        XCTAssertTrue(on.isSelected)
    }

    /// The pause screen used to offer Close and "Resume Game" side by side and
    /// then repeat all three exits as a "Game Control" section above them. One
    /// row of three, one meaning each.
    func testTheOnlyWaysOutAreCloseRestartAndQuit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowPauseMenu"]
        app.launch()

        XCTAssertTrue(app.otherElements["screen.in-game-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["in-game-settings.close"].exists)
        XCTAssertTrue(app.buttons["in-game-settings.restart"].exists)
        XCTAssertTrue(app.buttons["in-game-settings.quit"].exists)
        XCTAssertFalse(app.buttons["Resume Game"].exists)
        XCTAssertFalse(app.staticTexts["Game Control"].exists)

        app.buttons["in-game-settings.restart"].tap()
        XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: 2))
        app.buttons["Cancel"].tap()

        app.buttons["in-game-settings.close"].tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 3))
    }
}
