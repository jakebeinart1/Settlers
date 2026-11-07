import XCTest

/// Start from the shipping New Game screen and use the real board controls.
/// A seeded cover could look right while an ordinary seat change leaks the hand.
@MainActor
final class PassAndPlayFlowTests: XCTestCase {
    private let owner = "UI Tester"
    private let guest = "Mira"
    private let timeout: TimeInterval = 5
    private let settlementPrefix = "board.vertex."
    private let roadPrefix = "board.edge."

    func testMixedTableHandoffAndColdResumeProtectTheGuestHand() throws {
        continueAfterFailure = false
        let guest = "Willa Morgan"
        let app = openNewGame()
        setHuman(guest, at: 1, in: app)
        XCTAssertTrue(app.staticTexts["Pass & Play • 2 people • 2 AI"].exists)
        retain("Pass & Play – two people and two AI seats", in: app)
        startAsShown(in: app)

        claim(owner, in: app, capture: "Pass & Play – initial handoff to the owner")
        try placeOpeningPair(in: app)
        claim(guest, in: app, capture: "Pass & Play – private handoff with a maximum-length name")
        retain("Pass & Play – Willa's first placement", in: app)
        try place(settlementPrefix, in: app)
        XCTAssertTrue(targets(roadPrefix, in: app).firstMatch.waitForExistence(timeout: timeout))

        coldResume(in: app)
        claim(guest, in: app, capture: "Pass & Play – cold resume re-covers Willa's hand")
        XCTAssertFalse(targets(settlementPrefix, in: app).firstMatch.exists,
                       "Resuming must preserve the settlement and its pending road")
        retain("Pass & Play – committed settlement and pending road after resume", in: app)
        try place(roadPrefix, in: app)
    }

    func testAllHumanOpeningReachesTheNextPlayersRegularTurn() throws {
        continueAfterFailure = false
        let players = [owner, guest, "Hana", "Tariq"]
        let app = openNewGame()
        for (index, name) in players.enumerated().dropFirst() { setHuman(name, at: index, in: app) }
        XCTAssertTrue(app.staticTexts["Pass & Play • 4 people"].exists)
        startAsShown(in: app)

        var previous: String?
        for player in players + Array(players.reversed()) {
            if player != previous { claim(player, in: app) }
            try placeOpeningPair(in: app)
            previous = player
        }

        let roll = app.buttons["Roll Dice"]
        XCTAssertTrue(roll.waitForExistence(timeout: timeout))
        retain("Pass & Play – all human seats after real opening placements", in: app)
        roll.tap()
        try finishFirstRoll(in: app)
        app.buttons["End Turn"].tap()
        claim(guest, in: app, capture: "Pass & Play – handoff on an ordinary turn")
        XCTAssertTrue(roll.waitForExistence(timeout: timeout))
        assertHandVisible(in: app)
        retain("Pass & Play – Mira's regular turn after claiming", in: app)
    }

    func testRolledSevenPassesToTheOtherDiscarderAndBackToTheRoller() throws {
        let app = launchFixture("-qaPassAndPlayDiscard")
        claim("Player 1", in: app)
        app.buttons["Roll Dice"].tap()
        discard("brick", in: app)

        acknowledgeHandoff("Player 2", in: app, capture: "Pass & Play – off-turn discard handoff")
        let ore = app.buttons["discard.hand.ore"]
        XCTAssertTrue(ore.waitForExistence(timeout: timeout) && ore.isEnabled)
        XCTAssertFalse(app.buttons["discard.hand.brick"].isEnabled, "The previous person's hand was reused")
        retain("Pass & Play – second person's private discard editor", in: app)
        discard("ore", in: app)

        claim("Player 1", in: app, capture: "Pass & Play – return to the seven's roller")
        try resolveRobber(in: app)
        assertHandVisible(in: app)
        XCTAssertEqual(resource("brick", in: app), "4")
    }

