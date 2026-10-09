import XCTest

/// The mode is the only match-contract dial left on the New Game screen, and it
/// sets the victory-point target, so the interaction is covered end to end
/// rather than only through model tests.
@MainActor
final class NewGameModeFlowTests: XCTestCase {

    func testClassicWithClassicBotsStartsAndResumes() {
        assertMatchStartsAndResumes(vast: false, expert: false, vertexCount: 54)
    }

    func testClassicWithExpertBotsStartsAndResumes() {
        assertMatchStartsAndResumes(vast: false, expert: true, vertexCount: 54)
    }

    func testVastWithClassicBotsStartsAndResumes() {
        assertMatchStartsAndResumes(vast: true, expert: false, vertexCount: 150)
    }

    func testVastWithExpertBotsStartsAndResumes() {
        assertMatchStartsAndResumes(vast: true, expert: true, vertexCount: 150)
    }

    /// Tap the shipping controls, not a fixture that installs the finished
    /// configuration. Cold resume must restore the same board and a playable
    /// setup decision; model tests separately pin the restored policy IDs.
    private func assertMatchStartsAndResumes(vast: Bool, expert: Bool, vertexCount: Int) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        if vast { app.buttons["Vast"].tap() }
        if expert { app.buttons["Expert"].tap() }
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        assertOpeningBoard(in: app, vertexCount: vertexCount)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "release-\(vast ? "vast" : "classic")-\(expert ? "expert" : "classic")"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: 5))
        app.buttons["main-menu.resume"].tap()
        assertOpeningBoard(in: app, vertexCount: vertexCount)
        confirmOpeningSettlement(in: app)
    }

    /// Conquest is a rules layer over the board, chosen beside it.
    func testConquestStartsFromTheNewGameScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()
        app.buttons["main-menu.new-game"].tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 5))
        app.buttons["Conquest"].tap()
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        assertOpeningBoard(in: app, vertexCount: 54)
    }

    func testNavalReturnsToClassicStandard() {
        assertReturningFromNavalStarts(vast: false, conquest: false)
    }

    func testNavalReturnsToClassicConquest() {
        assertReturningFromNavalStarts(vast: false, conquest: true)
    }

    func testNavalReturnsToVastStandard() {
        assertReturningFromNavalStarts(vast: true, conquest: false)
    }

    func testNavalReturnsToVastConquest() {
        assertReturningFromNavalStarts(vast: true, conquest: true)
    }

    func testNavalReturnsToFixedClassicStandard() {
        assertReturningFromNavalStarts(vast: false, conquest: false, randomized: false)
    }

    func testNavalReturnsToFixedClassicConquest() {
        assertReturningFromNavalStarts(vast: false, conquest: true, randomized: false)
    }

    func testNavalReturnsToFixedVastStandard() {
        assertReturningFromNavalStarts(vast: true, conquest: false, randomized: false)
    }

    func testNavalReturnsToFixedVastConquest() {
        assertReturningFromNavalStarts(vast: true, conquest: true, randomized: false)
    }

    func testNavalRoundTripUsesUpdatedLandChoices() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()
        XCTAssertTrue(app.buttons["new-game.rules.naval"].waitForExistence(timeout: 10))
        app.buttons["new-game.board.standard"].tap()
        visitNavalAndReturn(in: app, conquest: false)
        XCTAssertTrue(app.buttons["new-game.board.standard"].isSelected)
        app.buttons["new-game.mode.vast"].tap()
        app.buttons["new-game.board.randomized"].tap()
        visitNavalAndReturn(in: app, conquest: true)
        XCTAssertTrue(app.buttons["new-game.mode.vast"].isSelected)
        XCTAssertTrue(app.buttons["new-game.board.randomized"].isSelected)
        app.buttons["new-game.mode.classic"].tap()
        app.buttons["new-game.board.standard"].tap()
        visitNavalAndReturn(in: app, conquest: false)
        XCTAssertTrue(app.buttons["new-game.mode.classic"].isSelected)
        XCTAssertTrue(app.buttons["new-game.board.standard"].isSelected)
        XCTAssertTrue(app.buttons["new-game.start"].isEnabled)
    }

    /// Visiting Naval must preserve the land-board choice alongside its mode.
    /// Naval's randomized island generation cannot replace a fixed land board
    /// that the player already selected before exploring the Rules options.
    private func assertReturningFromNavalStarts(vast: Bool, conquest: Bool, randomized: Bool = true) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()
        XCTAssertTrue(app.buttons["new-game.rules.naval"].waitForExistence(timeout: 10))
        if vast { app.buttons["new-game.mode.vast"].tap() }
        let boardChoice = "new-game.board.\(randomized ? "randomized" : "standard")"
        app.buttons[boardChoice].tap()
        XCTAssertTrue(app.buttons[boardChoice].isSelected)
        app.buttons["new-game.rules.conquest"].tap()
        visitNavalAndReturn(in: app, conquest: conquest)
        XCTAssertTrue(app.buttons["new-game.mode.\(vast ? "vast" : "classic")"].isSelected)
        XCTAssertTrue(app.buttons[boardChoice].isSelected,
                      "Visiting Naval replaced the selected land-board layout")
        XCTAssertTrue(app.buttons["new-game.start"].isEnabled)
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        assertOpeningBoard(in: app, vertexCount: vast ? 150 : 54)
    }

    private func visitNavalAndReturn(in app: XCUIApplication, conquest: Bool) {
        let naval = app.buttons["new-game.rules.naval"]
        naval.tap()
        XCTAssertTrue(naval.isSelected)
        // Tapping the selected rule cannot replace the remembered land choice.
        naval.tap()
        XCTAssertFalse(app.buttons["new-game.mode.vast"].exists)
        let rules = app.buttons["new-game.rules.\(conquest ? "conquest" : "standard")"]
        rules.tap()
        XCTAssertTrue(rules.isSelected, "Returning from Naval must restore the chosen land rules")
    }

    private func assertOpeningBoard(in app: XCUIApplication, vertexCount: Int) {
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 5))
        let vertices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.vertex."))
        XCTAssertTrue(vertices.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(vertices.count, vertexCount, "The selected board was not restored")
        XCTAssertTrue(app.buttons["board-decision.confirm"].exists)
    }

    private func confirmOpeningSettlement(in app: XCUIApplication) {
        let vertex = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND isEnabled == true", "board.vertex."
        )).firstMatch
        vertex.tap()
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        let road = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND isEnabled == true", "board.edge."
        )).firstMatch
        XCTAssertTrue(road.waitForExistence(timeout: 5), "Resumed setup did not advance to road placement")
    }

    /// The mode row is a chip row rather than a popup as of 2026-09-16, so this
    /// taps the chip directly. Match length is no longer a control at all - the
    /// mode sets the target - so what this asserts is that picking a mode still
    /// leaves a startable match rather than stranding an out-of-range target.
    func testPickingVastLeavesTheMatchStartable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()

        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 10))

        let vast = app.buttons["Vast"]
        XCTAssertTrue(vast.waitForExistence(timeout: 5), "The Vast chip is not on the mode row")
        vast.tap()

        XCTAssertTrue(app.buttons["new-game.start"].isEnabled,
                      "Switching mode left Start disabled: the target did not snap into range")
    }

    /// Expanded is retired from the New Game screen but still decodable, so an
    /// in-progress save resumes. It must not be offerable again.
    func testExpandedIsNoLongerOffered() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()

        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Expanded"].exists,
                       "Expanded is still startable; its 25-point target is unreachable on its board")
    }
}
