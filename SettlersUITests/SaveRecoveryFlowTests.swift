import XCTest

/// A corrupt save stays recoverable until the player explicitly replaces it.
/// All observations cross the public UI; no test reads the app's persistence.
@MainActor
final class SaveRecoveryFlowTests: XCTestCase {
    func testCorruptSaveSurvivesCancellationAndRelaunchUntilExplicitReplacement() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-ui-testing-corrupt-save"]
        app.launch()
        acknowledgeUnreadableSave(in: app)
        assertRecoveryMenu(in: app)

        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        app.buttons["new-game.cancel"].tap()
        assertRecoveryMenu(in: app)

        app.terminate()
        // Neither reset nor corruption seeding may run on this process boundary.
        app.launchArguments = ["-ui-testing"]
        app.launch()
        acknowledgeUnreadableSave(in: app)
        assertRecoveryMenu(in: app)

        explicitlyReplaceSave(in: app)
        placeOpeningSettlementAndRoad(in: app)
    }

    private func acknowledgeUnreadableSave(in app: XCUIApplication) {
        let alert = app.alerts["Couldn't open your saved game"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["screen.game"].exists)
        alert.buttons["OK"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2))
    }

    private func assertRecoveryMenu(in app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["main-menu.resume"].exists)
        XCTAssertFalse(app.otherElements["screen.game"].exists)
    }

    private func explicitlyReplaceSave(in app: XCUIApplication) {
        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        app.buttons["As Shown"].tap()
        let start = app.buttons["new-game.start"]
        XCTAssertTrue(start.isEnabled)
        start.tap()

        let confirm = app.buttons["new-game.confirm-overwrite"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Replace your saved game?"].exists)
        XCTAssertFalse(app.otherElements["screen.game"].exists)
        confirm.tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.exists)
    }

    private func placeOpeningSettlementAndRoad(in app: XCUIApplication) {
        let confirm = app.buttons[BoardDecisionUITestID.confirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled)

        let vertex = enabledBoardButton(in: app, prefix: "board.vertex.")
        XCTAssertTrue(vertex.waitForExistence(timeout: 5))
        vertex.tap()
        let settlementPreview = app.otherElements[BoardDecisionUITestID.buildingPreview]
        XCTAssertTrue(settlementPreview.waitForExistence(timeout: 2))
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertFalse(enabledBoardButton(in: app, prefix: "board.edge.").exists)
        confirm.tap()

        XCTAssertTrue(settlementPreview.waitForNonExistence(timeout: 2))
        let edge = enabledBoardButton(in: app, prefix: "board.edge.")
        XCTAssertTrue(edge.waitForExistence(timeout: 2))
        XCTAssertFalse(confirm.isEnabled)
        edge.tap()
        let roadPreview = app.otherElements[BoardDecisionUITestID.roadPreview]
        XCTAssertTrue(roadPreview.waitForExistence(timeout: 2))
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        XCTAssertTrue(roadPreview.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 2))
    }

    private func enabledBoardButton(in app: XCUIApplication, prefix: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
            .firstMatch
    }
}
