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
