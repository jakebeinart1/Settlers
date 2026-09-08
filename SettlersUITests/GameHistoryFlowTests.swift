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

    /// Stepping, jumping and playback in one launch, deliberately.
    ///
    /// These were three tests and three app launches. The suite that costs
    /// nothing on its own is not free inside `gate.sh`, which runs both
    /// bundles across parallel simulator clones: the extra launches starved
    /// `GameplayBoundaryFlowTests.testRealAutomatedMatchReachesGameOverAndClearsItsSave`
    /// - which plays a whole match on the main actor - into "Failed to get
    /// matching snapshots" twice. Measured 2026-09-08: that test fails under
    /// this suite's load and passes without it, with no change to itself. One
    /// launch, three claims.
    func testTheReplayStepsScrubsAndPlaysBack() {
        continueAfterFailure = false
        let app = launchWithArchive(["-qaShowGameHistory"])
        openFirstReplay(in: app)

        let caption = app.staticTexts["replay.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        XCTAssertEqual(caption.label, "Opening position")
        XCTAssertTrue(app.otherElements["board.surface"].exists)
        XCTAssertTrue(element(app, "replay.score.0").label.contains("0 VP"))

        // Stepping forward and back lands on the same move again.
        app.buttons["replay.next"].tap()
        let firstMove = caption.label
        XCTAssertNotEqual(firstMove, "Opening position")
        app.buttons["replay.next"].tap()
        XCTAssertNotEqual(caption.label, firstMove)
        app.buttons["replay.previous"].tap()
        XCTAssertEqual(caption.label, firstMove)

        // The end of the recording is a board somebody has scored on.
        app.buttons["replay.end"].tap()
        let scored = (0..<4).contains { seat in
            !element(app, "replay.score.\(seat)").label.contains("0 VP")
        }
        XCTAssertTrue(scored, "No seat had scored by the last frame of the replay")

        // Playback advances on its own, and pause actually stops it.
        app.buttons["replay.start"].tap()
        XCTAssertEqual(caption.label, "Opening position")
        app.buttons["replay.play-pause"].tap()
        expectation(for: NSPredicate(format: "label != %@", "Opening position"), evaluatedWith: caption)
        waitForExpectations(timeout: 8)
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
