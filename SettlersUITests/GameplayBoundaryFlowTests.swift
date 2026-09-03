import XCTest

/// Exercises the modal boundaries most likely to make a playable game stall.
@MainActor
final class GameplayBoundaryFlowTests: XCTestCase {
    func testHotSeatHandoffCanBeAcknowledged() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaTwoHumans"])

        let ready = app.buttons["handoff.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        ready.tap()

        XCTAssertFalse(ready.waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["screen.game"].exists)
    }

    func testIncomingTradeCanBeRejected() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaShowIncomingOffer"])

        let reject = app.buttons["incoming-trade.reject"]
        XCTAssertTrue(reject.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["incoming-trade.accept"].exists)
        reject.tap()

        XCTAssertFalse(reject.waitForExistence(timeout: 2))
    }

    func testCompletedGameReturnsToMainMenuWithoutAResumeButton() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaShowEndGame"])

        let newGame = app.buttons["game-over.new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        newGame.tap()

        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["main-menu.resume"].exists)
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"] + arguments
        app.launch()
        return app
    }
}
