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
        let receipt = app.otherElements["naval.capture.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 20), "The ordinary rival must roll 11 and commit capture")
        XCTAssertTrue(app.staticTexts["Your ship was stolen"].exists)
        XCTAssertTrue(app.otherElements["naval.capture.location"].exists)
        XCTAssertFalse(app.buttons["board-decision.confirm"].exists)
        XCTAssertFalse(app.buttons["board.ship.0"].isHittable)
        retain("Naval — actual rival capture explains the lost vessel", in: app)
        coldResume(app)
        XCTAssertTrue(app.otherElements["naval.capture.receipt"].waitForExistence(timeout: 10))
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
        XCTAssertTrue(app.otherElements["naval.capture.receipt"].waitForExistence(timeout: 20))
        let acknowledgement = app.buttons["naval.capture.continue"]
        XCTAssertTrue(acknowledgement.isHittable)
        XCTAssertTrue(app.frame.insetBy(dx: 1, dy: 1).contains(acknowledgement.frame))
        retain("Naval — maximum text ship loss keeps Continue visible", in: app)
        app.swipeUp()
        XCTAssertTrue(acknowledgement.isHittable)
        retain("Naval — maximum text ownership and location are scrollable", in: app)
        acknowledgement.tap()
        XCTAssertFalse(app.otherElements["naval.capture.receipt"].exists)
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
