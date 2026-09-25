import XCTest

/// Exercises the modal boundaries most likely to make a playable game stall.
@MainActor
final class GameplayBoundaryFlowTests: XCTestCase {
    /// Debugging repro for Jake's "the game just stops advancing" report -
    /// "sometimes it happens if I close the game" in particular.
    ///
    /// Hypothesis: `GameView.seenTradeOfferIDs` is pre-seeded with every
    /// currently-pending offer ID in `.onAppear` (meant to stop a *previously
    /// shown* offer from replaying when the view is recreated), but that
    /// blanket seeding also swallows an offer that was pending yet NEVER
    /// actually shown as a card before the view went away and came back -
    /// so `handleTradeOffersChange` will never queue it (its `where` clause
    /// excludes anything already in `seenTradeOfferIDs`), and no card ever
    /// appears to let the human answer it. Meanwhile
    /// `GameViewModel.openIncomingOffer` (the bot loop's own gate) is a live
    /// computed property with no such bookkeeping, so it keeps seeing the
    /// same pending offer and the bot loop stays parked on it forever - a
    /// permanent deadlock with nothing on screen to explain it.
    ///
    /// A real `app.terminate()` + relaunch (the `testColdLaunchResumesThe-
    /// ConfiguredMatch` pattern in `MainMenuFlowTests`), not a same-process
    /// main-menu round trip - the QA flag that seeds the offer would
    /// otherwise still be present in `ProcessInfo.arguments` on the second
    /// appearance and re-seed it directly into `incomingOfferQueue`,
    /// bypassing `seenTradeOfferIDs` entirely and masking the exact bug
    /// this is trying to catch (measured: an earlier same-process version of
    /// this test passed for that wrong reason). The second launch omits
    /// `-qaShowIncomingOffer` so nothing re-seeds it - the only thing
    /// standing the offer back up is whatever `GameView` does with the
    /// still-pending offer already on disk.
    func testIncomingOfferSurvivesAppRelaunch() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaFastForwardToRollDice", "-qaShowIncomingOffer"])

        XCTAssertTrue(app.buttons["incoming-trade.accept"].waitForExistence(timeout: 15),
                      "QA fixture did not seed a visible incoming offer")

