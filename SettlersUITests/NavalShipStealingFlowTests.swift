import XCTest

/// Native actions must display and retain a real ownership transfer, rather
/// than a seeded message. Root QA runs this suite on its existing single device.
@MainActor
final class NavalShipStealingFlowTests: XCTestCase {
    func testNewGameOffersDisabledShipStealingWithExplanationAndPreservesDraftChoice() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()
        app.buttons["new-game.rules.naval"].tap()
        app.buttons["new-game.naval.advanced"].tap()
        let choice = app.buttons["new-game.naval.ship-stealing"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        reveal(choice, in: app)
        XCTAssertEqual(choice.value as? String, "Off")
        retain("Naval — ship stealing defaults Off with its rule explained", in: app)
        choice.tap()
        XCTAssertEqual(choice.value as? String, "On")
        app.buttons["new-game.naval.advanced.done"].tap()
        app.buttons["new-game.naval.advanced"].tap()
        reveal(choice, in: app)
        XCTAssertEqual(choice.value as? String, "On")
        choice.tap()
        XCTAssertEqual(choice.value as? String, "Off")
        retain("Naval — ship stealing can be switched back Off", in: app)
    }

    func testActualBotStealRemainsExplicitAcrossColdResumeUntilAcknowledged() {
        let app = launchLoss(largestText: false)
        let receipt = app.alerts["naval.capture.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 20), "The ordinary rival must roll 11 and commit capture")
        XCTAssertTrue(app.staticTexts["Your ship was stolen"].exists)
        XCTAssertTrue(app.otherElements["naval.capture.location"].exists)
        XCTAssertFalse(app.buttons["board-decision.confirm"].exists)
        XCTAssertFalse(app.buttons["board.ship.0"].isHittable)
        retain("Naval — actual rival capture explains the lost vessel", in: app)
        coldResume(app)
        XCTAssertTrue(app.alerts["naval.capture.receipt"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your ship was stolen"].exists)
        retain("Naval — unread ship loss survives a fresh process", in: app)
        let acknowledgement = app.buttons["naval.capture.continue"]
        XCTAssertTrue(acknowledgement.isHittable)
        acknowledgement.tap()
        XCTAssertFalse(receipt.exists)
        let owner = app.otherElements["naval.ship.owner.0"]
        XCTAssertTrue(owner.waitForExistence(timeout: 5))
        XCTAssertEqual(owner.value as? String, "1")
        app.buttons["naval.fleet.open"].tap()
        let vessel = app.buttons["naval.fleet.ship.0"]
        XCTAssertTrue(vessel.waitForExistence(timeout: 5))
        XCTAssertFalse(vessel.label.contains("Ship 0"))
        XCTAssertFalse(vessel.label.hasPrefix("Alex,"), "Fleet must describe its current owner after acknowledgement")
        retain("Naval — Fleet shows the vessel's new owner", in: app)
    }

    func testLossReceiptKeepsContinueReachableAtMaximumText() {
        let app = launchLoss(largestText: true)
        let receipt = app.alerts["naval.capture.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 20))
        let acknowledgement = app.buttons["naval.capture.continue"]
        XCTAssertTrue(acknowledgement.isHittable)
        XCTAssertTrue(app.frame.insetBy(dx: 1, dy: 1).contains(acknowledgement.frame))
        retain("Naval — maximum text ship loss keeps Continue visible", in: app)
        let content = receipt.scrollViews.firstMatch
        XCTAssertTrue(content.exists && content.isHittable, "Large text must have an actual readable content scroll area")
        content.swipeUp()
        XCTAssertTrue(acknowledgement.isHittable)
        retain("Naval — maximum text ownership and location are scrollable", in: app)
        acknowledgement.tap()
        XCTAssertFalse(receipt.exists)
    }

    func testConfirmedHumanCaptureRetainsItsOwnershipReceiptAfterColdResumeAndThenSails() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalCapturePosition"]
        app.launch()
        let choice = app.buttons["naval.choose-ship.0"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["naval.ship.owner.0"].value as? String, "1")
        choice.tap()
        app.buttons["board-decision.confirm"].tap()
        let receipt = app.alerts["naval.capture.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(receipt.staticTexts["You took control of a ship"].exists)
        XCTAssertTrue(receipt.otherElements["naval.capture.location"].exists)
        XCTAssertFalse(app.buttons["End Turn"].isHittable)
        retain("Naval — human-confirmed capture has an ownership receipt", in: app)
        coldResume(app)
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertTrue(receipt.staticTexts["You took control of a ship"].exists)
        retain("Naval — the human's unread gained ship survives cold resume", in: app)
        app.buttons["naval.capture.continue"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["naval.ship.owner.0"].value as? String, "0")
        try sailCapturedHull(in: app)
    }

    private func sailCapturedHull(in app: XCUIApplication) throws {
        app.buttons["naval.fleet.open"].tap()
        let hull = app.buttons["naval.fleet.ship.0"]
        XCTAssertTrue(hull.waitForExistence(timeout: 5))
        hull.tap()
        let targets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        XCTAssertTrue(targets.firstMatch.waitForExistence(timeout: 5))
        let target = try XCTUnwrap(targets.allElementsBoundByIndex.first {
            $0.isHittable && ($0.value as? String ?? "").contains("2 hexes of travel")
        }, "The gained vessel must expose a reachable two-hex destination")
        let coordinate = try XCTUnwrap(target.identifier.split(separator: ".").last)
            .split(separator: "_").compactMap { Int($0) }
        XCTAssertEqual(coordinate.count, 2)
        let original = app.otherElements["naval.ship.position.0"].value as? String
        target.tap()
        XCTAssertEqual(app.otherElements["naval.ship.position.0"].value as? String, original)
        app.buttons["board-decision.confirm"].tap()
        let expected = "q=\(coordinate[0]);r=\(coordinate[1]);steps=0"
        XCTAssertEqual(app.otherElements["naval.ship.position.0"].value as? String, expected)
        retain("Naval — acknowledged gained vessel commits its two-hex voyage", in: app)
        coldResume(app)
        XCTAssertTrue(app.otherElements["naval.ship.position.0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.otherElements["naval.ship.position.0"].value as? String, expected)
        XCTAssertFalse(app.alerts["naval.capture.receipt"].exists)
    }

    private func launchLoss(largestText: Bool) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalShipLossPosition"]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func coldResume(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
    }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable)
    }

    private func retain(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
