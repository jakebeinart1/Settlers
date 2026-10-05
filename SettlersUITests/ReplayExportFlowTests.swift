import XCTest

/// One launch exercises the public video product and the warned raw option.
/// The 40-move fixture is deliberately PARTIAL despite its JSONL end marker.
@MainActor
final class ReplayExportFlowTests: XCTestCase {
    func testExportOffersPrivateSafeDefaultsPreviewAndWarnedDiagnostics() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaSeedGameHistory", "-qaShowReplay"]
        app.launch()
        let export = app.buttons["replay.export"]
        XCTAssertTrue(export.waitForExistence(timeout: 20))
        export.tap()

        let names = app.switches["replay-export.names"]
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        XCTAssertEqual(names.value as? String, "0", "Player and Ghost names must be excluded by default")
        let diagnostic = app.buttons["replay-export.diagnostic"]
        diagnostic.tap()
        let warning = app.alerts["Share diagnostic recording?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 3))
        XCTAssertTrue(warning.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "hidden hand")).firstMatch.exists)
        warning.buttons["Cancel"].tap()

        app.buttons["replay-export.create"].tap()
        let preview = app.descendants(matching: .any).matching(identifier: "replay-export.preview").firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 90), "The export never produced an MP4 preview")
        XCTAssertTrue(app.staticTexts["Partial replay"].exists, "The short fixture must not be advertised as a complete game")
        XCTAssertTrue(app.buttons["replay-export.share"].exists)
        XCTAssertFalse(app.buttons["replay-export.cancel"].exists)
        app.buttons["replay-export.share"].tap()
        let activityList = app.otherElements["ActivityListView"]
        XCTAssertTrue(activityList.waitForExistence(timeout: 5), "Share must present the native sheet with the actual MP4")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Public replay MP4 — native share sheet"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let close = app.buttons["Close"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(activityList.waitForNonExistence(timeout: 5))
        XCTAssertTrue(preview.exists, "Dismissing Share must keep the generated video for another attempt")
        app.buttons["Done"].tap()
        XCTAssertTrue(export.waitForExistence(timeout: 5), "Closing export must return to the replay")
    }
}
