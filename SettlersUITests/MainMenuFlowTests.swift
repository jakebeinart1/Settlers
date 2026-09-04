import XCTest

/// Tracer flow for the public UI seam: a player can move from launch into the
/// match contract and back without relying on visible copy or pixel positions.
@MainActor
final class MainMenuFlowTests: XCTestCase {
    func testNewGameOpensAndCancels() {
        continueAfterFailure = false
        let app = launchResetApp()
        let mainMenu = app.otherElements["screen.main-menu"]
        XCTAssertTrue(mainMenu.waitForExistence(timeout: 5))

        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))

        app.buttons["new-game.cancel"].tap()
        XCTAssertTrue(mainMenu.waitForExistence(timeout: 2))
    }

    func testConfiguredMatchStarts() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        app.buttons["3 Players"].tap()
        app.buttons["8 VP"].tap()
        app.buttons["Randomized"].tap()
        app.buttons["Random"].tap()
        app.buttons["new-game.start"].tap()

        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))
    }

    func testEpicLengthIsOnlyOfferedAtAThreePlayerTable() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["12 VP"].exists)

        app.buttons["3 Players"].tap()
        XCTAssertTrue(app.buttons["12 VP"].waitForExistence(timeout: 2))
        app.buttons["12 VP"].tap()

        app.buttons["4 Players"].tap()
        XCTAssertFalse(app.buttons["12 VP"].exists)
        XCTAssertTrue(app.buttons["new-game.start"].isEnabled,
                      "growing the table must normalize Epic to a playable length")
    }

    func testOpeningSettlementRequiresAnAdjacentRoad() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        app.buttons["3 Players"].tap()
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()

        let legalVertex = enabledButton(in: app, prefix: "board.vertex.")
        XCTAssertTrue(legalVertex.waitForExistence(timeout: 5))
        legalVertex.tap()

        let legalEdge = enabledButton(in: app, prefix: "board.edge.")
        XCTAssertTrue(legalEdge.waitForExistence(timeout: 2))
        legalEdge.tap()
        XCTAssertFalse(enabledButton(in: app, prefix: "board.edge.").waitForExistence(timeout: 2))
    }

    func testColdLaunchResumesTheConfiguredMatch() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        app.buttons["3 Players"].tap()
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let resume = app.buttons["main-menu.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))
    }

    private func launchResetApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        return app
    }

    private func enabledButton(in app: XCUIApplication, prefix: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
            .firstMatch
    }
}
