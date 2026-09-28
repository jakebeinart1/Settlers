import XCTest

/// Tap the reported 2:1 trade through the real popup, not a parallel model.
@MainActor
final class BankTradeFlowTests: XCTestCase {
    func testSixGrainCanBuyThreeOre() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaBankTradePosition"]
        app.launch()
        let trade = app.buttons["Trade"]
        XCTAssertTrue(trade.waitForExistence(timeout: 10))
        trade.tap()
        app.buttons["Bank"].tap()
        let grain = app.buttons["trade.bank.give.grain"]
        XCTAssertTrue(grain.waitForExistence(timeout: 3))
        grain.tap()
        grain.tap()
        grain.tap()
        XCTAssertEqual(grain.value as? String, "6")
        let ore = app.buttons["trade.bank.get.ore"]
        ore.tap()
        ore.tap()
        ore.tap()
        XCTAssertEqual(ore.value as? String, "3", "Each tap must add one, not toggle 1 back to zero")
        XCTAssertTrue(app.buttons["Trade with Bank"].isEnabled)
        app.buttons["Trade with Bank"].tap()
        XCTAssertTrue(app.staticTexts["Trade complete"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["6 Grain"].exists)
        XCTAssertTrue(app.staticTexts["3 Ore"].exists)
        XCTAssertEqual(app.otherElements["human-resource.grain"].value as? String, "1")
        XCTAssertEqual(app.otherElements["human-resource.ore"].value as? String, "3")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Completed bank trade"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Trade again"].tap()
        XCTAssertFalse(app.staticTexts["Trade complete"].exists)
        XCTAssertEqual(app.buttons["trade.bank.get.ore"].value as? String, "0")
        XCTAssertFalse(app.buttons["Trade with Bank"].isEnabled)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["End Turn"].exists)
    }

    func testBankAddRemoveAndSameResourceExclusion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaBankTradePosition"]
        app.launch()
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: 10))
        app.buttons["Trade"].tap()
        app.buttons["Bank"].tap()
        let grain = app.buttons["trade.bank.give.grain"]
        grain.tap()
        grain.tap()
        grain.tap()
        XCTAssertFalse(grain.isEnabled)
        XCTAssertFalse(app.buttons["trade.bank.get.grain"].isEnabled)
        let ore = app.buttons["trade.bank.get.ore"]
        ore.tap()
        ore.tap()
        ore.tap()
        XCTAssertFalse(ore.isEnabled)
        app.buttons["trade.bank.get.remove.ore"].tap()
        XCTAssertEqual(ore.value as? String, "2")
        app.buttons["trade.bank.give.remove.grain"].tap()
        XCTAssertEqual(grain.value as? String, "4")
        XCTAssertTrue(app.buttons["Trade with Bank"].isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Bank quantity controls"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Trade with Bank"].tap()
        XCTAssertTrue(app.buttons["Close trade"].waitForExistence(timeout: 3))
        app.buttons["Close trade"].tap()
        XCTAssertFalse(app.staticTexts["Trade complete"].exists)
        XCTAssertEqual(app.otherElements["human-resource.grain"].value as? String, "3")
        XCTAssertEqual(app.otherElements["human-resource.ore"].value as? String, "2")
    }

    func testHelpCanScrollWithoutHidingCloseAndPlayerOffersCannotOverlap() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaBankTradePosition"]
        app.launch()
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: 10))
        app.buttons["Trade"].tap()
        app.buttons["trade.give.grain"].tap()
        XCTAssertFalse(app.buttons["trade.want.grain"].isEnabled)
        app.buttons["trade.want.ore"].tap()
        app.buttons["Bank"].tap()
        app.buttons["How bank trading works"].tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.isHittable)
        XCTAssertTrue(app.frame.contains(close.frame))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Trade help with pinned footer"
        attachment.lifetime = .keepAlways
        add(attachment)
        close.tap()
        XCTAssertTrue(app.buttons["End Turn"].exists)
    }

    func testConfirmedPlayerTradeShowsActualReceiptAndClose() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaBankTradePosition"]
        app.launch()
        XCTAssertTrue(app.buttons["Trade"].waitForExistence(timeout: 10))
        app.buttons["Trade"].tap()
        for _ in 0..<6 { app.buttons["trade.give.grain"].tap() }
        app.buttons["trade.want.ore"].tap()
        app.buttons["Propose to Bots"].tap()
        let confirm = app.buttons["Confirm Trade"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Trade complete"].exists, "Willingness is not a completed exchange")
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Trade complete"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["6 Grain"].exists)
        XCTAssertTrue(app.staticTexts["1 Ore"].exists)
        XCTAssertTrue(app.buttons["Trade again"].exists)
        app.buttons["Close trade"].tap()
        XCTAssertEqual(app.otherElements["human-resource.grain"].value as? String, "1")
        XCTAssertEqual(app.otherElements["human-resource.ore"].value as? String, "1")
    }
}