    func testUnclaimedTableWaitsPrivatelyForLiveBotsToReachAHuman() {
        let app = launchFixture("-qaPassAndPlayBotWait")
        let waiting = app.staticTexts["Waiting for the next player"]
        XCTAssertTrue(waiting.waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["handoff.ready"].exists)
        assertPrivateContentHidden(in: app)
        retain("Pass & Play – covered while the AI plays", in: app)

        XCTAssertTrue(app.buttons["handoff.ready"].waitForExistence(timeout: 30))
        claim("Player 3", in: app, capture: "Pass & Play – AI returns control to a named person")
        XCTAssertTrue(app.buttons["Roll Dice"].waitForExistence(timeout: timeout))
        assertHandVisible(in: app)
    }

    func testGuestsActualWinningCityShowsANamedUnratedResult() throws {
        let app = launchFixture("-qaPassAndPlayWin")
        claim("Player 2", in: app)
        app.buttons["Build"].tap()
        let city = app.buttons["build.city"]
        XCTAssertTrue(city.waitForExistence(timeout: timeout) && city.isEnabled)
        city.tap()
        try place(settlementPrefix, in: app)

        let winner = app.staticTexts["game-over.cutscene.winner"]
        XCTAssertTrue(winner.waitForExistence(timeout: 20))
        XCTAssertEqual(winner.label, "Player 2 wins")
        retain("Pass & Play – the victory cutscene names the winner", in: app)
        XCTAssertTrue(app.staticTexts["PLAYER 2 WINS"].waitForExistence(timeout: 25))
        let receipt = app.staticTexts["game-over.unrated"]
        XCTAssertTrue(receipt.waitForExistence(timeout: timeout))
        XCTAssertTrue(receipt.label.contains("AI rating"))
        XCTAssertFalse(app.buttons["game-over.rating"].exists)
        retain("Pass & Play – guest wins with no solo AI Elo change", in: app)

        app.buttons["game-over.main-menu"].tap()
        XCTAssertTrue(app.buttons["main-menu.new-game"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["main-menu.resume"].exists, "The finished match remained resumable")
    }

    func testDirectedTradeReturnsToTheProposerAfterTheOtherPersonAccepts() {
        let app = launchFixture("-qaPassAndPlayTrade")
        claim("Player 1", in: app)
        sendDirectedTrade(in: app, capture: "Pass & Play – named recipient and directed trade terms")

        acknowledgeHandoff("Player 2", in: app, capture: "Pass & Play – private incoming trade handoff")
        assertNamed("incoming-trade.proposer", player: "Player 1", in: app)
        XCTAssertEqual(app.staticTexts["incoming-trade.give"].label, "You give 1 Grain")
        XCTAssertEqual(app.staticTexts["incoming-trade.receive"].label, "You receive 1 Lumber")
        retain("Pass & Play – the recipient reviews the offer", in: app)
        app.buttons["incoming-trade.accept"].tap()

        claim("Player 1", in: app)
        XCTAssertTrue(app.staticTexts["Player 2 accepted the trade"].waitForExistence(timeout: timeout))
        assertHandVisible(in: app)
        XCTAssertEqual(resource("lumber", in: app), "1")
        XCTAssertEqual(resource("grain", in: app), "1")
        retain("Pass & Play – trade accepted and control returned", in: app)
    }

    func testDecliningADirectedTradeReturnsControlWithoutChangingResources() {
        let app = launchFixture("-qaPassAndPlayTrade")
        claim("Player 1", in: app)
        sendDirectedTrade(in: app)
        acknowledgeHandoff("Player 2", in: app)
        let decline = app.buttons["incoming-trade.reject"]
        XCTAssertTrue(decline.waitForExistence(timeout: timeout) && decline.isHittable)
        decline.tap()

        claim("Player 1", in: app)
        XCTAssertTrue(app.staticTexts["Player 2 declined the trade"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["incoming-trade.accept"].exists)
        assertHandVisible(in: app)
        XCTAssertEqual(resource("lumber", in: app), "2")
        XCTAssertEqual(resource("grain", in: app), "0")
        retain("Pass & Play – trade declined and original hand preserved", in: app)
    }

    private func sendDirectedTrade(in app: XCUIApplication, capture: String? = nil) {
        app.buttons["Trade"].tap()
        let recipient = app.buttons["trade.recipient"]
        XCTAssertTrue(recipient.waitForExistence(timeout: timeout))
        recipient.tap()
        app.buttons["Player 2"].tap()
        app.buttons["trade.give.lumber"].tap()
        app.buttons["trade.want.grain"].tap()
        let send = app.buttons["Send offer"]
        XCTAssertTrue(send.exists && send.isEnabled)
        if let capture { retain(capture, in: app) }
        send.tap()
    }

    func testPrivateCardReceiptSurvivesColdResumeBehindTheOwnersHandoff() {
        let app = launchFixture("-qaPassAndPlayDevCard")
        claim("Player 2", in: app)
        app.buttons["Build"].tap()
        let buy = app.buttons["build.dev-card"]
        XCTAssertTrue(buy.waitForExistence(timeout: timeout) && buy.isEnabled)
        buy.tap()
        let monopoly = app.staticTexts["dev-cards.detail.monopoly"]
        XCTAssertTrue(monopoly.waitForExistence(timeout: timeout))

        coldResume(in: app)
        acknowledgeHandoff("Player 2", in: app, capture: "Pass & Play – resume keeps the purchased card covered")
        XCTAssertTrue(monopoly.waitForExistence(timeout: timeout))
        retain("Pass & Play – the purchaser sees the resumed card receipt", in: app)
        app.buttons["dev-cards.continue"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: timeout))

        coldResume(in: app)
        claim("Player 2", in: app)
        XCTAssertFalse(monopoly.exists, "The acknowledged receipt must stay closed after another resume")
        assertHandVisible(in: app)
        XCTAssertEqual(resource("ore", in: app), "0")
    }

    func testVoyagesHarvestPassesToTheIslandOwnerThenBackToTheRoller() {
        let app = launchFixture("-qaPassAndPlayHarvest")
        claim("Player 2", in: app)
        app.buttons["Roll Dice"].tap()
        acknowledgeHandoff("Player 1", in: app, capture: "Pass & Play – off-turn Voyages harvest handoff")
        let ore = app.buttons["naval.resource.ore"]
        XCTAssertTrue(ore.waitForExistence(timeout: timeout))
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 1 resource"))
        ore.tap()
        let collect = app.buttons["naval.resource.confirm"]
        XCTAssertTrue(collect.exists && collect.isEnabled)
        retain("Pass & Play – Voyages island owner chooses the harvest", in: app)
        collect.tap()

        claim("Player 2", in: app, capture: "Pass & Play – Voyages return to the roller")
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["naval.resource.choice"].exists)
    }

