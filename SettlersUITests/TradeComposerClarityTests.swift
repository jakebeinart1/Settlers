import XCTest

/// Regressions for the four-tray editor and the moving, color-only offer.
/// These assert observable quantities and words, not just new element IDs.
@MainActor
final class TradeComposerClarityTests: XCTestCase {
    private static let reviewHoldSeconds: TimeInterval = 16
    private static let timerTestTimeout: TimeInterval = 20

    func testPlayerDraftHasTwoNamedRowsAndEditsQuantitiesInPlace() {
        let app = launch("-qaBankTradePosition")
        app.buttons["Trade"].tap()
        XCTAssertTrue(app.staticTexts["You give"].exists)
        XCTAssertTrue(app.staticTexts["You receive"].exists)
        XCTAssertFalse(app.staticTexts["YOUR HAND"].exists)
        XCTAssertFalse(app.staticTexts["ASK FOR"].exists)
        let grain = app.buttons["trade.give.grain"]
        grain.tap()
        grain.tap()
        XCTAssertEqual(grain.value as? String, "2")
        XCTAssertTrue(grain.label.contains("Grain"))
        XCTAssertEqual(app.staticTexts["trade.inventory.grain"].label, "5 left")
        app.buttons["trade.give.remove.grain"].tap()
        XCTAssertEqual(grain.value as? String, "1")
        app.buttons["trade.want.ore"].tap()
        XCTAssertEqual(app.buttons["trade.want.ore"].value as? String, "1")
        XCTAssertFalse(app.buttons["trade.want.grain"].isEnabled)
        XCTAssertTrue(app.buttons["Propose to Bots"].isEnabled)
        XCTAssertFalse(app.staticTexts["2:1"].exists, "Bank rates do not govern player offers")
    }

    func testSwitchingToBankRepairsAPartialBundleWithoutClearingTheOffer() {
        let app = launch("-qaBankTradePosition")
        app.buttons["Trade"].tap()
        app.buttons["trade.give.grain"].tap()
        app.buttons["trade.want.ore"].tap()
        app.buttons["Bank"].tap()
        XCTAssertFalse(app.buttons["Trade with Bank"].isEnabled)
        // The old editor adds a whole bundle to 1, leaving 3 at a 2:1 port.
        app.buttons["trade.bank.give.grain"].tap()
        XCTAssertEqual(app.buttons["trade.bank.give.grain"].value as? String, "2")
        XCTAssertEqual(app.buttons["trade.bank.get.ore"].value as? String, "1")
        XCTAssertTrue(app.buttons["Trade with Bank"].isEnabled)
        XCTAssertTrue(app.buttons["Close"].isHittable)
    }

    func testIncomingOfferNamesTheLocalPlayersExchangeWithoutAMarquee() {
        let app = launch("-qaShowIncomingOffer")
        XCTAssertTrue(app.buttons["incoming-trade.accept"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["incoming-trade.give"].label, "You give 1 Grain")
        XCTAssertEqual(app.staticTexts["incoming-trade.receive"].label, "You receive 1 Brick")
        let proposer = app.staticTexts["incoming-trade.proposer"]
        XCTAssertTrue(proposer.label.contains("offers a trade"))
        XCTAssertTrue(app.frame.contains(proposer.frame))
        XCTAssertGreaterThanOrEqual(app.buttons["incoming-trade.accept"].frame.width, 44)
        app.buttons["incoming-trade.reject"].tap()
        XCTAssertFalse(app.buttons["incoming-trade.accept"].exists)
    }

    func testWideIncomingBundleCanBeReviewedWithEveryNamedQuantityBeforeAccepting() {
        let app = launch("-qaShowIncomingOffer", "-qaBundleOffer")
        let review = app.buttons["incoming-trade.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["incoming-trade.accept"].exists,
                       "A compressed total cannot be the sole basis for accepting")
        review.tap()
        for term in ["3 Grain", "2 Brick", "1 Lumber", "1 Ore", "1 Wool"] {
            let text = app.staticTexts[term]
            XCTAssertTrue(text.waitForExistence(timeout: 2), "Missing named quantity: \(term)")
            XCTAssertTrue(app.frame.contains(text.frame))
        }
        XCTAssertTrue(app.buttons["incoming-trade.accept"].isHittable)
        app.buttons["incoming-trade.accept"].tap()
        XCTAssertTrue(app.staticTexts["Trade complete"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["3 Grain"].exists)
        XCTAssertTrue(app.staticTexts["2 Brick"].exists)
    }

    func testFullIncomingReviewHoldsTheTimerAndDoesNotMoveTheBoard() {
        let app = launch("-qaShowIncomingOffer", "-qaBundleOffer")
        let review = app.buttons["incoming-trade.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        let boardFrame = app.otherElements["board.surface"].frame
        let commandFrame = app.otherElements["game.command-row"].frame
        review.tap()
        let held = expectation(description: "review outlasts the default 15-second deadline")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reviewHoldSeconds) { held.fulfill() }
        wait(for: [held], timeout: Self.timerTestTimeout)
        XCTAssertTrue(app.buttons["incoming-trade.accept"].exists)
        app.buttons["incoming-trade.review.close"].tap()
        let returned = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: review)
        wait(for: [returned], timeout: 3)
        XCTAssertEqual(app.otherElements["board.surface"].frame, boardFrame)
        XCTAssertEqual(app.otherElements["game.command-row"].frame, commandFrame)
        app.buttons["incoming-trade.reject"].tap()
    }

    private func launch(_ fixture: String, _ modifiers: String...) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", fixture] + modifiers
        app.launch()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 10))
        return app
    }
}
