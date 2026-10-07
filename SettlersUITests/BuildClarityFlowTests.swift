import XCTest

/// Actual native touches prove unavailable rows cannot become hidden proposals,
/// and available construction stays reversible until the production commit.
@MainActor
final class BuildClarityFlowTests: XCTestCase {
    private let resources = ["brick", "lumber", "ore", "grain", "wool"]
    private let navalRows = ["ship", "road", "settlement", "city", "dev-card"]

    func testScarceHandNamesShortagesAndDisabledRowsCannotStartOrSpend() {
        let app = launch(["-qaNavalMode", "-qaNavalBuildScarcity"])
        let before = holdings(in: app)
        let chartedBefore = app.buttons["naval.overview"].value as? String
        XCTAssertEqual(before, [0, 1, 0, 0, 10])
        app.buttons["Build"].tap()
        XCTAssertTrue(app.buttons["build.ship"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["build.ship"].valueAsString.contains("Need 1 lumber · 2 ore"))
        XCTAssertTrue(app.buttons["build.road"].valueAsString.contains("Need 1 brick"))
        let menuBefore = navalRows.map { app.buttons["build.\($0)"].valueAsString }
        retain("Build — exact scarce hand and readable shortages", app: app)
        for identifier in navalRows {
            let row = app.buttons["build.\(identifier)"]
            reveal(row, in: app)
            XCTAssertTrue(row.exists)
            XCTAssertFalse(row.isEnabled)
            XCTAssertTrue(row.valueAsString.hasPrefix("Unavailable"))
            // A physical tap exercises the disabled native surface rather than
            // trusting an accessibility property to imply safety.
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.buttons["Close"].exists)
            XCTAssertEqual(navalRows.map { app.buttons["build.\($0)"].valueAsString }, menuBefore,
                           "A disabled touch must leave the displayed costs and availability unchanged")
        }
        app.buttons["Close"].tap()
        // Modal presentation intentionally hides the underlying HUD and board
        // from accessibility. Verify their actual state after dismissing it;
        // absence beneath the modal cannot prove no hidden proposal was made.
        XCTAssertTrue(app.buttons["End Turn"].isHittable)
        XCTAssertTrue(app.buttons["Build"].isEnabled)
        XCTAssertFalse(app.buttons["board-decision.confirm"].exists)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
        XCTAssertFalse(app.buttons["board.ship.0"].exists)
        XCTAssertEqual(holdings(in: app), before)
        XCTAssertEqual(app.buttons["naval.overview"].value as? String, chartedBefore)
    }

    func testReadyShipRowPreviewsCancelsCommitsAndPersistsExactCost() {
        let app = launch(["-qaNavalMode", "-qaNavalVoyagePosition"])
        let before = holdings(in: app)
        app.buttons["Build"].tap()
        let ship = app.buttons["build.ship"]
        XCTAssertTrue(ship.waitForExistence(timeout: 3))
        XCTAssertTrue(ship.isEnabled)
        XCTAssertTrue(ship.valueAsString.hasPrefix("Ready"))
        let settlement = app.buttons["build.settlement"]
        XCTAssertFalse(settlement.isEnabled)
        XCTAssertTrue(settlement.valueAsString.contains("No legal corner reached by your roads or ships"))
        retain("Build — ready ship contrasts with blocked construction", app: app)
        ship.tap()
        selectSea(in: app)
        XCTAssertTrue(app.otherElements["board.ship-preview"].exists)
        XCTAssertEqual(holdings(in: app), before)
        app.buttons["board-decision.cancel"].tap()
        XCTAssertFalse(app.buttons["board.ship.0"].exists)
        XCTAssertEqual(holdings(in: app), before)
        app.buttons["Build"].tap()
        app.buttons["build.ship"].tap()
        selectSea(in: app)
        XCTAssertTrue(app.buttons["board-decision.confirm"].isEnabled)
        app.buttons["board-decision.confirm"].tap()
        XCTAssertTrue(app.buttons["board.ship.0"].waitForExistence(timeout: 5))
        let expected = zip(before, [0, 2, 2, 0, 1]).map { $0.0 - $0.1 }
        XCTAssertEqual(holdings(in: app), expected)
        retain("Build — confirmed vessel with exact payment", app: app)
        app.buttons["board-decision.cancel"].tap()
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: 5))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 5))
        XCTAssertEqual(holdings(in: app), expected)
        XCTAssertTrue(app.buttons["board.ship.0"].exists)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
    }

    func testClassicConstructionStillUsesOriginalStableRowsAndRealPreview() {
        let app = launch(["-qaPaidBuildPosition"])
        let before = holdings(in: app)
        app.buttons["Build"].tap()
        XCTAssertFalse(app.buttons["build.ship"].exists)
        for identifier in ["road", "settlement", "city", "dev-card"] {
            let row = app.buttons["build.\(identifier)"]
            XCTAssertTrue(row.isEnabled)
            XCTAssertTrue(row.valueAsString.hasPrefix("Ready"))
        }
        retain("Build — Classic ready construction", app: app)
        app.buttons["build.road"].tap()
        let edge = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.edge.")).firstMatch
        XCTAssertTrue(edge.waitForExistence(timeout: 3))
        edge.tap()
        XCTAssertEqual(holdings(in: app), before)
        app.buttons["board-decision.cancel"].tap()
        XCTAssertEqual(holdings(in: app), before)
    }

    func testConquestArmyRowsRemainReachableAtLargestTextWithPinnedClose() {
        let app = launch(["-qaShowConquest", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["Build"].tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.frame.contains(close.frame))
        let army = app.buttons["build.army-card"]
        reveal(army, in: app)
        XCTAssertTrue(army.valueAsString.contains("Any 3"))
        let deploy = app.buttons["build.deploy-army"]
        reveal(deploy, in: app)
        XCTAssertTrue(deploy.isEnabled)
        XCTAssertTrue(deploy.valueAsString.hasPrefix("Ready"))
        retain("Build — accessible Conquest choices and fixed Close", app: app)
        close.tap()
        XCTAssertTrue(app.buttons["Build"].isHittable)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart"] + arguments
        app.launch()
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 15))
        return app
    }

    private func holdings(in app: XCUIApplication) -> [Int] {
        resources.map { resource in
            let raw = app.otherElements["human-resource.\(resource)"].value as? String
            XCTAssertNotNil(raw)
            return Int(raw ?? "") ?? -1
        }
    }

    private func selectSea(in app: XCUIApplication) {
        let targets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        XCTAssertTrue(targets.firstMatch.waitForExistence(timeout: 5))
        let target = targets.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(target)
        target?.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let choices = app.scrollViews["build.choices"]
        XCTAssertTrue(choices.waitForExistence(timeout: 3))
        for _ in 0..<8 where !element.isHittable { choices.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    var valueAsString: String { value as? String ?? "" }
}
