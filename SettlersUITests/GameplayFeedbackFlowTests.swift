import XCTest

@MainActor
final class GameplayFeedbackFlowTests: XCTestCase {
    func testConfirmedLongestRoadTransferShowsBothDeltasWithoutMovingTheBoard() {
        let app = launch(["-qaLongestRoadPosition"])
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        let board = app.otherElements["board.surface"]
        let originalBoard = board.frame
        let commands = app.otherElements["game.command-row"].frame
        XCTAssertFalse(notice(in: app).exists, "preview must never claim the bonus")
        confirm.tap()
        let receipt = notice(in: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 3))
        XCTAssertTrue(receipt.label.contains("took Longest Road from"))
        XCTAssertTrue((receipt.value as? String)?.contains("+2 VP") == true)
        XCTAssertTrue((receipt.value as? String)?.contains("−2 VP") == true)
        XCTAssertEqual(app.staticTexts["gameplay.points.0"].label, "+2 victory points")
        XCTAssertEqual(app.staticTexts["gameplay.points.1"].label, "−2 victory points")
        XCTAssertEqual(board.frame, originalBoard)
        XCTAssertEqual(app.otherElements["game.command-row"].frame, commands)
        capture(app, "Longest Road transfer both scores")
        XCTAssertTrue(receipt.waitForNonExistence(timeout: 6))
        XCTAssertFalse(app.staticTexts["gameplay.points.0"].exists)
        XCTAssertEqual(board.frame, originalBoard)
    }

    func testMonopolyWaitsForPrivateResultThenNamesPlayerAndCard() {
        let app = launch(["-qaShowDevCardHand"])
        XCTAssertTrue(app.buttons["dev-cards.tile.monopoly"].waitForExistence(timeout: 10))
        app.buttons["dev-cards.tile.monopoly"].tap()
        app.buttons["dev-cards.resource.ore"].tap()
        XCTAssertFalse(notice(in: app).exists)
        app.buttons["dev-cards.play.monopoly"].tap()
        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertFalse(notice(in: app).exists, "private result has priority")
        app.buttons["dev-cards.result.continue"].tap()
        let receipt = notice(in: app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 3))
        XCTAssertEqual(receipt.label, "Player 1 played Monopoly")
        capture(app, "Committed Monopoly public notice")
        XCTAssertTrue(receipt.waitForNonExistence(timeout: 6))
    }

    func testCityUpgradeSaysPlusOneAndBackgroundClearsFeedback() {
        let app = launch(["-qaShowPaidCityDecision"])
        let vertex = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'board.vertex.' AND isEnabled == true"
        )).firstMatch
        XCTAssertTrue(vertex.waitForExistence(timeout: 10))
        vertex.tap()
        app.buttons["board-decision.confirm"].tap()
        XCTAssertTrue(notice(in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(notice(in: app).label, "Player 1 gained 1 VP")
        capture(app, "City upgrade is one net victory point")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(notice(in: app).exists)
    }

    func testKnightNoticeRequiresConfirmedRobberAndPrivateAcknowledgement() {
        let app = launch(["-qaShowDevCardHand"])
        XCTAssertTrue(app.buttons["dev-cards.play.knight"].waitForExistence(timeout: 10))
        app.buttons["dev-cards.play.knight"].tap()
        enabledBoardButton(in: app, prefix: "board.tile.").tap()
        XCTAssertFalse(notice(in: app).exists)
        app.buttons["board-decision.confirm"].tap()
        acknowledgeResult(in: app, card: "Knight")
    }

    func testRoadBuildingNoticeRequiresBothRoadsCommitted() {
        let app = launch(["-qaShowDevCardHand"])
        XCTAssertTrue(app.buttons["dev-cards.tile.roadBuilding"].waitForExistence(timeout: 10))
        app.buttons["dev-cards.tile.roadBuilding"].tap()
        app.buttons["dev-cards.play.roadBuilding"].tap()
        enabledBoardButton(in: app, prefix: "board.edge.").tap()
        enabledBoardButton(in: app, prefix: "board.edge.").tap()
        XCTAssertFalse(notice(in: app).exists)
        app.buttons["board-decision.confirm"].tap()
        acknowledgeResult(in: app, card: "Road Building")
    }

    func testYearOfPlentyNoticeNamesTheCardAfterRealSelection() {
        let app = launch(["-qaShowDevCardHand"])
        XCTAssertTrue(app.buttons["dev-cards.tile.yearOfPlenty"].waitForExistence(timeout: 10))
        app.buttons["dev-cards.tile.yearOfPlenty"].tap()
        app.buttons["dev-cards.resource.ore"].tap()
        app.buttons["dev-cards.resource.ore"].tap()
        XCTAssertFalse(notice(in: app).exists)
        app.buttons["dev-cards.play.yearOfPlenty"].tap()
        acknowledgeResult(in: app, card: "Year of Plenty")
    }

    private func acknowledgeResult(in app: XCUIApplication, card: String) {
        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertFalse(notice(in: app).exists)
        app.buttons["dev-cards.result.continue"].tap()
        XCTAssertTrue(notice(in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(notice(in: app).label, "Player 1 played \(card)")
        capture(app, "Committed \(card) public notice")
    }

    private func enabledBoardButton(in app: XCUIApplication, prefix: String) -> XCUIElement {
        let button = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix
        )).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        return button
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart"] + arguments
        app.launch()
        return app
    }

    private func notice(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["gameplay.notice"].firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
