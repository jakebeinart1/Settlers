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

    /// A real Conquest game, not a fixture: setup and the first roll are played
    /// by `-qaFastForwardToRollDice`, then the human deploys the dealt army card
    /// through Build, the board and the dock, ends the turn, and control comes
    /// back after a full bot round.
    func testDeployingTheDealtCardInARealClassicGame() {
        playADeployTurn(extra: [])
    }

    func testDeployingTheDealtCardInARealVastGame() {
        playADeployTurn(extra: ["-qaVastMode"])
    }

    private func playADeployTurn(extra: [String]) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaConquestMode",
                               "-qaFastForwardToRollDice"] + extra
        app.launch()
        let build = app.buttons["Build"]
        XCTAssertTrue(build.waitForExistence(timeout: 30))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: build)
        waitForExpectations(timeout: 60)
        build.tap()
        let deploy = app.buttons["build.deploy-army"]
        XCTAssertTrue(deploy.waitForExistence(timeout: 5))
        XCTAssertTrue(deploy.isEnabled, "the dealt army card must be deployable on turn one")
        deploy.tap()
        let hex = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile.")).firstMatch
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.tap()
        app.buttons["army.card.0"].tap()
        let preview = app.staticTexts["army.preview"].label
        XCTAssertFalse(preview.isEmpty || preview == "Choose army cards")
        app.buttons["board-decision.confirm"].tap()
        attach(app, "conquest-real-\(extra.isEmpty ? "classic" : "vast")-after-deploy (\(preview))")
        let endTurn = app.buttons["End Turn"]
        XCTAssertTrue(endTurn.waitForExistence(timeout: 5))
        endTurn.tap()
        let roll = app.buttons["Roll Dice"]
        XCTAssertTrue(roll.waitForExistence(timeout: 240), "control never came back after the bot round")
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: roll)
        waitForExpectations(timeout: 240)
        attach(app, "conquest-real-\(extra.isEmpty ? "classic" : "vast")-after-bot-round")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
