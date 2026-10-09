import XCTest

/// Observe the renderer, not just a setup value. Naval supplies a positive
/// mist control before the real New Game controls replace it with each land
/// rules combination; cold launches and replay then inspect those same saves.
@MainActor
final class OrdinaryModeVisibilityTests: XCTestCase {
    private static let transitionTimeout: TimeInterval = 10
    private static let completeMatchTimeout: TimeInterval = 360

    func testClassicStandardHasNoMistAfterNavalSetupResumeAndRestart() {
        auditOrdinaryJourney(vast: false, conquest: false)
    }

    func testClassicConquestHasNoMistAfterNavalSetupResumeAndRestart() {
        auditOrdinaryJourney(vast: false, conquest: true)
    }

    func testVastStandardHasNoMistAfterNavalSetupResumeAndRestart() {
        auditOrdinaryJourney(vast: true, conquest: false)
    }

    func testVastConquestHasNoMistAfterNavalSetupResumeAndRestart() {
        auditOrdinaryJourney(vast: true, conquest: true)
    }

    /// The saved Classic match is actually played to a winner by the existing
    /// onscreen production driver. Its own recording, rather than a fabricated
    /// end position, must retain the complete ordinary board at both endpoints.
    func testCompletedOrdinaryMatchAfterNavalHasNoMistInVictoryAndReplay() {
        continueAfterFailure = false
        let app = startOrdinaryAfterNaval(vast: false, conquest: false)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart", "-qaPlayToEnd"]
        app.launch()
        let skip = app.buttons["game-over.cutscene.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: Self.completeMatchTimeout),
                      "The restored ordinary match must reach its real victory cutscene")
        let score = app.staticTexts["game-over.cutscene.score"]
        let tourStarted = NSPredicate { _, _ in Int(score.label).map { $0 > 0 } ?? false }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: tourStarted, object: nil)],
                                     timeout: Self.transitionTimeout), .completed,
                       "The first scored beat follows the curtain opening; capture the actual board tour")
        assertOrdinaryProjection(in: app, vast: false, conquest: false)
        retain("Classic after Naval — real winner's board tour", in: app)
        skip.tap()
        openAndAuditCompletedReplay(in: app)
    }

    private func auditOrdinaryJourney(vast: Bool, conquest: Bool) {
        continueAfterFailure = false
        let app = startOrdinaryAfterNaval(vast: vast, conquest: conquest)
        confirmSettlement(in: app)
        assertOrdinaryProjection(in: app, vast: vast, conquest: conquest)
        retain(stage("settlement committed", vast: vast, conquest: conquest), in: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: Self.transitionTimeout))
        app.buttons["main-menu.resume"].tap()
        assertDockTitle("Confirm Road", in: app)
        assertOrdinaryProjection(in: app, vast: vast, conquest: conquest)
        retain(stage("cold resume", vast: vast, conquest: conquest), in: app)
        restart(in: app)
        assertOrdinaryProjection(in: app, vast: vast, conquest: conquest)
        retain(stage("restart", vast: vast, conquest: conquest), in: app)
    }

    private func startOrdinaryAfterNaval(vast: Bool, conquest: Bool) -> XCUIApplication {
        let app = launchNavalPositiveControl()
        leaveMatch(in: app)
        app.buttons["main-menu.new-game"].tap()
        let advanced = app.buttons["new-game.naval.advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: Self.transitionTimeout),
                      "The saved Naval prefill must actually expose its Advanced Settings control")
        let rule = app.buttons["new-game.rules.\(conquest ? "conquest" : "standard")"]
        XCTAssertTrue(rule.waitForExistence(timeout: Self.transitionTimeout))
        rule.tap()
        let mode = app.buttons["new-game.mode.\(vast ? "vast" : "classic")"]
        XCTAssertTrue(mode.waitForExistence(timeout: Self.transitionTimeout))
        mode.tap()
        XCTAssertTrue(rule.isSelected, "Changing the land board must retain the selected rules variant")
        XCTAssertFalse(app.buttons["new-game.naval.advanced"].exists)
        app.buttons["new-game.board.standard"].tap()
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        let overwrite = app.buttons["new-game.confirm-overwrite"]
        XCTAssertTrue(overwrite.waitForExistence(timeout: Self.transitionTimeout),
                      "The real Naval save must require replacement confirmation")
        overwrite.tap()
        assertOrdinaryProjection(in: app, vast: vast, conquest: conquest)
        retain(stage("opening", vast: vast, conquest: conquest), in: app)
        return app
    }

    private func launchNavalPositiveControl() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode", "-qaNavalSeed=7501"]
        app.launch()
        let mist = element("board.mist-field", in: app)
        XCTAssertTrue(mist.waitForExistence(timeout: Self.transitionTimeout),
                      "The absence detector must first observe the actual Naval mist subtree")
        let field = (mist.value as? String)?.split(separator: ";").first { $0.hasPrefix("hidden=") }
        let hidden = field.flatMap { Int($0.dropFirst("hidden=".count)) }
        XCTAssertNotNil(hidden, "The actual mist renderer must expose a readable hidden-cell count")
        XCTAssertGreaterThan(hidden ?? 0, 0, "The positive control must paint unexplored fog")
        for identifier in ["naval.home", "naval.overview", "naval.fleet.open"] {
            XCTAssertTrue(app.buttons[identifier].waitForExistence(timeout: Self.transitionTimeout),
                          "The Naval-only absence detector needs a real \(identifier) positive control")
        }
        app.buttons["naval.overview"].tap()
        retain("Naval positive control — actual unexplored mist before changing rules", in: app)
        return app
    }

    private func assertOrdinaryProjection(in app: XCUIApplication, vast: Bool, conquest: Bool,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let projection = element("board.public-projection", in: app)
        XCTAssertTrue(projection.waitForExistence(timeout: Self.transitionTimeout), file: file, line: line)
        let expected = "mode=\(vast ? "vast" : "classic");variant=\(conquest ? "conquest" : "standard");"
            + "tiles=\(vast ? 61 : 19);fog=0;sea=0;choices=0;ports=\(vast ? 15 : 9);genericPorts=\(vast ? 5 : 4)"
        XCTAssertEqual(projection.value as? String, expected,
                       "Ordinary Canvas must consume its complete board and harbors", file: file, line: line)
        XCTAssertFalse(element("board.mist-field", in: app).exists,
                       "A Naval mist layer must not exist in an ordinary match", file: file, line: line)
        for identifier in ["naval.home", "naval.overview", "naval.fleet.open"] {
            XCTAssertFalse(app.buttons[identifier].exists, file: file, line: line)
        }
    }

    private func confirmSettlement(in app: XCUIApplication) {
        let candidates = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND isEnabled == true", "board.vertex."))
        XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: Self.transitionTimeout))
        guard let target = candidates.allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail("The fully visible ordinary board has no hittable settlement corner")
            return
        }
        target.tap()
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.edge."))
            .firstMatch.waitForExistence(timeout: Self.transitionTimeout))
        assertDockTitle("Confirm Road", in: app)
    }

    private func leaveMatch(in app: XCUIApplication) {
        app.buttons["game.settings"].tap()
        XCTAssertTrue(app.buttons["in-game-settings.quit"].waitForExistence(timeout: Self.transitionTimeout))
        app.buttons["in-game-settings.quit"].tap()
        XCTAssertTrue(app.buttons["Main Menu"].waitForExistence(timeout: Self.transitionTimeout))
        app.buttons["Main Menu"].tap()
        XCTAssertTrue(app.buttons["main-menu.new-game"].waitForExistence(timeout: Self.transitionTimeout))
    }

    private func restart(in app: XCUIApplication) {
        app.buttons["game.settings"].tap()
        XCTAssertTrue(app.buttons["in-game-settings.restart"].waitForExistence(timeout: Self.transitionTimeout))
        app.buttons["in-game-settings.restart"].tap()
        let confirm = app.buttons["in-game-settings.restart-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.transitionTimeout))
        confirm.tap()
        assertDockTitle("Confirm Settlement", in: app)
    }

    /// The confirmation control exists in both setup phases. Observe its
    /// actual command changing, so a preserved road phase cannot fake Restart.
    private func assertDockTitle(_ title: String, in app: XCUIApplication) {
        let command = app.buttons["board-decision.confirm"]
        XCTAssertTrue(command.waitForExistence(timeout: Self.transitionTimeout))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", title), object: command)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: Self.transitionTimeout), .completed,
                       "The actual board decision must become \(title)")
    }

    private func openAndAuditCompletedReplay(in app: XCUIApplication) {
        let replay = app.buttons["game-over.replay"]
        XCTAssertTrue(replay.waitForExistence(timeout: Self.transitionTimeout))
        replay.tap()
        XCTAssertTrue(app.buttons["replay.start"].waitForExistence(timeout: Self.transitionTimeout))
        app.buttons["replay.start"].tap()
        assertOrdinaryProjection(in: app, vast: false, conquest: false)
        let tiles = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "board.inspect.tile."))
        XCTAssertEqual(tiles.count, 19, "Inspect-only replay exposes every ordinary hex from its opening")
        retain("Classic after Naval — complete opening replay with visible harbors", in: app)
        app.buttons["replay.end"].tap()
        assertOrdinaryProjection(in: app, vast: false, conquest: false)
        XCTAssertEqual(tiles.count, 19)
        retain("Classic after Naval — complete winning replay with visible harbors", in: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func stage(_ name: String, vast: Bool, conquest: Bool) -> String {
        "\(vast ? "Vast" : "Classic") \(conquest ? "Conquest" : "Standard") after Naval — \(name), no mist"
    }

    private func retain(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
