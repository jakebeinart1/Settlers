import XCTest

/// The mode is the only match-contract dial left on the New Game screen, and it
/// sets the victory-point target, so the interaction is covered end to end
/// rather than only through model tests.
@MainActor
final class NewGameModeFlowTests: XCTestCase {

    /// The mode row is a chip row rather than a popup as of 2026-09-16, so this
    /// taps the chip directly. Match length is no longer a control at all - the
    /// mode sets the target - so what this asserts is that picking a mode still
    /// leaves a startable match rather than stranding an out-of-range target.
    func testPickingVastLeavesTheMatchStartable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()

        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 10))

        let vast = app.buttons["Vast"]
        XCTAssertTrue(vast.waitForExistence(timeout: 5), "The Vast chip is not on the mode row")
        vast.tap()

        XCTAssertTrue(app.buttons["new-game.start"].isEnabled,
                      "Switching mode left Start disabled: the target did not snap into range")
    }

    /// Expanded is retired from the New Game screen but still decodable, so an
    /// in-progress save resumes. It must not be offerable again.
    func testExpandedIsNoLongerOffered() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()

        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Expanded"].exists,
                       "Expanded is still startable; its 25-point target is unreachable on its board")
    }
}
