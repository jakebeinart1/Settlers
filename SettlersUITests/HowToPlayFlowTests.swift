import XCTest

/// The rules screen a new player reaches from the main menu's corner: the
/// walkthrough clicks through to the end and hands over to Rules, Details
/// disclosures open and close, Modes lists Classic, and Close returns to the
/// menu. Screenshots are attached for visual review of each tab.
@MainActor
final class HowToPlayFlowTests: XCTestCase {
    private static let walkthroughSteps = 10

    func testWalkthroughRulesAndModesAreReachableFromTheMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()

        let mainMenu = app.otherElements["screen.main-menu"]
        XCTAssertTrue(mainMenu.waitForExistence(timeout: 5))
        attach(app, "main-menu")
        app.buttons["main-menu.how-to-play"].tap()
        XCTAssertTrue(app.otherElements["screen.how-to-play"].waitForExistence(timeout: 5))
        let next = app.buttons["how-to-play.next"]
        for step in 1..<Self.walkthroughSteps {
            attach(app, "walkthrough-\(step)")
            next.tap()
        }
        XCTAssertTrue(next.label.contains("See the Rules"), "last step should hand over to Rules, got \(next.label)")
        attach(app, "walkthrough-last")
        next.tap()

        let goalDetails = app.buttons["how-to-play.details.goal"]
        XCTAssertTrue(goalDetails.waitForExistence(timeout: 2), "Next on the last step should open Rules")
        goalDetails.tap()
        let goalBody = app.otherElements["how-to-play.details-body.goal"]
        XCTAssertTrue(goalBody.waitForExistence(timeout: 2), "Details should open")
        attach(app, "rules-details-open")
        goalDetails.tap()
        XCTAssertTrue(goalBody.waitForNonExistence(timeout: 2), "Details should close again")

        // The board prints no pips, so the odds live in a chart under "Your turn".
        let turnDetails = app.buttons["how-to-play.details.turn"]
        XCTAssertTrue(turnDetails.waitForExistence(timeout: 2))
        turnDetails.tap()
        XCTAssertTrue(app.descendants(matching: .any)["how-to-play.roll-odds"].waitForExistence(timeout: 2),
                      "Your turn details should show the roll-odds chart")
        attach(app, "rules-roll-odds")
        turnDetails.tap()

        app.buttons["how-to-play.tab.modes"].tap()
        XCTAssertTrue(app.buttons["how-to-play.details.classic"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["how-to-play.details.conquest"].exists)
        attach(app, "modes")

        app.buttons["how-to-play.close"].tap()
        XCTAssertTrue(mainMenu.waitForExistence(timeout: 2))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
