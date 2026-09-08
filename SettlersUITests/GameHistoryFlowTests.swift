import XCTest

/// Drives Game History and the replay screen through the same controls a
/// player uses. A replay that renders a board in a screenshot but cannot be
/// scrubbed is not a replay, so every assertion here is about the caption or
/// the score changing in response to a real tap.
@MainActor
final class GameHistoryFlowTests: XCTestCase {
    private func launchWithArchive(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaSeedGameHistory"] + extraArguments
        app.launch()
        return app
    }

    func testGameHistoryOpensFromTheMainMenuAndListsARecordedGame() {
        continueAfterFailure = false
        let app = launchWithArchive()

        let history = app.buttons["main-menu.game-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        history.tap()

        XCTAssertTrue(app.otherElements["screen.game-history"].waitForExistence(timeout: 3))
        XCTAssertTrue(firstRecordedGame(in: app).waitForExistence(timeout: 3))

        app.buttons["game-history.close"].tap()
        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 3))
    }

    /// The button is a promise that there is something to open. On a fresh
    /// install there is not, and the menu must not offer it.
    func testGameHistoryIsHiddenUntilAGameHasBeenRecorded() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()

        XCTAssertTrue(app.buttons["main-menu.new-game"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["main-menu.game-history"].exists)
    }

    func testSteppingThroughAReplayChangesTheBoardAndTheCaption() {
        continueAfterFailure = false
        let app = launchWithArchive(["-qaShowGameHistory"])
        openFirstReplay(in: app)

        let caption = app.staticTexts["replay.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        XCTAssertEqual(caption.label, "Opening position")
        XCTAssertTrue(app.otherElements["board.surface"].exists)

        app.buttons["replay.next"].tap()
        let firstMove = caption.label
        XCTAssertNotEqual(firstMove, "Opening position")

        app.buttons["replay.next"].tap()
        XCTAssertNotEqual(caption.label, firstMove)

        app.buttons["replay.previous"].tap()
        XCTAssertEqual(caption.label, firstMove)
    }

    /// Jumping to the end must land on the finished board, which is the whole
    /// reason the score strip is on this screen: somebody has points by then.
    func testJumpingToTheEndShowsTheFinishedPositionAndScores() {
        continueAfterFailure = false
        let app = launchWithArchive(["-qaShowGameHistory"])
        openFirstReplay(in: app)

        let opening = element(app, "replay.score.0")
        XCTAssertTrue(opening.waitForExistence(timeout: 10))
        XCTAssertTrue(opening.label.contains("0 VP"))

        app.buttons["replay.end"].tap()

        let scored = (0..<4).contains { seat in
            !element(app, "replay.score.\(seat)").label.contains("0 VP")
        }
        XCTAssertTrue(scored, "No seat had scored by the last frame of the replay")

        app.buttons["replay.start"].tap()
        XCTAssertEqual(app.staticTexts["replay.caption"].label, "Opening position")
    }

    func testPlaybackAdvancesTheReplayOnItsOwnAndStops() {
        continueAfterFailure = false
        let app = launchWithArchive(["-qaShowGameHistory"])
        openFirstReplay(in: app)

        let caption = app.staticTexts["replay.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 10))
        app.buttons["replay.play-pause"].tap()

        let advanced = NSPredicate(format: "label != %@", "Opening position")
        expectation(for: advanced, evaluatedWith: caption)
        waitForExpectations(timeout: 5)

        app.buttons["replay.play-pause"].tap()
        let paused = caption.label
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(caption.label, paused, "Playback kept running after pause")
    }

    // MARK: - Helpers

    /// A combined accessibility element is not guaranteed to surface as any
    /// particular XCUIElement type, so these are looked up by identifier
    /// across every type rather than guessed at.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func firstRecordedGame(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "game-history.game."))
            .firstMatch
    }

    private func openFirstReplay(in app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["screen.game-history"].waitForExistence(timeout: 5))
        let game = firstRecordedGame(in: app)
        XCTAssertTrue(game.waitForExistence(timeout: 3))
        game.tap()
        XCTAssertTrue(app.otherElements["screen.replay"].waitForExistence(timeout: 10))
    }
}
