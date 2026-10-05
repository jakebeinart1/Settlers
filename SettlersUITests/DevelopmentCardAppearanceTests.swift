import XCTest

/// These assertions inspect actual rendered controls. The old tile exposes no
/// typed status value and announces an older blocked copy as ready.
@MainActor
final class DevelopmentCardAppearanceTests: XCTestCase {
    func testMixedInventoryExposesFullTitleCountsAndTypedReadiness() {
        let app = launchHand()
        let knight = app.buttons["dev-cards.tile.knight"]
        XCTAssertTrue(knight.waitForExistence(timeout: 5))
        XCTAssertEqual(knight.label, "Knight, 2 owned")
        XCTAssertEqual(knight.value as? String, "1 ready, 1 new. Ready to play")
        let road = app.buttons["dev-cards.tile.roadBuilding"]
        XCTAssertEqual(road.label, "Road Building, 2 owned")
        XCTAssertEqual(road.value as? String, "1 ready, 1 new. Ready to play")
    }

    func testBlockedMixedStackDoesNotAdvertiseReadyAndStillOpens() {
        let app = launchHand()
        let monopoly = app.buttons["dev-cards.tile.monopoly"]
        XCTAssertTrue(monopoly.waitForExistence(timeout: 5))
        monopoly.tap()
        app.buttons["dev-cards.resource.wool"].tap()
        app.buttons["dev-cards.play.monopoly"].tap()
        XCTAssertTrue(app.buttons["dev-cards.result.continue"].waitForExistence(timeout: 3))
        app.buttons["dev-cards.result.continue"].tap()
        app.buttons["dev-cards.shelf"].tap()
        let road = app.buttons["dev-cards.tile.roadBuilding"]
        XCTAssertTrue(road.waitForExistence(timeout: 3))
        XCTAssertTrue(road.isEnabled, "A blocked card must remain inspectable")
        XCTAssertEqual(road.value as? String, "1 held, 1 new. One card already played")
        road.tap()
        XCTAssertTrue(app.staticTexts["dev-cards.detail.roadBuilding"].exists)
        XCTAssertFalse(app.buttons["dev-cards.play.roadBuilding"].isEnabled)
    }

    private func launchHand() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaShowDevCardHand"]
        app.launch()
        return app
    }

    func testPaintedPlentyChooserCanRemoveAndReselectTheSameResource() {
        let app = launchHand()
        let plenty = app.buttons["dev-cards.tile.yearOfPlenty"]
        XCTAssertTrue(plenty.waitForExistence(timeout: 5))
        plenty.tap()
        let ore = app.buttons["dev-cards.resource.ore"]
        XCTAssertTrue(ore.waitForExistence(timeout: 2))
        ore.tap()
        ore.tap()
        let play = app.buttons["dev-cards.play.yearOfPlenty"]
        XCTAssertTrue(play.isEnabled)
        let selected = app.buttons["dev-cards.selected.ore"]
        XCTAssertTrue(selected.exists)
        selected.tap()
        XCTAssertFalse(play.isEnabled, "Removing a pick must disable committing an incomplete pair")
        ore.tap()
        XCTAssertTrue(play.isEnabled)
        play.tap()
        XCTAssertTrue(app.staticTexts["dev-cards.result"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["The bank gave you 2 ore."].exists)
    }

}