    private func openNewGame() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        let newGame = app.buttons["main-menu.new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: timeout))
        newGame.tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: timeout))
        return app
    }

    private func launchFixture(_ flag: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", flag]
        app.launch()
        return app
    }

    private func setHuman(_ name: String, at index: Int, in app: XCUIApplication) {
        let role = app.buttons["new-game.seat-kind.\(index).human"]
        revealSetupControl(role, in: app)
        role.tap()
        let field = app.textFields["new-game.seat-name.\(index)"]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        revealSetupControl(field, in: app)
        field.tap()
        let previous = (field.value as? String) ?? ""
        if !previous.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(name)
        field.typeText("\n")
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: timeout))
        XCTAssertEqual(field.value as? String, name)
    }

    private func startAsShown(in app: XCUIApplication) {
        let asShown = app.buttons["As Shown"]
        revealSetupControl(asShown, in: app)
        asShown.tap()
        let start = app.buttons["new-game.start"]
        XCTAssertTrue(start.isHittable && start.isEnabled)
        start.tap()
    }

    private func revealSetupControl(_ control: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<4 where !control.isHittable { scroll.swipeUp() }
        XCTAssertTrue(control.isHittable)
    }

    private func claim(_ player: String, in app: XCUIApplication, capture: String? = nil) {
        acknowledgeHandoff(player, in: app, capture: capture)
        assertNamed("game.local-turn", player: player, in: app)
    }

    private func assertHandVisible(in app: XCUIApplication) {
        XCTAssertTrue(app.otherElements["human-resource.ore"].waitForExistence(timeout: timeout),
                      "The claimed reader must regain access to their own hand")
    }

    private func acknowledgeHandoff(_ player: String, in app: XCUIApplication, capture: String? = nil) {
        let ready = app.buttons["handoff.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: timeout), "Handoff to \(player)")
        assertNamed("handoff.recipient", player: player, in: app)
        XCTAssertTrue(app.frame.contains(ready.frame) && ready.isHittable)
        assertPrivateContentHidden(in: app)
        if let capture { retain(capture, in: app) }

        ready.tap()
        XCTAssertTrue(ready.waitForNonExistence(timeout: timeout))
    }

    private func assertNamed(_ identifier: String, player: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), identifier)
        XCTAssertTrue(element.label.localizedCaseInsensitiveContains(player),
                      "\(identifier) should name \(player), got \(element.label)")
    }

    private func assertPrivateContentHidden(in app: XCUIApplication) {
        let resources = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "human-resource."))
        XCTAssertFalse(resources.firstMatch.exists, "The unclaimed hand leaked through accessibility")
        let privateCards = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "dev-cards.detail."))
        XCTAssertFalse(privateCards.firstMatch.exists, "The covered card identity leaked through accessibility")
        for identifier in ["dev-cards.view-hand", "board-decision.confirm", "Roll Dice", "discard.submit",
                           "incoming-trade.accept", "naval.resource.confirm"] {
            XCTAssertFalse(app.buttons[identifier].exists, "The covered player can still reach \(identifier)")
        }
        XCTAssertFalse(targets(settlementPrefix, in: app).firstMatch.exists)
        XCTAssertFalse(targets(roadPrefix, in: app).firstMatch.exists)
    }

    private func discard(_ resource: String, in app: XCUIApplication) {
        let card = app.buttons["discard.hand.\(resource)"]
        XCTAssertTrue(card.waitForExistence(timeout: timeout) && card.isEnabled)
        XCTAssertEqual(card.value as? String, "8 remaining, 0 selected")
        let submit = app.buttons["discard.submit"]
        XCTAssertFalse(submit.isEnabled)
        for _ in 0..<4 { card.tap() }
        XCTAssertEqual(submit.value as? String, "4 of 4 selected")
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
    }

    private func resource(_ resource: String, in app: XCUIApplication) -> String? {
        app.otherElements["human-resource.\(resource)"].value as? String
    }

    private func coldResume(in app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let resume = app.buttons["main-menu.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: timeout), "The ordinary Resume route must find this match")
        resume.tap()
    }

    private func placeOpeningPair(in app: XCUIApplication) throws {
        try place(settlementPrefix, in: app)
        try place(roadPrefix, in: app)
    }

    private func place(_ prefix: String, in app: XCUIApplication) throws {
        let available = targets(prefix, in: app)
        XCTAssertTrue(available.firstMatch.waitForExistence(timeout: timeout), "No legal \(prefix) target")
        let target = try XCTUnwrap(available.allElementsBoundByIndex.first(where: \.isHittable), prefix)
        target.tap()
        XCTAssertEqual(target.value as? String, "Selected")
        confirmBoardDecision(in: app)
    }

    private func targets(_ prefix: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
    }

    private func confirmBoardDecision(in app: XCUIApplication) {
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout) && confirm.isEnabled)
        confirm.tap()
    }

    private func finishFirstRoll(in app: XCUIApplication) throws {
        let end = app.buttons["End Turn"]
        if end.waitForExistence(timeout: timeout) { return }

        // Starting hands hold at most three cards. A seven can require the
        // robber placement and victim choice, but cannot require a discard.
        try resolveRobber(in: app)
    }

    private func resolveRobber(in app: XCUIApplication) throws {
        let tiles = targets("board.tile.", in: app)
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: timeout))
        let tile = try XCTUnwrap(tiles.allElementsBoundByIndex.first(where: \.isHittable))
        tile.tap()
        if !app.buttons["board-decision.confirm"].isEnabled {
            let victim = targets("robber.victim.", in: app).firstMatch
            XCTAssertTrue(victim.waitForExistence(timeout: timeout))
            victim.tap()
        }
        confirmBoardDecision(in: app)
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: timeout))
    }

    private func retain(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
