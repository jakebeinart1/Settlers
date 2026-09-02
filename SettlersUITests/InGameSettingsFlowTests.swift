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
}
