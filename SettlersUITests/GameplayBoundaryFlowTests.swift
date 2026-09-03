import XCTest

/// Exercises the modal boundaries most likely to make a playable game stall.
@MainActor
final class GameplayBoundaryFlowTests: XCTestCase {
    func testHotSeatHandoffCanBeAcknowledged() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaTwoHumans"])

        let ready = app.buttons["handoff.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        ready.tap()

        XCTAssertFalse(ready.waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["screen.game"].exists)
    }

    func testIncomingTradeCanBeRejected() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaShowIncomingOffer"])

        let reject = app.buttons["incoming-trade.reject"]
        XCTAssertTrue(reject.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["incoming-trade.accept"].exists)
        let resourcesBeforeRejecting = humanResourceSnapshot(in: app)
        reject.tap()

        XCTAssertFalse(reject.waitForExistence(timeout: 2))
        XCTAssertEqual(humanResourceSnapshot(in: app), resourcesBeforeRejecting)
    }

    func testIncomingTradeCanBeAcceptedAndExchangesRealResources() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaShowIncomingOffer"])

        let accept = app.buttons["incoming-trade.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        assertHumanResources(brick: 0, grain: 1, in: app)
        accept.tap()

        XCTAssertFalse(accept.waitForExistence(timeout: 2))
        assertHumanResources(brick: 1, grain: 0, in: app)
    }

    func testIncomingTradeTimerStopsWhileSettingsAreOpen() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaShowIncomingOffer"])

        XCTAssertTrue(app.buttons["incoming-trade.accept"].waitForExistence(timeout: 5))
        app.buttons["game.settings"].tap()
        XCTAssertTrue(app.otherElements["screen.in-game-settings"].waitForExistence(timeout: 2))

        let timerWouldHaveExpired = expectation(description: "default 15-second offer timer elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdPastDefaultTimerSeconds) {
            timerWouldHaveExpired.fulfill()
        }
        wait(for: [timerWouldHaveExpired], timeout: Self.timerTestTimeoutSeconds)

        app.buttons["in-game-settings.close"].tap()
        XCTAssertTrue(app.buttons["incoming-trade.accept"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["incoming-trade.reject"].exists)
        assertHumanResources(brick: 0, grain: 1, in: app)
    }

    func testCompletedGameReturnsToMainMenuWithoutAResumeButton() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaShowEndGame"])

        let newGame = app.buttons["game-over.new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        newGame.tap()

        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["main-menu.resume"].exists)
    }

    private func launch(arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"] + arguments
        app.launch()
        return app
    }

    private func resourceCount(_ resource: ResourceName, in app: XCUIApplication) -> String {
        let element = app.otherElements["human-resource.\(resource.rawValue)"]
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        return element.value as? String ?? ""
    }

    private func assertHumanResources(brick: Int, grain: Int, in app: XCUIApplication) {
        XCTAssertEqual(resourceCount(.brick, in: app), "\(brick)")
        XCTAssertEqual(resourceCount(.grain, in: app), "\(grain)")
    }

    private func humanResourceSnapshot(in app: XCUIApplication) -> [ResourceName: String] {
        Dictionary(uniqueKeysWithValues: ResourceName.allCases.map {
            ($0, resourceCount($0, in: app))
        })
    }

    /// The shipped default is 15 seconds. Waiting one second beyond it proves
    /// settings held the countdown rather than merely racing its deadline.
    private static let holdPastDefaultTimerSeconds: TimeInterval = 16
    private static let timerTestTimeoutSeconds: TimeInterval = holdPastDefaultTimerSeconds + 1

    private enum ResourceName: String, CaseIterable {
        case brick, lumber, ore, grain, wool
    }
}
