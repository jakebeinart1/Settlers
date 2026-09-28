import XCTest

@MainActor
final class ResourceProductionFlowTests: XCTestCase {
    func testRealRollShowsCityAndSettlementGainsWithoutMovingBoard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaProductionPosition"]
        app.launch()
        let roll = app.buttons["Roll Dice"]
        XCTAssertTrue(roll.waitForExistence(timeout: 10))
        let board = app.otherElements["board.surface"]
        let before = board.frame
        roll.tap()
        let receipt = app.descendants(matching: .any)["production.receipt"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 2))
        XCTAssertTrue(receipt.label.contains("2 ore"))
        XCTAssertTrue(receipt.label.contains("1 grain"))
        XCTAssertEqual(app.otherElements["human-resource.ore"].value as? String, "2")
        XCTAssertEqual(app.otherElements["human-resource.grain"].value as? String, "1")
        XCTAssertEqual(board.frame, before)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Real roll city plus two settlement plus one"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertTrue(receipt.waitForNonExistence(timeout: 5))
        XCTAssertEqual(board.frame, before)
        XCTAssertEqual(app.otherElements["human-resource.ore"].value as? String, "2")
    }
}
