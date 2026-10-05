import XCTest

/// Real New Game, CPU pacing and durable resume; no seeded gameplay positions.
/// The human places first; CPUs then place before the human's reverse setup.
@MainActor
final class BotProgressFlowTests: XCTestCase {
    private enum FlowID {
        static let status = "bot-progress.status"
        static let skip = "bot-progress.skip"
        static let retry = "bot-progress.retry"
        static let settings = "game.settings"
        static let settingsScreen = "screen.in-game-settings"
        static let settingsClose = "in-game-settings.close"
        static let dock = "board-decision.dock"
        static let confirm = "board-decision.confirm"
        static let cancel = "board-decision.cancel"
        static let buildingPreview = "board.building-preview"
        static let roadPreview = "board.road-preview"
        static let robberOrigin = "board.robber-origin"
        static let robberPreview = "board.robber-preview"
        static let discard = "discard.editor"
        static let discardSubmit = "discard.submit"
    }

    private static let screenTimeout: TimeInterval = 5
    private static let cpuTimeout: TimeInterval = 30
    private static let minimumTapDimension: CGFloat = 44
    // Three CPUs each place twice (12 actions) before reverse human setup.
    private static let holdSeconds: TimeInterval = 26
    private static let unconfirmedSeconds: TimeInterval = 2
    private static let naturalRollLimit = 3
    private static let boundarySignalLimit = 32
    private static let scrollAttemptLimit = 4
    private static let setupPairCount = 1
    private static let discardSelectionLimit = 30
    private static let resources = ["brick", "lumber", "ore", "grain", "wool"]

    func testCPUStatusSkipPausesStillRequiresHumanSetupConfirmation() {
        continueAfterFailure = false
        let app = launchRealCPUOpening()
        let skip = requireCPUStatus(in: app)
        attachScreenshot(in: app, name: "CPU status — real New Game after first human setup")
        skip.tap()

        confirmInitialPiece(in: app, prefix: "board.vertex.", previewID: FlowID.buildingPreview)
        // Settlement confirmation, not Skip, must be what opens the road dock.
        XCTAssertTrue(app.otherElements[FlowID.dock].exists)
        XCTAssertFalse(app.buttons[FlowID.confirm].isEnabled)
        XCTAssertFalse(app.buttons[FlowID.cancel].exists, "An initial road is mandatory")
        XCTAssertFalse(app.buttons[FlowID.skip].exists, "Skip must yield to the human")
        confirmInitialPiece(in: app, prefix: "board.edge.", previewID: FlowID.roadPreview)
    }

    func testSettingsHoldsCPUWorkAndNativeMenuResumeRestartsIt() {
        continueAfterFailure = false
        let app = launchRealCPUOpening()
        openSettings(in: app)
        let held = expectation(description: "settings outlast all opening CPU pauses")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdSeconds) { held.fulfill() }
        wait(for: [held], timeout: Self.holdSeconds + Self.screenTimeout)
        XCTAssertTrue(app.otherElements[FlowID.settingsScreen].exists)
        XCTAssertFalse(app.buttons[FlowID.skip].exists, "Hidden CPU commands must not remain accessible")
        app.buttons[FlowID.settingsClose].tap()
        XCTAssertTrue(app.buttons[FlowID.skip].waitForExistence(timeout: Self.screenTimeout),
                      "CPUs advanced behind settings instead of staying held")

