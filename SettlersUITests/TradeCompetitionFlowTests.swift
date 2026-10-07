import XCTest

/// Both native journeys tap the actual incoming Accept control. QA chooses
/// only a conserved pre-proposal baseline and policy seed; the rival evaluates
/// the offer using its real seated policy and the normal checkpoint commits.
@MainActor
final class TradeCompetitionFlowTests: XCTestCase {
    private enum Timing {
        static let launch: TimeInterval = 10
        static let transition: TimeInterval = 5
        static let cpu: TimeInterval = 30
    }

    private enum FlowID {
        static let settingsScreen = "screen.in-game-settings"
        static let settingsClose = "in-game-settings.close"
        static let skip = "bot-progress.skip"
        static let retry = "bot-progress.retry"
        static let accept = "incoming-trade.accept"
        static let reject = "incoming-trade.reject"
        static let notice = "gameplay.notice"
    }

    private static let resources = ["brick", "lumber", "ore", "grain", "wool"]
    private static let boundaryLimit = 24

    func testHumanWinsAgainstAWillingRecipientAndContinuesAfterTheReceipt() {
        let app = reachOffer(winner: "human")
        defer { app.terminate() }
        assertHand(["grain": 1], in: app)
        app.buttons[FlowID.accept].tap()
        XCTAssertTrue(app.staticTexts["Trade complete"].waitForExistence(timeout: Timing.transition))
        XCTAssertTrue(app.staticTexts["1 Grain"].exists)
        XCTAssertTrue(app.staticTexts["4 Brick"].exists)
        retainScreenshot("Human wins the actual competing acceptance", in: app)
        app.buttons["Close trade"].tap()
        XCTAssertFalse(app.staticTexts["Trade complete"].exists)
        assertHand(["brick": 4], in: app)
        reachOwnTurn(in: app)
        retainScreenshot("Human winner continues to their next dice roll", in: app)
    }

    func testActualExpertRivalWinsAfterColdResumeWithoutChangingTheHumanHand() {
        let app = reachOffer(winner: "rival", extra: ["-qaNavalExpert"])
        defer { app.terminate() }
        assertHand(["grain": 1], in: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"] // Resume the durable proposal without rebuilding the fixture.
        app.launch()
        let resume = app.buttons["main-menu.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: Timing.launch))
        resume.tap()
        XCTAssertTrue(app.buttons[FlowID.accept].waitForExistence(timeout: Timing.transition))
        assertHand(["grain": 1], in: app)
        app.buttons[FlowID.accept].tap()
        XCTAssertTrue(app.buttons[FlowID.accept].waitForNonExistence(timeout: Timing.transition))
        XCTAssertFalse(app.staticTexts["Trade complete"].exists, "The losing recipient cannot receive a completed exchange receipt")
        let news = app.otherElements[FlowID.notice]
        XCTAssertTrue(news.waitForExistence(timeout: Timing.transition))
        XCTAssertEqual(news.label, "Alexander traded with Ramesses")
        retainScreenshot("Cold-resumed actual rival wins; human keeps their Grain", in: app)
        assertHand(["grain": 1], in: app)
        reachOwnTurn(in: app)
        retainScreenshot("Rival winner continues to the human's next dice roll", in: app)
    }

    private func reachOffer(winner: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowPauseMenu",
                               "-qaNavalMode", "-qaThreePlayerTable", "-qaBotTradeAfterPause",
                               "-qaTradeCompetitionWinner=\(winner)"] + extra
        app.launch()
        XCTAssertTrue(app.otherElements[FlowID.settingsScreen].waitForExistence(timeout: Timing.launch))
        app.buttons["Slow"].tap()
        app.buttons["No Limit"].tap()
        XCTAssertTrue(app.buttons["No Limit"].isSelected)
        app.buttons[FlowID.settingsClose].tap()
        let skip = app.buttons[FlowID.skip]
        XCTAssertTrue(skip.waitForExistence(timeout: Timing.transition))
        skip.tap() // The ordinary runner must choose and commit the proposal.
        XCTAssertTrue(app.buttons[FlowID.accept].waitForExistence(timeout: Timing.transition))
        XCTAssertFalse(app.staticTexts["Trade complete"].exists)
        XCTAssertFalse(app.otherElements[FlowID.notice].exists)
        retainScreenshot("Real funded competing offer before any human answer", in: app)
        return app
    }

    /// Skip only viewing pauses and decline any subsequent real offers. Reaching
    /// the ordinary Roll Dice control proves the accepted proposal did not park
    /// the runner or leave its queued trade bookkeeping behind.
    private func reachOwnTurn(in app: XCUIApplication) {
        for _ in 0..<Self.boundaryLimit {
            if app.buttons["Roll Dice"].exists { return }
            XCTAssertFalse(app.buttons[FlowID.retry].exists, "The policy loop failed after accepting the offer")
            var includeCPU = true
            if app.buttons[FlowID.reject].exists {
                app.buttons[FlowID.reject].tap()
            } else if app.buttons[FlowID.skip].exists {
                app.buttons[FlowID.skip].tap()
                includeCPU = false // One Skip cancels the entire current CPU run's viewing pauses.
            }
            let identifiers = [FlowID.reject, FlowID.retry] + (includeCPU ? [FlowID.skip] : [])
            let signals = app.descendants(matching: .any).matching(NSPredicate(
                format: "identifier IN %@ OR label == %@", identifiers, "Roll Dice"
            ))
            XCTAssertTrue(signals.firstMatch.waitForExistence(timeout: Timing.cpu), "Trade resolution stalled the next playable turn")
        }
        XCTFail("Too many bot transitions before the human's next dice roll")
    }

    private func assertHand(_ expected: [String: Int], in app: XCUIApplication) {
        for resource in Self.resources {
            let value = app.otherElements["human-resource.\(resource)"]
            XCTAssertTrue(value.waitForExistence(timeout: Timing.transition))
            XCTAssertEqual(value.value as? String, "\(expected[resource, default: 0])", resource)
        }
    }

    private func retainScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
