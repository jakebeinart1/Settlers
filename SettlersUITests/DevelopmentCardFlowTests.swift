import XCTest

/// Proves the card journey through taps rather than launch-only screenshots.
@MainActor
final class DevelopmentCardFlowTests: XCTestCase {
    func testPurchaseRevealsExactCardAndAcknowledgementSurvivesRelaunch() {
        continueAfterFailure = false
        let app = launchReset(arguments: ["-qaAutoStart", "-qaDevCardPurchase"])
        let build = app.buttons["Build"]
        XCTAssertTrue(build.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: build)
        waitForExpectations(timeout: 5)

        build.tap()
        let buy = app.buttons["build.dev-card"]
        XCTAssertTrue(buy.waitForExistence(timeout: 2))
        XCTAssertTrue(buy.isEnabled)
        buy.tap()

        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["dev-cards.detail.monopoly"].exists)
        XCTAssertTrue(app.staticTexts["New this turn"].exists)

        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.staticTexts["dev-cards.detail.monopoly"].waitForExistence(timeout: 5))

        app.buttons["dev-cards.continue"].tap()
        XCTAssertFalse(app.otherElements["dev-cards.overlay"].exists)
        app.terminate()
        app.launch()
        XCTAssertFalse(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 2))
    }

    func testBlockedCardRemainsInspectableAndPlayExplainsWhy() {
        continueAfterFailure = false
        let app = launchReset(arguments: ["-qaAutoStart", "-qaShowDevCardHand"])
        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 5))

        app.buttons["dev-cards.tile.monopoly"].tap()
        app.buttons["dev-cards.resource.wool"].tap()
        app.buttons["dev-cards.play.monopoly"].tap()
        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        app.buttons["dev-cards.result.continue"].tap()
        app.buttons["dev-cards.shelf"].tap()

        app.buttons["dev-cards.tile.roadBuilding"].tap()

        XCTAssertTrue(app.staticTexts["dev-cards.detail.roadBuilding"].exists)
        XCTAssertTrue(app.staticTexts["1 READY · 1 NEW"].exists)
        XCTAssertTrue(app.staticTexts["One card already played"].exists)
        let play = app.buttons["dev-cards.play.roadBuilding"]
        XCTAssertTrue(play.exists)
        XCTAssertFalse(play.isEnabled)
    }

    func testMonopolyZeroResultIsExplicit() {
        continueAfterFailure = false
        let app = launchReset(arguments: ["-qaAutoStart", "-qaShowDevCardHand"])
        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 5))
        app.buttons["dev-cards.tile.monopoly"].tap()
        app.buttons["dev-cards.resource.wool"].tap()
        let play = app.buttons["dev-cards.play.monopoly"]
        XCTAssertTrue(play.isEnabled)
        play.tap()

        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No rival held any wool. You collected 0 cards."].exists)
        app.buttons["dev-cards.result.continue"].tap()
        XCTAssertFalse(app.staticTexts["dev-cards.result"].exists)
    }

    func testYearOfPlentyChoosesExactlyTwoCardsAndReportsThem() {
        continueAfterFailure = false
        let app = launchReset(arguments: ["-qaAutoStart", "-qaShowDevCardHand"])
        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 5))
        app.buttons["dev-cards.tile.yearOfPlenty"].tap()

        let ore = app.buttons["dev-cards.resource.ore"]
        XCTAssertTrue(ore.waitForExistence(timeout: 2))
        ore.tap()
        ore.tap()
        let play = app.buttons["dev-cards.play.yearOfPlenty"]
        XCTAssertTrue(play.isEnabled)
        play.tap()

        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The bank gave you 2 ore."].exists)
    }

    func testKnightCanCancelThenResolveThroughAnAccessibleBoardTile() {
        continueAfterFailure = false
        let app = launchReset(arguments: ["-qaAutoStart", "-qaShowDevCardHand"])
        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 5))
        app.buttons["dev-cards.play.knight"].tap()

        let cancel = app.buttons[BoardDecisionUITestID.cancel]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["dev-cards.result"].exists)

        app.buttons["dev-cards.shelf"].tap()
        app.buttons["dev-cards.tile.knight"].tap()
        app.buttons["dev-cards.play.knight"].tap()
        let destination = enabledBoardButton(in: app, prefix: "board.tile.")
        destination.tap()

        let preview = app.otherElements[BoardDecisionUITestID.robberPreview]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(destination.value as? String, "Selected destination")
        XCTAssertFalse(app.staticTexts["dev-cards.result"].exists)
        let confirm = app.buttons[BoardDecisionUITestID.confirm]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertTrue(preview.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["The robber moved. No rival was eligible to steal from."].exists)
    }

    func testRoadBuildingSupportsUndoAndCommitsBothRoadsTogether() {
        continueAfterFailure = false
        let app = launchReset(arguments: ["-qaAutoStart", "-qaShowDevCardHand"])
        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 5))
        app.buttons["dev-cards.tile.roadBuilding"].tap()
        let play = app.buttons["dev-cards.play.roadBuilding"]
        XCTAssertTrue(play.isEnabled)
        play.tap()

        enabledBoardButton(in: app, prefix: "board.edge.").tap()
        XCTAssertTrue(app.otherElements["board.road-preview"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["dev-cards.result"].exists)
        let confirm = app.buttons[BoardDecisionUITestID.confirm]
        XCTAssertFalse(confirm.isEnabled)
        let undo = app.buttons[BoardDecisionUITestID.undo]
        XCTAssertTrue(undo.waitForExistence(timeout: 2))
        undo.tap()
        XCTAssertFalse(app.otherElements["board.road-preview"].exists)

        enabledBoardButton(in: app, prefix: "board.edge.").tap()
        enabledBoardButton(in: app, prefix: "board.edge.").tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.roadPreview].exists)
        XCTAssertFalse(app.staticTexts["dev-cards.result"].exists)
        XCTAssertTrue(confirm.isEnabled)

        let clear = app.buttons[BoardDecisionUITestID.clear]
        XCTAssertTrue(clear.exists)
        XCTAssertTrue(app.buttons[BoardDecisionUITestID.cancel].exists)
        let proposalScreenshot = XCTAttachment(screenshot: app.screenshot())
        proposalScreenshot.name = "road-building-two-road-proposal"
        proposalScreenshot.lifetime = .keepAlways
        add(proposalScreenshot)
        clear.tap()
        XCTAssertFalse(app.otherElements[BoardDecisionUITestID.roadPreview].exists)
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].exists,
                      "Clear must retain the active Road Building decision")

        enabledBoardButton(in: app, prefix: "board.edge.").tap()
        enabledBoardButton(in: app, prefix: "board.edge.").tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts[
            "Both free roads were placed together and your network has been updated."
        ].exists)
        app.buttons["dev-cards.result.continue"].tap()
        XCTAssertTrue(app.buttons["Roll Dice"].waitForExistence(timeout: 2),
                      "Road Building must remain fully usable before the roll")
    }

    func testHotSeatCoverHidesPrivateRevealFromAccessibilityUntilClaimed() {
        continueAfterFailure = false
        let app = launchReset(arguments: [
            "-qaAutoStart", "-qaTwoHumans", "-qaShowDevCardReveal",
        ])

        let ready = app.buttons["handoff.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["dev-cards.detail.yearOfPlenty"].exists,
                       "the covered player's exact card leaked through accessibility")

        ready.tap()

        XCTAssertTrue(app.staticTexts["dev-cards.detail.yearOfPlenty"].waitForExistence(timeout: 3))
    }

    func testCardHandKeepsActionsReachableAtAccessibilityTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-reset",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityLarge",
            "-qaAutoStart", "-qaShowDevCardHand",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["dev-cards.detail.knight"].exists)
        let close = app.buttons["dev-cards.close"]
        XCTAssertTrue(close.exists)
        XCTAssertTrue(close.isHittable, "the pinned action bar must remain usable at large text")
    }

    func testEmptyShelfIsDiscoverable() {
        continueAfterFailure = false
        // Start from an ordinary main turn. Fresh games now correctly owe a
        // mandatory setup placement, which outranks opening the private hand.
        let app = launchReset(arguments: ["-qaAutoStart", "-qaPaidBuildPosition"])
        let shelf = app.buttons["dev-cards.shelf"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 5))
        XCTAssertEqual(shelf.value as? String, "0")
        shelf.tap()
        XCTAssertTrue(app.staticTexts["No development cards yet"].waitForExistence(timeout: 2))
    }

    func testWinningPointIsRevealedBeforeTheEndGameSurface() {
        continueAfterFailure = false
        let app = launchReset(arguments: ["-qaAutoStart", "-qaShowWinningDevCardReveal"])

        XCTAssertTrue(app.otherElements["dev-cards.overlay"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["dev-cards.detail.victoryPoint"].exists)

        app.buttons["dev-cards.view-hand"].tap()
        XCTAssertTrue(app.buttons["dev-cards.tile.victoryPoint"].waitForExistence(timeout: 2))
        app.buttons["dev-cards.close"].tap()

        let claim = app.buttons["dev-cards.continue"]
        XCTAssertEqual(claim.label, "Claim Victory")
        claim.tap()

        XCTAssertTrue(app.buttons["game-over.new-game"].waitForExistence(timeout: 3))
    }

    private func launchReset(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"] + arguments
        app.launch()
        return app
    }

    private func enabledBoardButton(in app: XCUIApplication, prefix: String) -> XCUIElement {
        let button = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
            .firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Expected enabled board control with prefix \(prefix)")
        return button
    }
}