        // Leave it unanswered and really quit - `qaPersistCurrentState`
        // (called right after seeding, see GameView.swift) is what makes
        // this offer still be there on the next launch.
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let resume = app.buttons["main-menu.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))

        // The offer is still genuinely pending in engine state (a cold
        // relaunch only replaces `hasStartedThisSession`'s starting value,
        // never touches `state.pendingTradeOffers`) - if the card doesn't
        // come back, the human has no way to answer it and the bot loop
        // (gated on that same still-pending offer) can never proceed either.
        XCTAssertTrue(app.buttons["incoming-trade.accept"].waitForExistence(timeout: 5),
                      "incoming offer vanished after relaunching - the game is now stuck " +
                      "with no way to answer a still-pending offer")
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
        // No replay here, and that is the assertion. `-qaShowEndGame` forces
        // the win through `qaForceHumanWin`, which replaces the active match
        // with a fresh one carrying no moves - so its id names a recording
        // that was never written, and the button must stay away rather than
        // offer a replay that cannot open. The button's presence is asserted
        // on the match that is really played, below.
        XCTAssertFalse(app.buttons["game-over.replay"].exists)

        let mainMenu = app.buttons["game-over.main-menu"]
        XCTAssertTrue(mainMenu.exists)
        mainMenu.tap()

        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["main-menu.resume"].exists)
    }

    /// Jake, 2026-09-25: "New game should be the same as restart game." It used
    /// to clear the match back to the menu, the same thing Main Menu does.
    func testGameOverNewGameStartsTheSameTableAgain() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaShowEndGame"])

        let newGame = app.buttons["game-over.new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5))
        newGame.tap()

        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5),
                      "New Game on the game-over screen must start a game, not return to the menu")
        XCTAssertFalse(app.otherElements["screen.main-menu"].exists)
        XCTAssertFalse(app.buttons["game-over.new-game"].exists)
    }

    func testRobberVictimChoicesExposeConfiguredIdentity() {
        continueAfterFailure = false
        let app = launch(arguments: [
            "-qaAutoStart", "-qaShowRobberVictimPicker",
        ])
        let victims = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "robber.victim.")
        )
        let first = victims.firstMatch
        let clear = app.buttons[BoardDecisionUITestID.clear]

        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(victims.count, 3)
        XCTAssertTrue(clear.waitForExistence(timeout: 2))
        XCTAssertTrue(first.label.contains("resource card"))
        XCTAssertGreaterThanOrEqual(first.label.split(separator: ",").count, 3,
                                    "victim must expose name, civilization, and public hand size")
        for victim in victims.allElementsBoundByIndex {
            XCTAssertLessThanOrEqual(
                victim.frame.maxX,
                clear.frame.minX,
                "a victim card must not paint or receive touches beneath pinned Clear"
            )
        }

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = "identity-rich-robber-victims"
        add(attachment)
    }

    /// Also the only place the win screen's "View Replay" shortcut can be
    /// tested, which is why it is asserted here rather than in a test of its
    /// own next to the rest of the replay coverage.
    ///
    /// Two reasons it has to be this test. A recording only exists for a game
    /// that was really played, and `-qaShowEndGame` does not qualify:
    /// `qaForceHumanWin` goes through `persistTestingPosition`, which replaces
    /// the active match with a fresh one carrying no moves, so its id names a
    /// recording that was never written. And a *second* `-qaPlayToEnd` test
    /// makes the gate red rather than slow - measured 2026-09-08, when this
    /// assertion did live in `GameHistoryFlowTests`: both full-match tests
    /// failed together at `GATE_TEST_WORKERS=2` and both passed serially, the
    /// starvation pattern `gate.sh`'s own header describes. One match, both
    /// claims.
    func testRealAutomatedMatchReachesGameOverAndClearsItsSave() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaPlayToEnd"])

        let newGame = app.buttons["game-over.new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: Self.completeMatchTimeoutSeconds))

        // Existence only, and deliberately no tap. What this test uniquely
        // proves is that the button resolves the recording of the match that
        // was actually just played - the win screen shows it only when
        // `GameLogStore.summary(for:)` finds a file for the active match id.
        // Opening and scrubbing a replay is covered five ways over in
        // `GameHistoryFlowTests` against a seeded fixture, and doing it here
        // as well made this - already the most expensive test in the suite -
        // build every frame of a full match while a second worker competed
        // for the machine. That timed out an unrelated UI query and turned
        // the gate red twice (2026-09-08) without a bug behind it.
        XCTAssertTrue(app.buttons["game-over.replay"].waitForExistence(timeout: 10),
                      "The win screen offered no replay of the match just played")

        app.buttons["game-over.main-menu"].tap()

        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["main-menu.resume"].exists)
    }

    /// Repro for Jake's "trade popup shouldn't close when a trade is
    /// proposed" report. Builds a real give/want offer and proposes it to
    /// the bots; the popup (its "Close" button, since the builder itself is
    /// swapped for a status banner once a bot has answered - see
    /// `TradePopupView.isShowingBotResponse`) must still be on screen
    /// afterward. `-qaFastForwardToRollDice` doesn't guarantee which
    /// resource the human ends up holding, so this reads the real hand back
    /// via `human-resource.*` (same identifiers `assertHumanResources` uses)
    /// rather than assuming one.
    func testTradePopupStaysOpenAfterProposingToBots() {
        continueAfterFailure = false
        let app = launch(arguments: ["-qaAutoStart", "-qaFastForwardToRollDice"])

        // The fixture autoplays setup, rolls, and resolves a possible seven,
        // so it always yields on Trade/Build/End Turn rather than a disabled
        // intermediate phase. Those are real paced moves, so wait on enabled
        // rather than existence: the action row renders before main turn.
        let tradeButton = app.buttons["Trade"]
        XCTAssertTrue(tradeButton.waitForExistence(timeout: 20))
        let becameEnabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                         evaluatedWith: tradeButton)
        wait(for: [becameEnabled], timeout: 20)
        tradeButton.tap()

        let closeButton = app.buttons["Close"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "trade popup did not open")

        guard let owned = ResourceName.allCases.first(where: { resourceCount($0, in: app) != "0" }) else {
            XCTFail("human hand was empty after fast-forwarding to roll dice - cannot build an offer")
            return
        }
        let wanted = ResourceName.allCases.first { $0 != owned }!

        app.buttons["trade.give.\(owned.rawValue)"].tap()
        app.buttons["trade.want.\(wanted.rawValue)"].tap()

        let propose = app.buttons["Propose to Bots"]
        XCTAssertTrue(propose.isEnabled)
        propose.tap()

        // Bot responses are evaluated synchronously (see
        // `GameViewModel.resolveHumanProposedTrade`), so no wait is needed
        // before this assertion - if the popup were going to close, it
        // would already have.
        XCTAssertTrue(app.buttons["Close"].exists, "trade popup closed after proposing to bots")

        // A bot may have accepted, in which case the pending-confirmation
        // banner (Decline/Confirm Trade) is showing instead of a resolved
        // outcome - decline it either way, deterministically reaching the
        // resolved-outcome state below regardless of which bot said what.
        if app.buttons["Decline"].waitForExistence(timeout: 2) {
            app.buttons["Decline"].tap()
        }

        // A resolved outcome gets a way back into the builder alongside
        // Close, so proposing again doesn't mean closing and reopening the
        // popup from scratch - see the "New Offer" button added next to
        // Close in TradePopupView.
        XCTAssertTrue(app.buttons["New Offer"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        attachment.name = "trade-outcome-with-new-offer"
        add(attachment)

        app.buttons["New Offer"].tap()
        XCTAssertTrue(app.buttons["Propose to Bots"].waitForExistence(timeout: 3),
                      "New Offer did not return to the builder")
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
    private static let completeMatchTimeoutSeconds: TimeInterval = 60

    private enum ResourceName: String, CaseIterable {
        case brick, lumber, ore, grain, wool
    }
}
