import XCTest

/// Deploying is tap-a-hex: from Build, Deploy Army; tap a highlighted hex; pick
/// the 2 in the dock; the preview names the outcome; Commit lands it.
@MainActor
final class ConquestFlowTests: XCTestCase {
    func testDeployingByTappingAHex() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowConquest"]
        app.launch()
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 10))
        app.buttons["Build"].tap()
        app.buttons["build.deploy-army"].tap()
        let hex = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile.")).firstMatch
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        let two = app.buttons["army.card.0"]
        XCTAssertTrue(two.waitForExistence(timeout: 5))
        two.tap()
        XCTAssertNotEqual(app.staticTexts["army.preview"].label, "Choose army cards")
        let commit = app.buttons["board-decision.confirm"]
        XCTAssertTrue(commit.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "conquest-deploy-dock"
        shot.lifetime = .keepAlways
        add(shot)
        commit.tap()
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 5), "the dock gave way to the action row")
    }
}
