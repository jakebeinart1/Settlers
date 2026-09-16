import XCTest

/// Tracer flow for the public UI seam: a player can move from launch into the
/// match contract and back without relying on visible copy or pixel positions.
@MainActor
final class MainMenuFlowTests: XCTestCase {
    func testNewGameOpensAndCancels() {
        continueAfterFailure = false
        let app = launchResetApp()
        let mainMenu = app.otherElements["screen.main-menu"]
        XCTAssertTrue(mainMenu.waitForExistence(timeout: 5))

        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))

        app.buttons["new-game.cancel"].tap()
        XCTAssertTrue(mainMenu.waitForExistence(timeout: 2))
    }

    func testConfiguredMatchStarts() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        app.buttons["Randomized"].tap()
        app.buttons["Random"].tap()
        app.buttons["new-game.start"].tap()

        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))
    }

    /// Table size and match length stopped being controls on 2026-09-16: every
    /// table is four seats and the mode names the target, so Epic left with the
    /// three-player table that offered it. This replaces the test that used to
    /// drive those chips - what matters now is that they are gone and the screen
    /// still starts.
    func testTableSizeAndMatchLengthAreNoLongerChoices() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))

        for gone in ["3 Players", "4 Players", "8 VP", "10 VP", "12 VP"] {
            XCTAssertFalse(app.buttons[gone].exists, "\(gone) should no longer be a control")
        }
        XCTAssertTrue(app.buttons["new-game.start"].isEnabled)
    }

    func testNewGameControlsRemainUsableAtAccessibilityTextSize() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-reset",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXL",
            "-qaShowNewGame",
        ]
        app.launch()

        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        let start = app.buttons["new-game.start"]
        let cancel = app.buttons["new-game.cancel"]
        assertFullyOnScreen(start, named: "Start", in: app)
        assertFullyOnScreen(cancel, named: "Cancel", in: app)

        let setupScroll = app.scrollViews.firstMatch
        XCTAssertTrue(setupScroll.exists)
        assertChoiceRowIsReachable(
            helpLabel: "About Board", choiceLabel: "Randomized", in: app, scroll: setupScroll
        )
        assertChoiceRowIsReachable(
            helpLabel: "About Turn Order", choiceLabel: "Random", in: app, scroll: setupScroll
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "new-game-accessibility-large"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertFullyOnScreen(
        _ control: XCUIElement,
        named name: String,
        in app: XCUIApplication
    ) {
        XCTAssertTrue(control.exists)
        XCTAssertTrue(control.isHittable)
        XCTAssertTrue(
            app.frame.contains(control.frame),
            "the pinned \(name) action must stay fully on-screen at accessibility sizes"
        )
    }

    private func assertChoiceRowIsReachable(
        helpLabel: String,
        choiceLabel: String,
        in app: XCUIApplication,
        scroll: XCUIElement
    ) {
        let help = app.buttons[helpLabel]
        let choice = app.buttons[choiceLabel]
        XCTAssertTrue(help.exists)
        XCTAssertTrue(choice.exists)
        for _ in 0..<3 where !help.isHittable { scroll.swipeUp() }
        XCTAssertTrue(help.isHittable)
        XCTAssertTrue(choice.isHittable)
        XCTAssertFalse(
            help.frame.intersects(choice.frame),
            "\(helpLabel) must not consume or overlap its choices"
        )
    }

    func testOpeningSettlementRequiresAnAdjacentRoad() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()

        let legalVertex = enabledButton(in: app, prefix: "board.vertex.")
        XCTAssertTrue(legalVertex.waitForExistence(timeout: 5))
        let confirm = app.buttons[BoardDecisionUITestID.confirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertFalse(app.otherElements[BoardDecisionUITestID.buildingPreview].exists)
        legalVertex.tap()

        let settlementPreview = app.otherElements[BoardDecisionUITestID.buildingPreview]
        XCTAssertTrue(settlementPreview.waitForExistence(timeout: 2))
        XCTAssertEqual(legalVertex.value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertFalse(enabledButton(in: app, prefix: "board.edge.").exists,
                       "road placement must not begin while the settlement is only staged")
        confirm.tap()
        XCTAssertTrue(settlementPreview.waitForNonExistence(timeout: 2))

        let legalEdge = enabledButton(in: app, prefix: "board.edge.")
        XCTAssertTrue(legalEdge.waitForExistence(timeout: 2))
        XCTAssertFalse(confirm.isEnabled)
        legalEdge.tap()

        let roadPreview = app.otherElements[BoardDecisionUITestID.roadPreview]
        XCTAssertTrue(roadPreview.waitForExistence(timeout: 2))
        XCTAssertEqual(legalEdge.value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(legalEdge.exists,
                      "selecting a road must leave setup waiting for explicit confirmation")
        confirm.tap()

        XCTAssertTrue(roadPreview.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 2))
    }

    func testColdLaunchResumesTheConfiguredMatch() {
        continueAfterFailure = false
        let app = launchResetApp()

        app.buttons["main-menu.new-game"].tap()
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        let resume = app.buttons["main-menu.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        resume.tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))
    }

    private func launchResetApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        return app
    }

    private func enabledButton(in app: XCUIApplication, prefix: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
            .firstMatch
    }
}

/// End-to-end board-decision journeys reached through deterministic QA
/// positions. Every assertion observes the public accessibility surface: a
/// target first becomes a proposal, and only Confirm advances canonical play.
@MainActor
final class BoardDecisionFlowTests: XCTestCase {
    func testPaidRoadStagesThenSpendsOnlyAfterConfirmation() {
        assertPaidBuild(
            pieceTitle: "Road",
            targetPrefix: "board.edge.",
            previewIdentifier: BoardDecisionUITestID.roadPreview,
            expectedResources: [.brick: 4, .lumber: 4, .ore: 5, .grain: 5, .wool: 5]
        )
    }

    func testPaidSettlementStagesThenSpendsOnlyAfterConfirmation() {
        assertPaidBuild(
            pieceTitle: "Settlement",
            targetPrefix: "board.vertex.",
            previewIdentifier: BoardDecisionUITestID.buildingPreview,
            expectedResources: [.brick: 4, .lumber: 4, .ore: 5, .grain: 4, .wool: 4]
        )
    }

    func testPaidCityStagesThenSpendsOnlyAfterConfirmation() {
        assertPaidBuild(
            pieceTitle: "City",
            targetPrefix: "board.vertex.",
            previewIdentifier: BoardDecisionUITestID.buildingPreview,
            expectedResources: [.brick: 5, .lumber: 5, .ore: 2, .grain: 3, .wool: 5]
        )
    }

    func testMandatoryRobberRequiresDestinationVictimAndConfirmation() {
        continueAfterFailure = false
        let app = launchBoardDecision("-qaShowMandatoryRobberDecision")
        let confirm = requireDecisionDock(in: app)

        XCTAssertFalse(confirm.isEnabled)
        XCTAssertTrue(app.buttons[BoardDecisionUITestID.clear].exists)
        XCTAssertFalse(app.buttons[BoardDecisionUITestID.cancel].exists)
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.robberOrigin].exists)

        selectRobberDestinationWithVictim(in: app)
        let preview = app.otherElements[BoardDecisionUITestID.robberPreview]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertFalse(confirm.isEnabled,
                       "a destination must not commit before its victim is explicitly chosen")

        let victim = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", BoardDecisionUITestID.victimPrefix)
        ).firstMatch
        XCTAssertTrue(victim.waitForExistence(timeout: 2))
        let civilization = app.staticTexts.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                BoardDecisionUITestID.victimCivilizationPrefix
            )
        ).firstMatch
        XCTAssertTrue(
            civilization.waitForExistence(timeout: 2),
            "the compact victim card must visibly name its civilization"
        )
        victim.tap()
        XCTAssertEqual(victim.value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(preview.exists, "victim selection must still be an uncommitted proposal")
        XCTAssertEqual(
            app.buttons[BoardDecisionUITestID.clear].label,
            "Choose another territory"
        )

        confirm.tap()

        XCTAssertTrue(preview.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 3))
        assertResource(.ore, equals: 1, in: app)
    }

    func testThreePlayerNonzeroSeatCanResolveRolledSevenRobberDecision() {
        continueAfterFailure = false
        let app = launchBoardDecision(
            "-qaShowMandatoryRobberDecision",
            modifiers: ["-qaThreePlayerTable", "-qaHumanSeatTwo"]
        )
        let confirm = requireDecisionDock(in: app)

        selectRobberDestinationWithVictim(in: app)
        let victims = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", BoardDecisionUITestID.victimPrefix)
        )
        XCTAssertEqual(victims.count, 2, "a three-player fixture must expose both rival seats")
        victims.firstMatch.tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 3))
        assertResource(.ore, equals: 1, in: app)
    }

    func testThreePlayerNonzeroSeatCanResolveKnightRobberDecision() {
        continueAfterFailure = false
        let app = launchBoardDecision(
            "-qaShowRobberTargeting",
            modifiers: ["-qaThreePlayerTable", "-qaHumanSeatTwo"]
        )
        let confirm = requireDecisionDock(in: app)

        selectRobberDestinationWithVictim(in: app)
        let victim = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", BoardDecisionUITestID.victimPrefix)
        ).firstMatch
        XCTAssertTrue(victim.waitForExistence(timeout: 2))
        victim.tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
    }

    func testSettingsRoundTripRetainsTheExactProposal() {
        continueAfterFailure = false
        let app = launchBoardDecision("-qaShowPaidRoadDecision")
        let confirm = requireDecisionDock(in: app)
        let target = enabledBoardTarget(in: app, prefix: "board.edge.")
        target.tap()

        let preview = app.otherElements[BoardDecisionUITestID.roadPreview]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(target.value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled)

        app.buttons[BoardDecisionUITestID.settings].tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.settingsScreen].waitForExistence(timeout: 2))
        app.buttons[BoardDecisionUITestID.settingsClose].tap()

        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.settingsScreen].waitForNonExistence(timeout: 2))
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons[target.identifier].value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled)
    }

    func testQuitToMainMenuDropsOptionalProposalBeforeResume() {
        continueAfterFailure = false
        let app = launchPaidBuild(pieceTitle: "Road")
        let target = enabledBoardTarget(in: app, prefix: "board.edge.")
        target.tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.roadPreview].waitForExistence(timeout: 2))

        app.buttons[BoardDecisionUITestID.settings].tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.settingsScreen].waitForExistence(timeout: 2))
        // The three ways out are pinned in the bottom bar now, so this no
        // longer has to scroll to reach one.
        let quit = app.buttons["in-game-settings.quit"]
        XCTAssertTrue(quit.waitForExistence(timeout: 2))
        quit.tap()

        let confirmMainMenu = app.buttons["Main Menu"]
        XCTAssertTrue(confirmMainMenu.waitForExistence(timeout: 2))
        confirmMainMenu.tap()
        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 3))

        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements[BoardDecisionUITestID.dock].exists)
        XCTAssertFalse(app.otherElements[BoardDecisionUITestID.roadPreview].exists)
    }

    func testDraggingTheCradleStagesButDoesNotCommitARoad() {
        continueAfterFailure = false
        let app = launchBoardDecision("-qaShowPaidRoadDecision")
        let confirm = requireDecisionDock(in: app)
        let cradle = app.otherElements[BoardDecisionUITestID.dragCradle]
        let target = enabledBoardTarget(in: app, prefix: "board.edge.")

        XCTAssertTrue(cradle.waitForExistence(timeout: 2))
        XCTAssertTrue(cradle.isHittable)
        XCTAssertTrue(target.isHittable)
        cradle.press(forDuration: 0.2, thenDragTo: target)

        let preview = app.otherElements[BoardDecisionUITestID.roadPreview]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(target.value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].exists,
                      "dropping the piece must stage it without committing")

        confirm.tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 3))
        assertResource(.brick, equals: 4, in: app)
        assertResource(.lumber, equals: 4, in: app)
    }

    func testDraggingTheRobberStagesDestinationBeforeVictimAndConfirmation() {
        continueAfterFailure = false
        let app = launchBoardDecision("-qaShowMandatoryRobberDecision")
        let confirm = requireDecisionDock(in: app)
        let cradle = app.otherElements[BoardDecisionUITestID.dragCradle]
        let destination = app.buttons[BoardDecisionUITestID.mandatoryRobberVictimTile]

        XCTAssertTrue(cradle.waitForExistence(timeout: 2))
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        cradle.press(forDuration: 0.2, thenDragTo: destination)

        let preview = app.otherElements[BoardDecisionUITestID.robberPreview]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(destination.value as? String, "Selected destination")
        XCTAssertFalse(confirm.isEnabled,
                       "dragging must stage the territory without choosing a victim or committing")

        let victim = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", BoardDecisionUITestID.victimPrefix)
        ).firstMatch
        XCTAssertTrue(victim.waitForExistence(timeout: 2))
        victim.tap()
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        XCTAssertTrue(preview.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 3))
    }

    private func assertPaidBuild(
        pieceTitle: String,
        targetPrefix: String,
        previewIdentifier: String,
        expectedResources: [ResourceName: Int]
    ) {
        continueAfterFailure = false
        let app = launchPaidBuild(pieceTitle: pieceTitle)
        let confirm = requireDecisionDock(in: app)
        let target = enabledBoardTarget(in: app, prefix: targetPrefix)

        XCTAssertFalse(confirm.isEnabled)
        XCTAssertFalse(app.otherElements[previewIdentifier].exists)
        target.tap()

        let preview = app.otherElements[previewIdentifier]
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(target.value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].exists,
                      "target selection must remain a proposal before Confirm")

        confirm.tap()

        XCTAssertTrue(preview.waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 3))
        for (resource, expected) in expectedResources {
            assertResource(resource, equals: expected, in: app)
        }
    }

    private func launchBoardDecision(
        _ flag: String,
        modifiers: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", flag]
            + modifiers
        app.launch()
        return app
    }

    private func launchPaidBuild(pieceTitle: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaPaidBuildPosition",
        ]
        app.launch()

        let build = app.buttons["Build"]
        XCTAssertTrue(build.waitForExistence(timeout: 5))
        let buildReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isEnabled == true"), object: build
        )
        XCTAssertEqual(XCTWaiter.wait(for: [buildReady], timeout: 3), .completed)
        build.tap()

        let piece = app.buttons[buildIdentifier(for: pieceTitle)]
        XCTAssertTrue(piece.waitForExistence(timeout: 2))
        XCTAssertTrue(piece.isEnabled)
        piece.tap()
        return app
    }

    private func buildIdentifier(for title: String) -> String {
        switch title {
        case "Road": return "build.road"
        case "Settlement": return "build.settlement"
        case "City": return "build.city"
        default:
            XCTFail("Unknown build option: \(title)")
            return ""
        }
    }

    private func requireDecisionDock(in app: XCUIApplication) -> XCUIElement {
        let dock = app.otherElements[BoardDecisionUITestID.dock]
        XCTAssertTrue(dock.waitForExistence(timeout: 5))
        let confirm = app.buttons[BoardDecisionUITestID.confirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        return confirm
    }

    private func enabledBoardTarget(in app: XCUIApplication, prefix: String) -> XCUIElement {
        let target = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND isEnabled == true", prefix))
            .firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3), "Expected enabled board target with prefix \(prefix)")
        return target
    }

    private func selectRobberDestinationWithVictim(in app: XCUIApplication) {
        // The deterministic QA fixture puts every rival around the standard
        // board's first non-robber tile. Addressing that stable target directly
        // avoids asking XCTest to materialize all 18 large tile elements at
        // once, which can sever the automation connection on the simulator.
        let destination = app.buttons[BoardDecisionUITestID.mandatoryRobberVictimTile]
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        XCTAssertTrue(destination.isEnabled)
        destination.tap()
    }

    private func assertResource(_ resource: ResourceName, equals expected: Int, in app: XCUIApplication) {
        let element = app.otherElements["human-resource.\(resource.rawValue)"]
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        XCTAssertEqual(element.value as? String, "\(expected)")
    }

    private enum ResourceName: String {
        case brick, lumber, ore, grain, wool
    }
}

enum BoardDecisionUITestID {
    static let dock = "board-decision.dock"
    static let confirm = "board-decision.confirm"
    static let clear = "board-decision.clear"
    static let cancel = "board-decision.cancel"
    static let undo = "board-decision.undo"
    static let buildingPreview = "board.building-preview"
    static let roadPreview = "board.road-preview"
    static let robberPreview = "board.robber-preview"
    static let robberOrigin = "board.robber-origin"
    static let dragCradle = "board.drag-cradle"
    static let mandatoryRobberVictimTile = "board.tile.0_0"
    static let victimPrefix = "robber.victim."
    static let victimCivilizationPrefix = "robber.victim.civilization."
    static let settings = "game.settings"
    static let settingsScreen = "screen.in-game-settings"
    static let settingsClose = "in-game-settings.close"
}
