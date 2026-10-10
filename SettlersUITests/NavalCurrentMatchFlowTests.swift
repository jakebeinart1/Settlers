import XCTest

/// A fresh current-rule match exercises ordinary turn boundaries, policy
/// decisions, production and the archived replay without rare-state fixtures.
@MainActor
final class NavalCurrentMatchFlowTests: XCTestCase {
    func testTraditionalNavalMatchFinishesAndReplaysItsActualExploration() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaPlayToEnd", "-qaNavalSeed=19", "-qaNavalFamily=twinIslands"]
        app.launch()
        let skip = app.buttons["game-over.cutscene.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 360), "Traditional Naval must reach an actual winner")
        skip.tap()
        XCTAssertTrue(app.buttons["game-over.new-game"].waitForExistence(timeout: 10))
        retain("Naval v6 — completed Traditional match", app: app)
        app.buttons["game-over.replay"].tap()
        XCTAssertTrue(app.buttons["replay.end"].waitForExistence(timeout: 30))
        app.buttons["replay.start"].tap()
        let opening = charted(app)
        app.buttons["naval.overview"].tap()
        retain("Naval v6 — Traditional replay opening", app: app)
        app.buttons["replay.end"].tap()
        XCTAssertGreaterThan(charted(app), opening)
        retain("Naval v6 — Traditional replay explored world", app: app)
        app.buttons["replay.close"].tap()
        app.buttons["game-over.main-menu"].tap()
        XCTAssertTrue(app.buttons["main-menu.new-game"].waitForExistence(timeout: 10),
                      "Leaving the completed match must reach the main menu")
        XCTAssertFalse(app.buttons["main-menu.resume"].exists, "A finished match must clear its resumable save")
    }

    private func charted(_ app: XCUIApplication) -> Int {
        let value = app.buttons["naval.overview"].value as? String ?? ""
        let counts = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(counts.count, 2, "The shared chart summary must describe the actual replay frame")
        return counts.first ?? -1
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
