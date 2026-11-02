import XCTest

/// Summary fixtures prove presentation only. A separate complete-match test
/// checks that an ordinary finished game creates its actual Elo receipt.
@MainActor
final class PlayerRatingsFlowTests: XCTestCase {
    func testMenuShowsPersonalRatingAndOverallRecord() {
        let app = launch(seed: true)
        let plaque = menuPlaque(app)
        XCTAssertTrue(plaque.label.contains("Alex"), plaque.label)
        XCTAssertTrue(plaque.label.contains("13 wins"), plaque.label)
        XCTAssertTrue(plaque.label.contains("9 losses"), plaque.label)
        capture("01-menu-rating-and-record", app)
        plaque.tap()
        XCTAssertTrue(app.otherElements["screen.player-ratings"].waitForExistence(timeout: 5))
        waitForRated(app.staticTexts["ratings.rating"])
    }

    func testNewPlayerSeesAnHonestUnratedState() {
        let app = launch(seed: false)
        let plaque = menuPlaque(app)
        XCTAssertTrue(plaque.label.contains("Unrated"), plaque.label)
        capture("02-menu-new-player", app)
        plaque.tap()
        XCTAssertTrue(app.otherElements["screen.player-ratings"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["ratings.rating"].label, "Unrated")
        capture("03-new-player-record", app)
    }

    func testFiltersKeepModeAndDifficultyRatingsIndependent() {
        let app = openRatings()
        let rating = app.staticTexts["ratings.rating"]
        waitForRated(rating)
        let expertRating = rating.label
        capture("04-personal-expert-rating", app)
        app.buttons["ratings.difficulty.classic"].tap()
        XCTAssertEqual(rating.label, "Unrated", "Unplayed Classic AI pool must not borrow Expert's Elo")
        app.buttons["ratings.difficulty.expert"].tap()
        XCTAssertEqual(rating.label, expertRating)
        chooseMode("naval.standard", app)
        XCTAssertNotEqual(rating.label, expertRating)
        XCTAssertNotEqual(rating.label, "Unrated")
        capture("05-voyages-independent-rating", app)
        app.buttons["ratings.difficulty.classic"].tap()
        XCTAssertEqual(rating.label, "Unrated")
        chooseMode("classic.conquest", app)
        XCTAssertNotEqual(rating.label, "Unrated")
        capture("06-conquest-classic-ai", app)
        app.buttons["ratings.close"].tap()
        XCTAssertTrue(app.buttons["main-menu.ratings"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let menu = app.buttons["main-menu.ratings"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.label.contains("Conquest"), menu.label)
    }

    func testStandingsOpenOtherPlayersAndEveryGameHasADelta() {
        let app = openRatings()
        let jake = app.buttons["ratings.player.ratings-preview-jake"]
        reveal(app.buttons["ratings.player.ratings-preview-kyle"], app)
        capture("07-shared-player-standings", app)
        jake.tap()
        let kyle = app.buttons["ratings.player.ratings-preview-kyle"]
        reveal(kyle, app)
        kyle.tap()
        let result = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'ratings.result.'")).firstMatch
        reveal(result, app)
        XCTAssertTrue(result.label.contains("Elo"), result.label)
        capture("08-game-by-game-rating-changes", app)
        app.buttons["ratings.close"].tap()
    }

    func testRatingHelpAndLocalSyncStateAreReachable() {
        let app = openRatings()
        app.buttons["ratings.help"].tap()
        XCTAssertTrue(app.buttons["ratings.help-close"].waitForExistence(timeout: 3))
        capture("09-rating-help", app)
        app.buttons["ratings.help-close"].tap()
        let sync = app.staticTexts["ratings.sync-status"]
        reveal(sync, app)
        XCTAssertEqual(sync.label, "Saved on this device")
        capture("10-local-record-status", app)
    }

    func testWinReceiptOpensTheSameRatingPool() { assertResult(won: true) }
    func testLossReceiptOpensTheSameRatingPool() { assertResult(won: false) }

    func testLegacyLeaderboardRoutesPeopleToTheirModeRecords() {
        let app = launch(seed: true)
        app.buttons["main-menu.leaderboard"].tap()
        let jake = app.buttons["leaderboard.row.person:ratings-preview-jake"]
        reveal(jake, app)
        XCTAssertTrue(app.buttons["leaderboard.row.ghost:jake"].exists)
        capture("16-legacy-and-ghost-ladder-context", app)
        jake.tap()
        let aiRecords = app.buttons["leaderboard.ai-ratings"]
        reveal(aiRecords, app)
        capture("18-legacy-player-record-and-ai-link", app)
        aiRecords.tap()
        XCTAssertTrue(app.otherElements["screen.player-ratings"].waitForExistence(timeout: 5))
        waitForRated(app.staticTexts["ratings.rating"])
        capture("17-jake-personal-record", app)
    }

    private func assertResult(won: Bool) {
        let app = launch(seed: true, extra: ["-qaAutoStart", won ? "-qaShowRatingWin" : "-qaShowRatingLoss"])
        let receipt = app.buttons["game-over.rating"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        XCTAssertTrue(receipt.label.contains(won ? "+" : "−"), receipt.label)
        capture(won ? "11-win-rating-receipt" : "12-loss-rating-receipt", app)
        reveal(receipt, app)
        receipt.tap()
        XCTAssertTrue(app.otherElements["screen.player-ratings"].waitForExistence(timeout: 5))
        waitForRated(app.staticTexts["ratings.rating"])
        XCTAssertTrue(app.buttons["ratings.difficulty.expert"].isSelected)
        if won { chooseMode("naval.standard", app) }
        app.buttons["ratings.close"].tap()
        XCTAssertTrue(app.buttons["game-over.main-menu"].waitForExistence(timeout: 3))
        if won {
            app.buttons["game-over.main-menu"].tap()
            let plaque = menuPlaque(app)
            XCTAssertTrue(plaque.label.contains("Voyages"), "Returning from the receipt must retain the chosen view")
        }
    }

    func testRestartAndReplacementExplainTheRatingLoss() {
        let app = launch(seed: false, extra: ["-qaAutoStart", "-qaShowPauseMenu"])
        let restart = app.buttons["in-game-settings.restart"]
        reveal(restart, app)
        restart.tap()
        let warning = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'count as a loss'")).firstMatch
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        capture("13-restart-loss-disclosure", app)
        app.buttons["Cancel"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["main-menu.new-game"].tap()
        app.buttons["new-game.start"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        capture("14-replacement-loss-disclosure", app)
    }

    func testLargeTextKeepsFiltersAndCloseUsable() {
        let app = launch(seed: true, extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ])
        let plaque = menuPlaque(app)
        reveal(plaque, app)
        capture("24-menu-largest-text", app)
        plaque.tap()
        XCTAssertTrue(app.otherElements["screen.player-ratings"].waitForExistence(timeout: 5))
        let close = app.buttons["ratings.close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.frame.contains(close.frame))
        let expert = app.buttons["ratings.difficulty.expert"]
        XCTAssertTrue(expert.isHittable)
        capture("15-ratings-largest-text", app)
        reveal(app.buttons["ratings.player.ratings-preview-kyle"], app)
        capture("20-standings-largest-text", app)
        let result = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'ratings.result.'")).firstMatch
        reveal(result, app)
        capture("21-game-record-largest-text", app)
        let mode = app.buttons["ratings.mode"]
        for _ in 0..<10 where !mode.isHittable { app.swipeDown() }
        mode.tap()
        let cancel = app.buttons["ratings.mode-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3) && cancel.isHittable)
        capture("22-mode-chooser-largest-text", app)
        cancel.tap()
        app.buttons["ratings.help"].tap()
        XCTAssertTrue(app.buttons["ratings.help-close"].waitForExistence(timeout: 3))
        capture("23-help-largest-text", app)
        app.buttons["ratings.help-close"].tap()
        close.tap()
        reveal(app.buttons["main-menu.new-game"], app)
    }

    private func launch(seed: Bool, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
            + (seed ? ["-qaSeedPlayerRatings"] : []) + extra
        app.launch()
        return app
    }

    private func openRatings() -> XCUIApplication {
        let app = launch(seed: true)
        let plaque = menuPlaque(app)
        plaque.tap()
        XCTAssertTrue(app.otherElements["screen.player-ratings"].waitForExistence(timeout: 5))
        waitForRated(app.staticTexts["ratings.rating"])
        return app
    }

    private func menuPlaque(_ app: XCUIApplication) -> XCUIElement {
        let plaque = app.buttons["main-menu.ratings"]
        XCTAssertTrue(plaque.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: plaque)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        return plaque
    }

    private func waitForRated(_ element: XCUIElement) {
        let loaded = NSPredicate { _, _ in element.exists && element.label != "Unrated" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 5), .completed)
    }

    private func chooseMode(_ suffix: String, _ app: XCUIApplication) {
        app.buttons["ratings.mode"].tap()
        let option = app.buttons["ratings.mode.\(suffix)"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        capture("19-painted-mode-chooser-\(suffix)", app)
        option.tap()
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
