import XCTest

/// Jake, 2026-09-25: seat 1 is always you; every other seat is AI or Ghost, and
/// choosing Ghost offers the ghosts to pick from. Ghosts play Classic only.
@MainActor
final class GhostOpponentFlowTests: XCTestCase {

    private func openNewGame() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        return app
    }

    func testSeatOneIsYouAndTheOthersOfferAGhost() {
        continueAfterFailure = false
        let app = openNewGame()
        XCTAssertTrue(app.staticTexts["new-game.seat-you.0"].exists, "seat 1 is you, with no role control")
        XCTAssertFalse(app.buttons["new-game.seat-kind.0.ghost"].exists)
        for seat in 1...3 {
            XCTAssertTrue(app.buttons["new-game.seat-kind.\(seat).ghost"].exists, "seat \(seat + 1) offers a ghost")
            XCTAssertTrue(app.buttons["new-game.seat-kind.\(seat).ai"].exists)
        }
    }

    func testPickingJakesGhostSeatsItAndTheGameStarts() {
        continueAfterFailure = false
        let app = openNewGame()
        app.buttons["new-game.seat-kind.2.ghost"].tap()
        let jake = app.buttons["new-game.ghost-option.jake"]
        XCTAssertTrue(jake.waitForExistence(timeout: 3), "Jake's ghost ships in the app")
        jake.tap()
        XCTAssertTrue(app.staticTexts["Jake's Ghost"].waitForExistence(timeout: 2))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "new-game-with-jakes-ghost"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 10))
    }

    func testGhostsPlayClassicOnly() {
        continueAfterFailure = false
        let app = openNewGame()
        app.buttons["new-game.seat-kind.1.ghost"].tap()
        app.buttons["new-game.ghost-option.jake"].tap()
        XCTAssertTrue(app.staticTexts["Jake's Ghost"].waitForExistence(timeout: 2))
        app.buttons["Vast"].tap()
        XCTAssertFalse(app.staticTexts["Jake's Ghost"].exists, "a ghost seat goes back to AI outside Classic")
        let caption = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Ghosts play Classic only")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["new-game.start"].isEnabled)
    }

    /// The leaderboard opens from the home screen and shows both AI tiers.
    func testTheLeaderboardShowsTheFixedClassicAndExpert() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        app.buttons["main-menu.leaderboard"].tap()
        XCTAssertTrue(app.otherElements["screen.leaderboard"].waitForExistence(timeout: 5))
        let classic = app.buttons["leaderboard.row.classic"]
        XCTAssertTrue(classic.waitForExistence(timeout: 3))
        XCTAssertTrue(classic.label.contains("1000"), classic.label)
        XCTAssertTrue(classic.label.contains("fixed"), classic.label)
        XCTAssertTrue(app.buttons["leaderboard.row.expert"].label.contains("1229"))
        XCTAssertTrue(app.buttons["leaderboard.row.ghost:jake"].exists, "Jake's bundled ghost is listed")
    }

    /// Jake's page: games learned, games against humans, self-play, the graph, style.
    func testAGhostsPageShowsItsRecordGraphAndStyle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaSeedLeaderboard"]
        app.launch()
        app.buttons["main-menu.leaderboard"].tap()
        let jake = app.buttons["leaderboard.row.ghost:jake"]
        XCTAssertTrue(jake.waitForExistence(timeout: 5))
        let list = XCTAttachment(screenshot: app.screenshot())
        list.name = "leaderboard"
        list.lifetime = .keepAlways
        add(list)
        jake.tap()
        // A ScrollView reports itself as a scroll view, not an "other" element.
        XCTAssertTrue(app.descendants(matching: .any)["screen.rated-entity"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Games learned from its player"].exists)
        XCTAssertTrue(app.staticTexts["Games against humans"].exists)
        XCTAssertTrue(app.staticTexts["Against its own player"].exists)
        let radar = app.descendants(matching: .any)["leaderboard.radar"]
        XCTAssertTrue(radar.exists)
        XCTAssertTrue(radar.label.contains("Production"), radar.label)
        XCTAssertTrue(app.staticTexts["Style"].exists)
        let page = XCTAttachment(screenshot: app.screenshot())
        page.name = "jakes-ghost-page"
        page.lifetime = .keepAlways
        add(page)
    }
}