        openSettings(in: app)
        quitToMenu(in: app)
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons[FlowID.skip].waitForExistence(timeout: Self.screenTimeout),
                      "Native Resume did not expose the pending CPU work")
        app.buttons[FlowID.skip].tap()
        assertMandatorySettlement(in: app)
    }

    func testColdResumeRestartsSavedCPUWorkWithoutSkippingHumanSetup() {
        continueAfterFailure = false
        let app = launchRealCPUOpening()
        // Freeze before termination so the saved position is genuinely CPU
        // owned, not a human placement reached during screenshot/query work.
        openSettings(in: app)
        coldResume(in: app)
        let skip = requireCPUStatus(in: app)
        attachScreenshot(in: app, name: "CPU status — cold resume of real opening")
        skip.tap()
        assertMandatorySettlement(in: app)
    }

    /// Dice are deliberately not injected. A missing seven is an explicit
    /// skip, never a green claim that a pending-seven resume was exercised.
    func testNaturallyPendingSevenSurvivesColdResumeWhenReachable() throws {
        continueAfterFailure = false
        let app = launchRealCPUOpening()
        for _ in 0..<Self.setupPairCount {
            XCTAssertTrue(app.buttons[FlowID.skip].waitForExistence(timeout: Self.cpuTimeout))
            app.buttons[FlowID.skip].tap()
            confirmInitialPiece(in: app, prefix: "board.vertex.", previewID: FlowID.buildingPreview)
            confirmInitialPiece(in: app, prefix: "board.edge.", previewID: FlowID.roadPreview)
        }
        for _ in 0..<Self.naturalRollLimit {
            let boundary = reachHumanBoundary(in: app)
            if boundary.isSeven { verifySevenResume(boundary, in: app); return }
            XCTAssertEqual(boundary, .roll, "Expected the human's next real dice roll")
            app.buttons["Roll Dice"].tap()
            let rolled = reachHumanBoundary(in: app)
            if rolled.isSeven { verifySevenResume(rolled, in: app); return }
            XCTAssertEqual(rolled, .end, "A non-seven roll must reach the human main turn")
            app.buttons["End Turn"].tap()
        }
        let finalBoundary = reachHumanBoundary(in: app)
        if finalBoundary.isSeven { verifySevenResume(finalBoundary, in: app); return }
        throw XCTSkip("No human seven obligation arose within three real human rolls and their CPU rounds.")
    }

    // MARK: - Real match configuration

    /// Set Slow through the real settings screen, then finish the first human
    /// settlement/road. The CPU phase is reached by actual play, not fixtures.
    private func launchRealCPUOpening() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        openNewGame(in: app)
        tapNewGameChoice("As Shown", in: app)
        app.buttons["new-game.start"].tap()
        openSettings(in: app)
        app.buttons["Slow"].tap()
        app.buttons["No Limit"].tap()
        XCTAssertTrue(app.buttons["Slow"].isSelected)
        app.buttons[FlowID.settingsClose].tap()
        confirmInitialPiece(in: app, prefix: "board.vertex.", previewID: FlowID.buildingPreview)
        confirmInitialPiece(in: app, prefix: "board.edge.", previewID: FlowID.roadPreview)
        return app
    }

    private func openNewGame(in app: XCUIApplication) {
        let newGame = app.buttons["main-menu.new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: Self.screenTimeout))
        newGame.tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: Self.screenTimeout))
    }

    private func tapNewGameChoice(_ title: String, in app: XCUIApplication) {
        let button = app.buttons[title]
        for _ in 0..<Self.scrollAttemptLimit where !button.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(button.isHittable, "New Game choice is unreachable: \(title)")
        button.tap()
    }

    private func openSettings(in app: XCUIApplication) {
        let settings = app.buttons[FlowID.settings]
        XCTAssertTrue(settings.waitForExistence(timeout: Self.screenTimeout))
        settings.tap()
        XCTAssertTrue(app.otherElements[FlowID.settingsScreen].waitForExistence(timeout: Self.screenTimeout))
    }

    private func quitToMenu(in app: XCUIApplication) {
        app.buttons["in-game-settings.quit"].tap()
        let confirm = app.buttons["Main Menu"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.screenTimeout))
        confirm.tap()
        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: Self.screenTimeout))
        XCTAssertTrue(app.buttons["main-menu.resume"].exists, "Quit must retain the real save")
    }

    private func coldResume(in app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let resume = app.buttons["main-menu.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: Self.screenTimeout))
        XCTAssertFalse(app.otherElements["screen.game"].exists, "Cold launch must wait for Resume")
        resume.tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: Self.screenTimeout))
    }

    // MARK: - CPU status and mandatory placement

    private func requireCPUStatus(in app: XCUIApplication) -> XCUIElement {
        let skip = app.buttons[FlowID.skip]
        XCTAssertTrue(skip.waitForExistence(timeout: Self.screenTimeout), "Missing CPU Skip pauses control")
        XCTAssertTrue(app.otherElements[FlowID.status].exists, "Missing CPU status row")
        XCTAssertTrue(skip.isEnabled)
        XCTAssertTrue(skip.isHittable)
        XCTAssertGreaterThanOrEqual(skip.frame.height, Self.minimumTapDimension)
        XCTAssertGreaterThanOrEqual(skip.frame.width, Self.minimumTapDimension)
        XCTAssertFalse(app.buttons[FlowID.retry].exists, "A normal CPU opening must not be failed")
        return skip
    }

    private func assertMandatorySettlement(in app: XCUIApplication) {
        let confirm = app.buttons[FlowID.confirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.cpuTimeout), "Skip did not yield to human setup")
        XCTAssertTrue(app.otherElements[FlowID.dock].exists)
        XCTAssertFalse(confirm.isEnabled, "Unselected settlement must still require a legal target")
        XCTAssertFalse(app.buttons[FlowID.cancel].exists, "Opening placement cannot be cancelled")
        XCTAssertFalse(app.buttons[FlowID.skip].exists)
        XCTAssertTrue(boardTargets(in: app, prefix: "board.vertex.").firstMatch.exists)
    }

    private func confirmInitialPiece(in app: XCUIApplication, prefix: String, previewID: String) {
        let confirm = app.buttons[FlowID.confirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.cpuTimeout))
        XCTAssertFalse(confirm.isEnabled)
        let targets = boardTargets(in: app, prefix: prefix)
        XCTAssertTrue(targets.firstMatch.waitForExistence(timeout: Self.screenTimeout))
        let target = targets.allElementsBoundByIndex.first { $0.isHittable }
        guard let target else { return XCTFail("No tappable legal setup target: \(prefix)") }
        target.tap()
        let preview = app.otherElements[previewID]
        XCTAssertTrue(preview.waitForExistence(timeout: Self.screenTimeout))
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertFalse(app.buttons[FlowID.cancel].exists)
        assertRemainsUnconfirmed(preview)
        confirm.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: Self.screenTimeout), "Confirm did not commit placement")
    }

    private func assertRemainsUnconfirmed(_ preview: XCUIElement) {
        let autoCommitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [autoCommitted], timeout: Self.unconfirmedSeconds), .timedOut,
                       "CPU Skip or staging bypassed explicit human confirmation")
    }

    private func boardTargets(in app: XCUIApplication, prefix: String) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
    }

    private func attachScreenshot(in app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Opportunistic, unseeded seven

    private enum HumanBoundary: Equatable {
        case roll, end, discard, robber
        var isSeven: Bool { self == .discard || self == .robber }
    }

    /// Skip only CPU viewing delays and explicitly decline real offers. Stop
    /// on the first human obligation; never play their discard or robber here.
    private func reachHumanBoundary(in app: XCUIApplication) -> HumanBoundary {
        for _ in 0..<Self.boundarySignalLimit {
            if app.staticTexts[FlowID.discard].exists { return .discard }
            if app.otherElements[FlowID.robberOrigin].exists { return .robber }
            if app.buttons["Roll Dice"].exists { return .roll }
            if app.buttons["End Turn"].exists { return .end }
            if app.buttons["incoming-trade.reject"].exists {
                app.buttons["incoming-trade.reject"].tap()
            } else if app.buttons[FlowID.skip].exists {
                app.buttons[FlowID.skip].tap()
                // Once tapped, wait for a human/offer boundary rather than
                // tapping the disappearing Skip control a second time.
                waitForBoundarySignal(in: app, includeCPU: false)
                continue
            }
            waitForBoundarySignal(in: app, includeCPU: true)
        }
        XCTFail("Too many incoming-offer interruptions to reach the human")
        return .roll
    }

    private func waitForBoundarySignal(in app: XCUIApplication, includeCPU: Bool) {
        var identifiers = [FlowID.discard, FlowID.robberOrigin, "incoming-trade.reject", FlowID.retry]
        if includeCPU { identifiers.append(FlowID.skip) }
        // Turn actions have shipping labels but no dedicated IDs. All other
        // witnesses use existing IDs; no app instrumentation is introduced.
        let signals = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@ OR label IN %@", identifiers, ["Roll Dice", "End Turn"]
        ))
        XCTAssertTrue(signals.firstMatch.waitForExistence(timeout: Self.cpuTimeout),
                      "CPU work stalled before a playable human boundary")
        XCTAssertFalse(app.buttons[FlowID.retry].exists, "CPU policy failed during real play")
    }

    private func verifySevenResume(_ boundary: HumanBoundary, in app: XCUIApplication) {
        attachScreenshot(in: app, name: "Naturally pending seven — before cold resume")
        coldResume(in: app)
        let obligation = boundary == .discard ? app.staticTexts[FlowID.discard] : app.otherElements[FlowID.robberOrigin]
        XCTAssertTrue(obligation.waitForExistence(timeout: Self.cpuTimeout), "Cold resume lost the real seven obligation")
        XCTAssertFalse(app.buttons[FlowID.skip].exists, "Human seven decisions must outrank CPU Skip")
        XCTAssertFalse(app.buttons["Roll Dice"].exists)
        XCTAssertFalse(app.buttons["End Turn"].exists)
        attachScreenshot(in: app, name: "Naturally pending seven — cold restored obligation")
        if boundary == .discard { confirmRealDiscard(in: app) } else { confirmRealRobber(in: app) }
    }

    private func confirmRealDiscard(in app: XCUIApplication) {
        let submit = app.buttons[FlowID.discardSubmit]
        XCTAssertFalse(submit.isEnabled, "Cold resume must restore an obligation, not submit a draft")
        for _ in 0..<Self.discardSelectionLimit where !submit.isEnabled {
            let resource = Self.resources.map { app.buttons["discard.hand.\($0)"] }.first { $0.isEnabled }
            guard let resource else { return XCTFail("Pending discard offers no legal card to select") }
            resource.tap()
        }
        XCTAssertTrue(submit.isEnabled)
        assertRemainsUnconfirmed(app.staticTexts[FlowID.discard])
        submit.tap()
        XCTAssertTrue(app.staticTexts[FlowID.discard].waitForNonExistence(timeout: Self.screenTimeout))
    }

    private func confirmRealRobber(in app: XCUIApplication) {
        let targets = boardTargets(in: app, prefix: "board.tile.")
        guard let target = targets.allElementsBoundByIndex.first(where: { $0.isHittable }) else {
            return XCTFail("Restored seven offers no legal robber destination")
        }
        target.tap()
        let victims = boardTargets(in: app, prefix: "robber.victim.")
        if victims.firstMatch.exists { victims.firstMatch.tap() }
        let preview = app.otherElements[FlowID.robberPreview]
        XCTAssertTrue(preview.waitForExistence(timeout: Self.screenTimeout))
        XCTAssertTrue(app.buttons[FlowID.confirm].isEnabled)
        assertRemainsUnconfirmed(preview)
        app.buttons[FlowID.confirm].tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: Self.screenTimeout))
    }
}
