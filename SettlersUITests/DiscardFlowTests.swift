import XCTest

/// Proves that mandatory does not mean permanently modal: the board can be
/// inspected, but no game-producing command returns until the discard commits.
@MainActor
final class DiscardFlowTests: XCTestCase {
    func testDraftSurvivesBoardInspectionAndSettingsWhileCommandsStayAbsent() {
        continueAfterFailure = false
        let app = launchReset()

        XCTAssertTrue(app.staticTexts["discard.editor"].waitForExistence(timeout: 5))
        app.buttons["discard.hand.brick"].tap()
        XCTAssertTrue(app.staticTexts["1 of 4 selected"].exists)

        app.buttons["discard.minimize"].tap()
        XCTAssertTrue(app.buttons["discard.dock"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["discard.editor"].exists)
        let board = app.otherElements["board.surface"]
        let dock = app.buttons["discard.dock"]
        XCTAssertTrue(board.exists)
        XCTAssertGreaterThan(board.frame.height, 300,
                             "inspect mode must expose enough board to make a discard decision")
        XCTAssertLessThanOrEqual(board.frame.maxY, dock.frame.minY,
                                 "the mandatory-discard dock must not cover the board")
        assertGameplayCommandsAreAbsent(in: app)
        XCTAssertEqual(app.otherElements.matching(identifierPrefix: "board.inspect.tile.").count, 19)
        XCTAssertEqual(app.otherElements.matching(identifierPrefix: "board.inspect.port.").count, 9)
        XCTAssertGreaterThan(app.otherElements.matching(identifierPrefix: "board.inspect.building.").count, 0)
        XCTAssertGreaterThan(app.otherElements.matching(identifierPrefix: "board.inspect.road.").count, 0)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "discard-inspect-only-board"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["game.settings"].tap()
        XCTAssertTrue(app.otherElements["screen.in-game-settings"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["discard.dock"].exists,
                       "settings must hide the discard surface from assistive technology")
        app.buttons["in-game-settings.close"].tap()

        XCTAssertTrue(dock.waitForExistence(timeout: 2))
        XCTAssertTrue((dock.value as? String)?.contains("1 of 4 selected") == true)
        dock.tap()
        XCTAssertTrue(app.staticTexts["1 of 4 selected"].waitForExistence(timeout: 2))
    }

    func testExactCountWaitsForExplicitSubmitThenCommitsThroughTheEngine() {
        continueAfterFailure = false
        let app = launchReset()
        let brick = app.buttons["discard.hand.brick"]
        XCTAssertTrue(brick.waitForExistence(timeout: 5))

        brick.tap()
        brick.tap()
        app.buttons["discard.hand.lumber"].tap()
        app.buttons["discard.hand.grain"].tap()

        XCTAssertTrue(app.staticTexts["4 of 4 selected"].exists)
        XCTAssertTrue(app.staticTexts["discard.editor"].exists,
                      "reaching the count must never auto-submit")
        XCTAssertFalse(brick.isEnabled, "selection must stop at the required count")
        let submit = app.buttons["discard.submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertFalse(app.staticTexts["discard.editor"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["human-resource.brick"].value as? String, "2")
        XCTAssertTrue(enabledBoardButton(in: app, prefix: "board.tile.").exists,
                      "a committed discard must advance to the roller's robber decision")
    }

    func testColdRelaunchRestoresTheObligationExpandedWithABlankDraft() {
        continueAfterFailure = false
        let app = launchReset()
        XCTAssertTrue(app.buttons["discard.hand.brick"].waitForExistence(timeout: 5))
        app.buttons["discard.hand.brick"].tap()
        app.buttons["discard.minimize"].tap()
        XCTAssertTrue(app.buttons["discard.dock"].waitForExistence(timeout: 2))

        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()

        XCTAssertTrue(app.staticTexts["discard.editor"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["0 of 4 selected"].exists)
        XCTAssertFalse(app.buttons["discard.dock"].exists)
    }

    func testEditorControlsRemainReachableAtAccessibilityTextSize() {
        continueAfterFailure = false
        let standardApp = launchReset()
        let standardTitle = standardApp.staticTexts["discard.editor"]
        XCTAssertTrue(standardTitle.waitForExistence(timeout: 5))
        let standardTitleHeight = standardTitle.frame.height
        standardApp.terminate()

        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-reset",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-qaAutoStart", "-qaShowDiscard",
        ]
        app.launch()

        let scaledTitle = app.staticTexts["discard.editor"]
        XCTAssertTrue(scaledTitle.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            scaledTitle.frame.height,
            standardTitleHeight * 1.8,
            "the requested maximum Dynamic Type category must reach the rendered UI"
        )
        let minimize = app.buttons["discard.minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 5))
        XCTAssertTrue(minimize.isHittable, "\(minimize.debugDescription)")
        let submit = app.buttons["discard.submit"]
        XCTAssertTrue(submit.exists)
        XCTAssertFalse(submit.isEnabled)
        XCTAssertGreaterThanOrEqual(submit.frame.minY, app.frame.minY)
        XCTAssertLessThanOrEqual(submit.frame.maxY, app.frame.maxY,
                                 "the pinned submit control must remain on-screen at large text")

        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "discard-editor-accessibility-large"
        expanded.lifetime = .keepAlways
        add(expanded)

        minimize.tap()
        let dock = app.buttons["discard.dock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 2))
        XCTAssertTrue(dock.isHittable)
        XCTAssertGreaterThan(dock.frame.height, 75,
                             "the maximum accessibility category must reach the app and reflow the dock")
        XCTAssertGreaterThanOrEqual(dock.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(dock.frame.maxX, app.frame.maxX)
        XCTAssertLessThanOrEqual(dock.frame.maxY, app.frame.maxY)
        XCTAssertLessThan(dock.frame.height, 120,
                          "the reminder must stay compact enough to leave the board inspectable")
        let board = app.otherElements["board.surface"]
        XCTAssertGreaterThan(board.frame.height, 250)
        XCTAssertLessThanOrEqual(board.frame.maxY, dock.frame.minY)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "discard-dock-accessibility-large"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testMandatoryDiscardOutranksAlreadyOpenGameplaySurfaces() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-reset", "-qaAutoStart",
            "-qaShowBuildPopup", "-qaShowTradePopup", "-qaShowDevCardHand",
            "-qaShowDiscard",
        ]
        app.launch()

        XCTAssertTrue(app.buttons["discard.minimize"].waitForExistence(timeout: 5))
        app.buttons["discard.minimize"].tap()
        XCTAssertTrue(app.buttons["discard.dock"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["build.dev-card"].exists)
        XCTAssertFalse(app.buttons["trade.give.brick"].exists)
        XCTAssertFalse(app.otherElements["dev-cards.overlay"].exists)
    }

    private func launchReset() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowDiscard",
        ]
        app.launch()
        return app
    }

    private func assertGameplayCommandsAreAbsent(in app: XCUIApplication) {
        for title in ["Roll Dice", "Trade", "Build", "End Turn"] {
            XCTAssertFalse(app.buttons[title].exists, "\(title) leaked into inspect-only mode")
        }
        XCTAssertFalse(app.buttons["dev-cards.shelf"].exists)
        XCTAssertEqual(app.buttons.matching(identifierPrefix: "board.vertex.").count, 0)
        XCTAssertEqual(app.buttons.matching(identifierPrefix: "board.edge.").count, 0)
        XCTAssertEqual(app.buttons.matching(identifierPrefix: "board.tile.").count, 0)
    }

    private func enabledBoardButton(in app: XCUIApplication, prefix: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
            .firstMatch
    }
}

private extension XCUIElementQuery {
    func matching(identifierPrefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "identifier BEGINSWITH %@", identifierPrefix))
    }
}
