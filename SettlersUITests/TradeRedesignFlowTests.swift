import XCTest

/// Product journeys missing from TradeComposerClarityTests: complete two bank
/// exchanges in one popup, and reach every confirmation action on a short phone.
/// Expected quantities come from QATrade's conserved seven-grain / 2:1 fixture.
/// Each launch resets independently, including an Xcode retry of a failed test.
@MainActor
final class TradeRedesignFlowTests: XCTestCase {
    private enum Timing {
        static let launch: TimeInterval = 10
        static let transition: TimeInterval = 3
    }

    private enum Layout {
        static let shortPhone = CGSize(width: 375, height: 667)
        static let tolerance: CGFloat = 1
        static let maximumScrolls = 3
    }

    private static let resources = ["brick", "lumber", "wool", "grain", "ore"]

    func testBankPlusMinusThenTradeAgainCommitsANewExactReceiptAndCloses() {
        let app = launchBankPosition()
        defer { app.terminate() }
        tap("Trade", in: app)
        tap("Bank", in: app)
        composeAdjustedBankTrade(in: app)
        tap("Trade with Bank", in: app)
        assertBankReceipt(gave: "4 Grain", received: "2 Ore", in: app)
        tap("Trade again", in: app)
        assertEmptyDraft(prefix: "trade.bank", receiveSide: "get", in: app)
        XCTAssertEqual(app.staticTexts["trade.inventory.grain"].label, "3 left")
        XCTAssertEqual(app.staticTexts["trade.inventory.ore"].label, "2 left")
        XCTAssertEqual(app.staticTexts["trade.bank.stock.ore"].label, "Bank has 14 Ore")
        tap("trade.bank.give.grain", in: app)
        tap("trade.bank.get.ore", in: app)
        assertQuantity("trade.bank.give.grain", equals: "2", in: app)
        assertQuantity("trade.bank.get.ore", equals: "1", in: app)
        tap("Trade with Bank", in: app)
        assertBankReceipt(gave: "2 Grain", received: "1 Ore", in: app)
        XCTAssertFalse(app.staticTexts["4 Grain"].exists, "The second receipt must not replay the first trade")
        XCTAssertFalse(app.staticTexts["2 Ore"].exists)
        tap("Close trade", in: app)
        assertClosedHand(grain: "1", ore: "3", in: app)
        assertReopeningHasNoReceiptOrConfirmation(in: app)
    }

    /// An explicit device mismatch is a skip, not a claim that 402pt proved
    /// 375×667. Main runs this case on its serialized short-phone destination.
    func testConfirmationFooterAndNewOfferRemainReachableAt375By667() throws {
        let app = launchBankPosition()
        defer { app.terminate() }
        guard abs(app.frame.width - Layout.shortPhone.width) <= Layout.tolerance,
              abs(app.frame.height - Layout.shortPhone.height) <= Layout.tolerance else {
            throw XCTSkip("Requires a 375×667-point iPhone; this destination is \(app.frame.size)")
        }
        tap("Trade", in: app)
        tap("trade.give.grain", times: 6, in: app)
        tap("trade.want.ore", in: app)
        tap("Propose to Bots", in: app)
        XCTAssertTrue(app.buttons["Confirm Trade"].waitForExistence(timeout: Timing.transition))
        XCTAssertFalse(app.staticTexts["Trade complete"].exists, "A bot's yes has not exchanged any cards")
        assertPinnedConfirmationActions(in: app)
        assertVisibleTerms(["You give", "6 Grain", "You receive", "1 Ore"], in: app)
        assertPinnedConfirmationActions(in: app)
        attachScreenshot("375×667 pending player-trade confirmation", in: app)
        tap("Confirm Trade", in: app)
        assertReceipt(gave: "6 Grain", received: "1 Ore", in: app)
        assertReachable(app.buttons["Trade again"], in: app)
        assertReachable(app.buttons["Close trade"], in: app)
        tap("Trade again", in: app)
        assertEmptyDraft(prefix: "trade", receiveSide: "want", in: app)
        XCTAssertFalse(app.buttons["Confirm Trade"].exists)
        assertReachable(app.buttons["Propose to Bots"], in: app)
        tap("Close", in: app)
        assertClosedHand(grain: "1", ore: "1", in: app)
    }

