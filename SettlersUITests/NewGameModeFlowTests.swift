import XCTest

/// Choosing a mode changes the shape of the match-length control, so the
/// interaction is covered end to end rather than only through model tests.
@MainActor
final class NewGameModeFlowTests: XCTestCase {
    func testPickingExpandedShowsAFixedTwentyFivePointTarget() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()

        let modeRow = app.buttons["new-game.mode"]
        XCTAssertTrue(modeRow.waitForExistence(timeout: 10))
        modeRow.tap()

        let expanded = app.buttons["new-game.mode.expanded"]
        XCTAssertTrue(expanded.waitForExistence(timeout: 5), "The mode picker never appeared")
        expanded.tap()

        let fixed = app.staticTexts["new-game.match-length.fixed"]
        XCTAssertTrue(fixed.waitForExistence(timeout: 5),
                      "Expanded did not replace the match-length chips with a fixed target")
        XCTAssertEqual(fixed.label, "25 VP")
        XCTAssertTrue(app.buttons["new-game.start"].isEnabled,
                      "Switching mode left Start disabled: the target did not snap into range")
    }
}
