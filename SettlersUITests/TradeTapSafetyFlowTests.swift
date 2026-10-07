import XCTest

/// Skip cancels a genuine CPU viewing pause. The ensuing proposal is selected
/// by a deterministic QA policy but committed through the ordinary session,
/// checkpoint and human-offer policy. Stale physical touches must not become
/// an answer merely because the fixed command row changed its occupant.
@MainActor
final class TradeTapSafetyFlowTests: XCTestCase {
    private enum Timing {
        static let launch: TimeInterval = 10
        static let transition: TimeInterval = 5
        static let heldPastTimer: TimeInterval = 16
        static let expiry: TimeInterval = 20
    }

    private enum FlowID {
        static let skip = "bot-progress.skip"
        static let accept = "incoming-trade.accept"
        static let reject = "incoming-trade.reject"
        static let review = "incoming-trade.review"
        static let reviewBack = "incoming-trade.review.close"
        static let settings = "game.settings"
        static let settingsScreen = "screen.in-game-settings"
        static let settingsClose = "in-game-settings.close"
        static let command = "game.command-row"
    }

    private static let resources = ["brick", "lumber", "ore", "grain", "wool"]
    private static let repeatedTouches = 8
    private static let minimumHitDimension: CGFloat = 44
    private static let edgeInset: CGFloat = 4
    private static let maximumTextArguments = [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
    ]

    func testRepeatedSkipTouchesCannotAcceptARealNavalOffer() {
        let boundary = reachOffer(extra: ["-qaNavalMode"])
        defer { boundary.app.terminate() }
        repeatTouches(at: center(of: boundary.skipFrame), in: boundary.app)
        assertOfferUnanswered(grain: 1, in: boundary.app)
        assertAnswerRegionsSeparate(from: boundary.skipFrame, in: boundary.app)
        retainScreenshot("Real offer remains unanswered after repeated Skip-coordinate taps", in: boundary.app)
        boundary.app.buttons[FlowID.accept].tap()
        XCTAssertTrue(boundary.app.staticTexts["Trade complete"].waitForExistence(timeout: Timing.transition))
        XCTAssertTrue(boundary.app.staticTexts["1 Grain"].exists)
        XCTAssertTrue(boundary.app.staticTexts["1 Brick"].exists)
        boundary.app.buttons["Close trade"].tap()
        XCTAssertFalse(boundary.app.staticTexts["Trade complete"].exists)
        assertHand(["brick": 1], in: boundary.app)
    }

    /// Every edge of the former button is exercised, not only its center.
    /// The three-seat modifier and maximum user text run the narrower density.
    func testSkipPaddingCannotDeclineAnOfferAtMaximumText() {
        let boundary = reachOffer(extra: ["-qaThreePlayerTable"] + Self.maximumTextArguments)
        defer { boundary.app.terminate() }
        tapPerimeter(of: boundary.skipFrame, in: boundary.app)
        assertOfferUnanswered(grain: 1, in: boundary.app)
        assertAnswerRegionsSeparate(from: boundary.skipFrame, in: boundary.app)
        boundary.app.buttons[FlowID.reject].tap()
        XCTAssertTrue(boundary.app.buttons[FlowID.reject].waitForNonExistence(timeout: Timing.transition))
        XCTAssertFalse(boundary.app.staticTexts["Trade complete"].exists)
        assertHand(["grain": 1], in: boundary.app)
    }

    func testWideOfferStillRequiresReviewAndHoldsWhileReading() {
        let boundary = reachOffer(extra: ["-qaNavalMode", "-qaBundleOffer"] + Self.maximumTextArguments,
                                  timer: "15s")
        defer { boundary.app.terminate() }
        repeatTouches(at: center(of: boundary.skipFrame), in: boundary.app, count: 2)
        assertOfferUnanswered(grain: 3, in: boundary.app, review: true)
        assertAnswerRegionsSeparate(from: boundary.skipFrame, in: boundary.app)
        boundary.app.buttons[FlowID.review].tap()
        XCTAssertTrue(boundary.app.buttons[FlowID.reviewBack].waitForExistence(timeout: Timing.transition))
        waitFor(Timing.heldPastTimer)
        XCTAssertTrue(boundary.app.buttons[FlowID.accept].exists, "Review must hold the actual 15-second timer")
        XCTAssertFalse(boundary.app.staticTexts["Trade complete"].exists)
        boundary.app.buttons[FlowID.reviewBack].tap()
        assertOfferUnanswered(grain: 3, in: boundary.app, review: true)
        boundary.app.buttons[FlowID.reject].tap()
        XCTAssertTrue(boundary.app.buttons[FlowID.reject].waitForNonExistence(timeout: Timing.transition))
        assertHand(["grain": 3], in: boundary.app)
    }

    func testAnUnansweredOfferCanStillExpireWithoutExchangingCards() {
        let boundary = reachOffer(timer: "15s")
        defer { boundary.app.terminate() }
        assertAnswerRegionsSeparate(from: boundary.skipFrame, in: boundary.app)
        XCTAssertTrue(boundary.app.buttons[FlowID.accept].waitForNonExistence(timeout: Timing.expiry))
        XCTAssertFalse(boundary.app.staticTexts["Trade complete"].exists)
        assertHand(["grain": 1], in: boundary.app)
    }