    private func launchBankPosition() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaBankTradePosition"]
        app.launch()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: Timing.launch),
                      "The existing bank fixture must reach the game before any trade assertion")
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: Timing.transition))
        return app
    }

    private func composeAdjustedBankTrade(in app: XCUIApplication) {
        // Giving advances by a port bundle; receiving advances by one card.
        tap("trade.bank.give.grain", times: 3, in: app)
        assertQuantity("trade.bank.give.grain", equals: "6", in: app)
        tap("trade.bank.get.ore", times: 3, in: app)
        assertQuantity("trade.bank.get.ore", equals: "3", in: app)
        XCTAssertFalse(app.buttons["trade.bank.get.ore"].isEnabled)
        tap("trade.bank.get.remove.ore", in: app)
        assertQuantity("trade.bank.get.ore", equals: "2", in: app)
        XCTAssertFalse(app.buttons["Trade with Bank"].isEnabled, "Three bundles cannot buy only two cards")
        tap("trade.bank.give.remove.grain", in: app)
        assertQuantity("trade.bank.give.grain", equals: "4", in: app)
        XCTAssertTrue(app.buttons["Trade with Bank"].isEnabled)
    }

    private func assertEmptyDraft(prefix: String, receiveSide: String, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Trade complete"].waitForNonExistence(timeout: Timing.transition))
        for resource in Self.resources {
            assertQuantity("\(prefix).give.\(resource)", equals: "0", in: app)
            assertQuantity("\(prefix).\(receiveSide).\(resource)", equals: "0", in: app)
            XCTAssertFalse(app.buttons["\(prefix).give.remove.\(resource)"].isEnabled)
            XCTAssertFalse(app.buttons["\(prefix).\(receiveSide).remove.\(resource)"].isEnabled)
        }
        let action = prefix == "trade.bank" ? "Trade with Bank" : "Propose to Bots"
        XCTAssertFalse(app.buttons[action].isEnabled, "Trade again must not leave a submittable stale draft")
        XCTAssertFalse(app.buttons["trade.clear"].isEnabled)
    }

    private func assertBankReceipt(gave: String, received: String, in app: XCUIApplication) {
        assertReceipt(gave: gave, received: received, in: app)
        XCTAssertTrue(app.staticTexts["Traded with the Bank. Your hand is updated."].exists)
        XCTAssertFalse(app.buttons["Trade with Bank"].exists)
        assertReachable(app.buttons["Trade again"], in: app)
        assertReachable(app.buttons["Close trade"], in: app)
    }

    private func assertReceipt(gave: String, received: String, in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Trade complete"].waitForExistence(timeout: Timing.transition))
        assertVisibleTerms(["YOU GAVE", gave, "YOU RECEIVED", received], in: app)
    }

    private func assertClosedHand(grain: String, ore: String, in app: XCUIApplication) {
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: Timing.transition))
        XCTAssertFalse(app.staticTexts["Trade complete"].exists)
        for (resource, count) in [("grain", grain), ("ore", ore), ("brick", "0"), ("lumber", "0"), ("wool", "0")] {
            XCTAssertEqual(app.otherElements["human-resource.\(resource)"].value as? String, count,
                           "Only the committed exchanges may alter \(resource)")
        }
    }

    private func assertReopeningHasNoReceiptOrConfirmation(in app: XCUIApplication) {
        tap("Trade", in: app)
        assertEmptyDraft(prefix: "trade", receiveSide: "want", in: app)
        XCTAssertFalse(app.buttons["Confirm Trade"].exists)
        XCTAssertFalse(app.buttons["Trade again"].exists)
        XCTAssertEqual(app.staticTexts["trade.inventory.grain"].label, "1 left")
        XCTAssertEqual(app.staticTexts["trade.inventory.ore"].label, "3 left")
        tap("Close", in: app)
        assertClosedHand(grain: "1", ore: "3", in: app)
    }

    private func assertPinnedConfirmationActions(in app: XCUIApplication) {
        let actions = ["Decline", "Confirm Trade", "Close"].map { app.buttons[$0] }
        actions.forEach { assertReachable($0, in: app) }
        let frames = actions.map(\.frame)
        let content = app.scrollViews.firstMatch
        // A hugging confirmation needs no scroller; when one is present its
        // content must never carry the footer with it.
        if content.exists {
            for swipeUp in [true, false] {
                if swipeUp { content.swipeUp() } else { content.swipeDown() }
                for (action, frame) in zip(actions, frames) {
                    assertReachable(action, in: app)
                    XCTAssertEqual(action.frame.minY, frame.minY, accuracy: Layout.tolerance)
                    XCTAssertEqual(action.frame.maxY, frame.maxY, accuracy: Layout.tolerance)
                }
            }
        }
    }

    private func assertQuantity(_ identifier: String, equals expected: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: Timing.transition), "Missing quantity control: \(identifier)")
        XCTAssertEqual(button.value as? String, expected, identifier)
    }

    private func assertVisibleTerms(_ terms: [String], in app: XCUIApplication) {
        for term in terms {
            let text = app.staticTexts[term]
            reveal(text, in: app)
            XCTAssertEqual(text.label, term)
            assertReachable(text, in: app)
        }
    }

    private func tap(_ identifier: String, times: Int = 1, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        for _ in 0..<times {
            reveal(button, in: app)
            XCTAssertTrue(button.isEnabled, "Cannot tap disabled \(identifier)")
            button.tap()
        }
    }

    /// Use only native scrolling and accessible controls. No screen-coordinate
    /// shortcuts or retries of failed product actions can hide a regression.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        if isReachable(element, in: app) { return }
        let content = app.scrollViews.firstMatch
        if content.exists {
            for swipeUp in [true, false] {
                for _ in 0..<Layout.maximumScrolls {
                    if swipeUp { content.swipeUp() } else { content.swipeDown() }
                    if isReachable(element, in: app) { return }
                }
            }
        }
        assertReachable(element, in: app)
    }

    private func isReachable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        element.exists && element.isHittable && app.frame.contains(element.frame)
    }

    private func assertReachable(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: Timing.transition), "Missing \(element.identifier): \(element.label)")
        XCTAssertTrue(element.isHittable, "Unreachable \(element.identifier): \(element.label)")
        XCTAssertTrue(app.frame.contains(element.frame), "Clipped \(element.identifier): \(element.frame)")
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
