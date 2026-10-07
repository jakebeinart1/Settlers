import XCTest

/// One visible destination choice must commit a whole voyage, while staging
/// and clearing leave travel, discoveries and the conserved hand untouched.
@MainActor
final class NavalTravelFlowTests: XCTestCase {
    func testFullTwoHexRangePreviewsOnceAndCommitsOneVoyageThenColdResumes() {
        continueAfterFailure = false
        let app = launch()
        purchase(in: app)
        let original = position(in: app)
        let discovered = charted(in: app)
        let holdings = resources(in: app)
        let targets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        let entries = targets.allElementsBoundByIndex
        XCTAssertTrue(entries.contains { ($0.value as? String ?? "").contains("1 hex of travel") })
        XCTAssertTrue(entries.contains { ($0.value as? String ?? "").contains("2 hexes of travel") })
        XCTAssertTrue(app.staticTexts["2 hexes left this turn. Numbers show travel cost."].exists)
        XCTAssertFalse(app.staticTexts["Sail Ship 1"].exists)
        retain("Voyages — complete two-hex sailing range", app: app)
        guard let target = entries.first(where: {
            ($0.value as? String ?? "").contains("2 hexes of travel") && $0.isHittable
        }) else { XCTFail("No visible two-hex destination"); return }
        target.tap()
        XCTAssertTrue(app.buttons["board-decision.confirm"].isEnabled)
        XCTAssertTrue(app.staticTexts["Sail 2 hexes. 0 left afterward."].exists)
        XCTAssertEqual(position(in: app), original)
        XCTAssertEqual(charted(in: app), discovered)
        XCTAssertEqual(resources(in: app), holdings)
        retain("Voyages — one destination stages the complete route", app: app)
        app.buttons["board-decision.clear"].tap()
        XCTAssertEqual(position(in: app), original)
        XCTAssertEqual(charted(in: app), discovered)
        app.buttons["board.ship.0"].tap()
        target.tap()
        app.buttons["board-decision.confirm"].tap()
        let moved = position(in: app)
        XCTAssertTrue(moved.contains("steps=0"))
        XCTAssertNotEqual(moved, original)
        XCTAssertEqual(resources(in: app), holdings)
        XCTAssertTrue(app.buttons["End Turn"].exists)
        retain("Voyages — complete voyage uses both hexes", app: app)
        coldResume(app)
        XCTAssertEqual(position(in: app), moved)
        XCTAssertEqual(resources(in: app), holdings)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
    }

    func testFleetAndVictoryGoalUsePlainVisibleLanguage() {
        let app = launch()
        purchase(in: app)
        app.buttons["naval.fleet.open"].tap()
        let ship = app.buttons["naval.fleet.ship.0"]
        XCTAssertTrue(ship.waitForExistence(timeout: 5))
        XCTAssertTrue(ship.label.contains("2 hexes of sailing left"))
        XCTAssertFalse(ship.label.contains("Ship 1"))
        retain("Voyages — plain fleet travel allowance", app: app)
        ship.tap()
        XCTAssertTrue(app.staticTexts["game.victory-points"].label.contains("14 needed to win"))
        app.buttons["game.settings"].tap()
        let goal = app.staticTexts["in-game-settings.victory-target"]
        XCTAssertTrue(goal.waitForExistence(timeout: 5))
        XCTAssertEqual(goal.label, "First to 14 victory points wins.")
        retain("Voyages — current match victory goal", app: app)
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode", "-qaNavalVoyagePosition"]
        app.launch()
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 15))
        return app
    }

    private func purchase(in app: XCUIApplication) {
        app.buttons["Build"].tap()
        app.buttons["build.ship"].tap()
        let targets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        guard let first = targets.allElementsBoundByIndex.first(where: \.isHittable) else {
            XCTFail("No launch coast available"); return
        }
        first.tap()
        app.buttons["board-decision.confirm"].tap()
        XCTAssertTrue(app.buttons["board.ship.0"].waitForExistence(timeout: 5))
    }

    private func coldResume(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: 5))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.fleet.open"].waitForExistence(timeout: 5))
    }

    private func position(in app: XCUIApplication) -> String {
        app.otherElements["naval.ship.position.0"].value as? String ?? ""
    }

    private func charted(in app: XCUIApplication) -> String {
        app.buttons["naval.overview"].value as? String ?? ""
    }

    private func resources(in app: XCUIApplication) -> [String] {
        ["brick", "lumber", "ore", "grain", "wool"].map {
            app.otherElements["human-resource.\($0)"].value as? String ?? ""
        }
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