    func testRepeatedSkipTouchesRemainUnansweredThroughColdResumeAndRestart() {
        let boundary = reachOffer(extra: ["-qaNavalMode"])
        let app = boundary.app
        defer { app.terminate() }
        repeatTouches(at: center(of: boundary.skipFrame), in: app)
        assertOfferUnanswered(grain: 1, in: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: Timing.launch))
        app.buttons["main-menu.resume"].tap()
        assertOfferUnanswered(grain: 1, in: app)
        repeatTouches(at: center(of: boundary.skipFrame), in: app)
        assertOfferUnanswered(grain: 1, in: app)
        app.buttons[FlowID.settings].tap()
        app.buttons["in-game-settings.restart"].tap()
        XCTAssertTrue(app.buttons["Restart"].waitForExistence(timeout: Timing.transition))
        app.buttons["in-game-settings.restart-confirm"].tap()
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Timing.transition))
        XCTAssertFalse(confirm.isEnabled, "A new match must still await its own settlement selection")
        XCTAssertFalse(app.buttons[FlowID.accept].exists)
        XCTAssertFalse(app.staticTexts["Trade complete"].exists)
        assertHand([:], in: app)
    }

    private struct Boundary {
        let app: XCUIApplication
        let skipFrame: CGRect
    }

    /// Settings is already covering the explicit QA baseline at launch, so
    /// no guessed delay can race the proposal while pacing is configured.
    /// Once closed, capture the physical Skip rectangle and immediately tap.
    private func reachOffer(extra: [String] = [], timer: String = "No Limit") -> Boundary {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowPauseMenu",
                               "-qaBotTradeAfterPause"] + extra
        app.launch()
        XCTAssertTrue(app.otherElements[FlowID.settingsScreen].waitForExistence(timeout: Timing.launch))
        app.buttons["Slow"].tap()
        app.buttons[timer].tap()
        XCTAssertTrue(app.buttons["Slow"].isSelected)
        app.buttons[FlowID.settingsClose].tap()
        let skip = app.buttons[FlowID.skip]
        XCTAssertTrue(skip.waitForExistence(timeout: Timing.transition))
        let frame = skip.frame
        XCTAssertGreaterThanOrEqual(frame.width, Self.minimumHitDimension)
        XCTAssertGreaterThanOrEqual(frame.height, Self.minimumHitDimension)
        retainScreenshot("CPU viewing pause with separate Skip target", in: app)
        physicalPoint(center(of: frame), in: app).tap()
        let responseID = extra.contains("-qaBundleOffer") ? FlowID.review : FlowID.accept
        XCTAssertTrue(app.buttons[responseID].waitForExistence(timeout: Timing.transition),
                      "The real CPU proposal must replace the viewing pause")
        return Boundary(app: app, skipFrame: frame)
    }

    private func assertOfferUnanswered(grain: Int, in app: XCUIApplication, review: Bool = false) {
        let action = app.buttons[review ? FlowID.review : FlowID.accept]
        XCTAssertTrue(action.waitForExistence(timeout: Timing.transition),
                      "A stale Skip touch answered or opened the real offer")
        XCTAssertTrue(app.buttons[FlowID.reject].isHittable)
        XCTAssertFalse(app.buttons[FlowID.skip].exists, "Human trade decisions must own the command row")
        XCTAssertFalse(app.buttons[FlowID.reviewBack].exists, "Only a deliberate Review tap may open full terms")
        XCTAssertFalse(app.staticTexts["Trade complete"].exists, "A stale Skip touch must never commit a trade")
        assertHand(["grain": grain], in: app)
    }

    private func assertAnswerRegionsSeparate(from skipFrame: CGRect, in app: XCUIApplication) {
        for identifier in [FlowID.accept, FlowID.reject, FlowID.review] {
            let answer = app.buttons[identifier]
            guard answer.exists else { continue }
            XCTAssertFalse(skipFrame.intersects(answer.frame),
                           "Skip's complete hit rectangle must be disjoint from \(identifier)")
            XCTAssertGreaterThanOrEqual(answer.frame.width, Self.minimumHitDimension)
            XCTAssertGreaterThanOrEqual(answer.frame.height, Self.minimumHitDimension)
            XCTAssertTrue(answer.isHittable)
            XCTAssertTrue(app.frame.contains(answer.frame))
        }
        XCTAssertTrue(app.otherElements[FlowID.command].frame.contains(skipFrame),
                      "The fixed command row must not move when an offer appears")
    }

    private func assertHand(_ expected: [String: Int], in app: XCUIApplication) {
        for resource in Self.resources {
            let value = app.otherElements["human-resource.\(resource)"]
            XCTAssertTrue(value.waitForExistence(timeout: Timing.transition))
            XCTAssertEqual(value.value as? String, "\(expected[resource, default: 0])", resource)
        }
    }

    private func center(of frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    private func physicalPoint(_ point: CGPoint, in app: XCUIApplication) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    private func repeatTouches(at point: CGPoint, in app: XCUIApplication, count: Int? = nil) {
        let coordinate = physicalPoint(point, in: app)
        for _ in 0..<(count ?? Self.repeatedTouches) { coordinate.tap() }
    }

    private func tapPerimeter(of frame: CGRect, in app: XCUIApplication) {
        let inset = frame.insetBy(dx: Self.edgeInset, dy: Self.edgeInset)
        for point in [CGPoint(x: inset.minX, y: inset.minY), CGPoint(x: inset.maxX, y: inset.minY),
                      CGPoint(x: inset.minX, y: inset.maxY), CGPoint(x: inset.maxX, y: inset.maxY)] {
            physicalPoint(point, in: app).tap()
        }
    }

    private func waitFor(_ seconds: TimeInterval) {
        let elapsed = expectation(description: "Real offer reading interval elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { elapsed.fulfill() }
        wait(for: [elapsed], timeout: seconds + Timing.transition)
    }

    private func retainScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
