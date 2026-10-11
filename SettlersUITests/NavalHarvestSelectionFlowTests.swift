import XCTest
import UIKit

/// Real quantity taps keep the hand unchanged, expose completion in both
/// locations, permit editing, and collect the whole obligation with one tap.
@MainActor
final class NavalHarvestSelectionFlowTests: XCTestCase {
    private static let maximumCollectionHeight: CGFloat = 100
    private static let minimumInformationalTextContrast = 4.5
    func testCityHarvestDraftResetsOnColdResumeAndBothChoicesCollectOnce() {
        let app = launch("-qaNavalCityResourcePosition")
        let ore = app.buttons["naval.resource.ore"]
        XCTAssertEqual(app.staticTexts["naval.resource.source"].label, "City harvest")
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 2 resources"))
        XCTAssertEqual(app.descendants(matching: .any)["naval.resource.progress"].value as? String, "0 of 2 selected. 2 remaining.")
        retain("Voyages — city chooses two resources with clear progress", app: app)
        let before = resource("ore", in: app)
        let grainBefore = resource("grain", in: app)
        ore.tap()
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].exists)
        XCTAssertEqual(resource("ore", in: app), before)
        XCTAssertEqual(app.descendants(matching: .any)["naval.resource.progress"].value as? String, "1 of 2 selected. 1 remaining.")
        XCTAssertEqual(app.buttons["naval.resource.confirm"].value as? String, "1 of 2 selected")
        XCTAssertFalse(app.buttons["naval.resource.confirm"].isEnabled, "Every card must be selected before one confirmation")
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(ore.waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), before)
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 2 resources"))
        XCTAssertEqual(app.descendants(matching: .any)["naval.resource.progress"].value as? String, "0 of 2 selected. 2 remaining.")
        retain("Voyages — uncommitted city harvest resets after cold resume", app: app)
        XCTAssertFalse(app.buttons["naval.resource.confirm"].isEnabled)
        ore.tap()
        app.buttons["naval.resource.grain"].tap()
        XCTAssertEqual(app.buttons["naval.resource.confirm"].value as? String, "2 of 2 selected")
        retain("Voyages — complete city choice before one collection", app: app)
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), before + 1)
        XCTAssertEqual(resource("grain", in: app), grainBefore + 1)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), before + 1)
        XCTAssertEqual(resource("grain", in: app), grainBefore + 1)
    }

    func testMixedHarvestCountsEveryPickAndAllowsEditingAtFullAllocation() {
        let app = launch()
        let confirm = app.buttons["naval.resource.confirm"]
        let before = holdings(app)
        XCTAssertEqual(app.staticTexts["naval.resource.source"].label, "1 settlement + 1 city")
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 3 resources"))
        assertProgress(0, required: 3, app: app)
        retain("Harvest — mixed buildings before selection", app: app)
        app.buttons["naval.resource.ore"].tap()
        assertProgress(1, required: 3, app: app)
        retain("Harvest — one of three selected", app: app)
        app.buttons["naval.resource.add.ore"].tap()
        assertProgress(2, required: 3, app: app)
        retain("Harvest — two identical resources selected", app: app)
        app.buttons["naval.resource.grain"].tap()
        assertProgress(3, required: 3, app: app)
        XCTAssertEqual(holdings(app), before)
        XCTAssertFalse(app.buttons["naval.resource.ore"].isEnabled)
        let remove = app.buttons["naval.resource.remove.ore"]
        XCTAssertTrue(remove.isEnabled && remove.isHittable)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.width, 44)
        retain("Harvest — complete three-card choice", app: app)
        remove.tap()
        assertProgress(2, required: 3, app: app)
        app.buttons["naval.resource.add.lumber"].tap()
        assertProgress(3, required: 3, app: app)
        XCTAssertEqual(holdings(app), before)
        confirm.tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        let after = holdings(app)
        XCTAssertEqual(after, before.enumerated().map { index, count in count + ([1, 2, 3].contains(index) ? 1 : 0) })
        retain("Harvest — one collection credits all three resources", app: app)
        coldResume(app)
        XCTAssertEqual(holdings(app), after)
        XCTAssertFalse(app.buttons["naval.resource.confirm"].exists)
    }

    func testBankShortageAllowsOnlyStockedQuantitiesAndExplainsReducedCollection() {
        let app = launch(extra: ["-qaNavalHarvestBankScarce"])
        let before = holdings(app)
        XCTAssertTrue(app.staticTexts["naval.resource.bank-shortage"].exists)
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 2 resources"))
        assertProgress(0, required: 2, app: app)
        XCTAssertFalse(app.buttons["naval.resource.brick"].isEnabled)
        XCTAssertFalse(app.buttons["naval.resource.add.brick"].isEnabled)
        app.buttons["naval.resource.add.ore"].tap()
        XCTAssertFalse(app.buttons["naval.resource.ore"].isEnabled, "The only Ore is already reserved")
        XCTAssertFalse(app.buttons["naval.resource.add.ore"].isEnabled)
        assertProgress(1, required: 2, app: app)
        app.buttons["naval.resource.remove.ore"].tap()
        assertProgress(0, required: 2, app: app)
        XCTAssertTrue(app.buttons["naval.resource.ore"].isEnabled)
        XCTAssertTrue(app.buttons["naval.resource.add.ore"].isEnabled)
        app.buttons["naval.resource.ore"].tap()
        app.buttons["naval.resource.add.grain"].tap()
        assertProgress(2, required: 2, app: app)
        XCTAssertEqual(holdings(app), before)
        retain("Harvest — scarce bank explains two available cards", app: app)
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5), "Empty supply cannot leave a mandatory harvest blocked")
        XCTAssertEqual(holdings(app), before.enumerated().map { index, count in count + ([2, 3].contains(index) ? 1 : 0) })
    }

    func testRightSidePlusAndMinusRemainSeparateAndAlignedForEveryResource() {
        let app = launch()
        let scroll = app.scrollViews["naval.resource.scroll"]
        var plusX: CGFloat?
        var minusX: CGFloat?
        for resource in ["brick", "lumber", "ore", "grain", "wool"] {
            let row = app.buttons["naval.resource.\(resource)"]
            let plus = app.buttons["naval.resource.add.\(resource)"]
            let minus = app.buttons["naval.resource.remove.\(resource)"]
            XCTAssertTrue(plus.exists && plus.isHittable)
            XCTAssertGreaterThanOrEqual(plus.frame.width, 44)
            XCTAssertGreaterThanOrEqual(plus.frame.height, 44)
            XCTAssertGreaterThanOrEqual(minus.frame.width, 44)
            XCTAssertGreaterThanOrEqual(minus.frame.height, 44)
            XCTAssertEqual(row.frame.midY, plus.frame.midY, accuracy: 1)
            XCTAssertEqual(plus.frame.midY, minus.frame.midY, accuracy: 1)
            XCTAssertLessThanOrEqual(row.frame.maxX, minus.frame.minX)
            XCTAssertLessThanOrEqual(minus.frame.maxX, plus.frame.minX)
            XCTAssertTrue(scroll.frame.contains(plus.frame) && scroll.frame.contains(minus.frame))
            XCTAssertFalse(minus.isEnabled)
            if let plusX, let minusX {
                XCTAssertEqual(plus.frame.minX, plusX, accuracy: 1)
                XCTAssertEqual(minus.frame.minX, minusX, accuracy: 1)
            }
            plusX = plus.frame.minX; minusX = minus.frame.minX
            plus.tap()
            assertProgress(1, required: 3, app: app)
            XCTAssertEqual(app.staticTexts["naval.resource.quantity.\(resource)"].value as? String, "1")
            minus.tap()
            assertProgress(0, required: 3, app: app)
            XCTAssertEqual(app.staticTexts["naval.resource.quantity.\(resource)"].value as? String, "0")
        }
        retain("Harvest — explicit right-side plus and minus for every resource", app: app)
        let orePlus = app.buttons["naval.resource.add.ore"]
        orePlus.tap()
        XCTAssertEqual(app.staticTexts["naval.resource.quantity.ore"].value as? String, "1")
        app.buttons["naval.resource.remove.ore"].tap()
        assertProgress(0, required: 3, app: app)
        XCTAssertEqual(app.staticTexts["naval.resource.quantity.ore"].value as? String, "0")
        let minus = app.buttons["naval.resource.remove.ore"]
        XCTAssertFalse(minus.isEnabled)
        minus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        assertProgress(0, required: 3, app: app)
    }

    func testSelectedQuantitiesAndStockStayReadableBeforeSingleCollection() throws {
        let app = launch()
        let ore = app.buttons["naval.resource.ore"]
        ore.tap()
        assertProgress(1, required: 3, app: app)
        try assertSelectedRowContrast(ore, quantity: app.staticTexts["naval.resource.quantity.ore"], name: "Ore one selected")
        ore.tap()
        app.buttons["naval.resource.grain"].tap()
        assertProgress(3, required: 3, app: app)
        for resource in ["ore", "grain"] {
            let row = app.buttons["naval.resource.\(resource)"]
            XCTAssertFalse(row.isEnabled)
            XCTAssertFalse(app.buttons["naval.resource.add.\(resource)"].isEnabled)
            try assertSelectedRowContrast(row, quantity: app.staticTexts["naval.resource.quantity.\(resource)"],
                                          name: "\(resource) at complete allocation")
        }
        try assertWhiteContrast(app.buttons["naval.resource.confirm"],
                                region: CGRect(x: 0.14, y: 0.55, width: 0.78, height: 0.28),
                                name: "Completed collection progress")
        retain("Harvest — selected quantities and stock with readable white ink", app: app)
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
    }

    func testPreviouslyCollectedUnitSurvivesColdResumeWithoutBeingCollectedAgain() {
        let app = launch(extra: ["-qaNavalHarvestPartial"])
        XCTAssertEqual(app.staticTexts["naval.resource.previous-collection"].label, "1 of 3 already collected")
        let before = holdings(app)
        assertProgress(0, required: 2, app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["naval.resource.previous-collection"].label, "1 of 3 already collected")
        XCTAssertEqual(holdings(app), before)
        app.buttons["naval.resource.ore"].tap()
        app.buttons["naval.resource.ore"].tap()
        assertProgress(2, required: 2, app: app)
        retain("Harvest — a legacy partial collection keeps its credited card", app: app)
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(holdings(app)[2], before[2] + 2)
    }

    func testMaximumTextKeepsProgressEditingAndConfirmationReachable() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let before = holdings(app)
        let confirm = app.buttons["naval.resource.confirm"]
        XCTAssertTrue(confirm.isHittable)
        XCTAssertLessThanOrEqual(confirm.frame.height, Self.maximumCollectionHeight,
                                 "The capped collection scaffold cannot consume the choice region")
        assertProgress(0, required: 3, app: app)
        retain("Harvest — maximum text before selection", app: app)
        for index in 1...3 {
            let identifier = index == 1 ? "naval.resource.wool" : "naval.resource.add.wool"
            reveal(identifier, app: app)
            app.buttons[identifier].tap()
            assertProgress(index, required: 3, app: app)
            XCTAssertTrue(confirm.isHittable, "The complete-choice action must stay pinned")
            XCTAssertLessThanOrEqual(confirm.frame.height, Self.maximumCollectionHeight)
            retain("Harvest — maximum text \(index) of 3 identical resources selected", app: app)
        }
        let remove = app.buttons["naval.resource.remove.wool"]
        reveal("naval.resource.remove.wool", app: app)
        XCTAssertTrue(remove.isEnabled && remove.isHittable)
        remove.tap()
        assertProgress(2, required: 3, app: app)
        reveal("naval.resource.add.ore", app: app)
        app.buttons["naval.resource.add.ore"].tap()
        assertProgress(3, required: 3, app: app)
        retain("Harvest — maximum text preserves editable quantities and pinned collection", app: app)
        confirm.tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        let expected = before.enumerated().map { index, count in count + (index == 4 ? 2 : (index == 2 ? 1 : 0)) }
        XCTAssertEqual(holdings(app), expected)
        coldResume(app)
        XCTAssertEqual(holdings(app), expected)
    }

    func testLargestStandardTextPreservesRightSideControlsAndFullLabels() throws {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"])
        for resource in ["brick", "lumber", "ore", "grain", "wool"] {
            reveal("naval.resource.add.\(resource)", app: app)
            let plus = app.buttons["naval.resource.add.\(resource)"]
            let minus = app.buttons["naval.resource.remove.\(resource)"]
            let row = app.buttons["naval.resource.\(resource)"]
            XCTAssertEqual(row.frame.midY, plus.frame.midY, accuracy: 1)
            XCTAssertLessThanOrEqual(minus.frame.maxX, plus.frame.minX)
            plus.tap()
            assertProgress(1, required: 3, app: app)
            XCTAssertEqual(app.staticTexts["naval.resource.quantity.\(resource)"].value as? String, "1")
            minus.tap()
            assertProgress(0, required: 3, app: app)
        }
        reveal("naval.resource.ore", app: app)
        try app.performAccessibilityAudit(for: [.textClipped])
        retain("Harvest — largest standard text keeps names and right-side controls", app: app)
    }

    private func launch(_ fixture: String = "-qaNavalMixedResourcePosition", extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               fixture] + extra
        app.launch()
        XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 15))
        return app
    }

    private func assertProgress(_ selected: Int, required: Int, app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) {
        let progress = app.descendants(matching: .any)["naval.resource.progress"]
        XCTAssertEqual(progress.value as? String, "\(selected) of \(required) selected. \(required - selected) remaining.", file: file, line: line)
        let confirm = app.buttons["naval.resource.confirm"]
        XCTAssertEqual(confirm.value as? String, "\(selected) of \(required) selected", file: file, line: line)
        XCTAssertEqual(confirm.isEnabled, selected == required, file: file, line: line)
    }

    private func resource(_ resource: String, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) -> Int {
        NavalResourceOracle.ownedCount(resource, in: app, file: file, line: line)
    }

    private func holdings(_ app: XCUIApplication) -> [Int] {
        ["brick", "lumber", "ore", "grain", "wool"].map {
            resource($0, in: app)
        }
    }

    private func reveal(_ identifier: String, app: XCUIApplication) {
        NavalResourceOracle.revealHarvestControl(app.buttons[identifier], in: app)
    }

    private func coldResume(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func assertSelectedRowContrast(_ row: XCUIElement, quantity: XCUIElement, name: String) throws {
        // Separate interior crops prevent the white title or gold frame from
        // masking a low-contrast quantity or owned/bank caption regression.
        XCTAssertTrue(quantity.exists && quantity.isHittable)
        try assertWhiteContrast(quantity, region: CGRect(x: 0, y: 0, width: 1, height: 1),
                                name: "\(name) quantity")
        try assertWhiteContrast(row, region: CGRect(x: 0.14, y: 0.12, width: 0.8, height: 0.42),
                                name: "\(name) title")
        try assertWhiteContrast(row, region: CGRect(x: 0.14, y: 0.6, width: 0.8, height: 0.3),
                                name: "\(name) owned and bank caption")
    }

    private func assertWhiteContrast(_ element: XCUIElement, region: CGRect, name: String) throws {
        let screenshot = element.screenshot().image
        let source = try XCTUnwrap(screenshot.cgImage)
        let bounds = CGRect(x: region.minX * CGFloat(source.width), y: region.minY * CGFloat(source.height),
                            width: region.width * CGFloat(source.width), height: region.height * CGFloat(source.height))
        let cropped = UIImage(cgImage: try XCTUnwrap(source.cropping(to: bounds.integral)))
        let attachment = XCTAttachment(image: cropped)
        attachment.name = "\(name) — actual rendered contrast crop"
        attachment.lifetime = .keepAlways
        add(attachment)
        let ratio = try XCTUnwrap(WhiteTextContrast.ratio(in: cropped), "\(name) must contain actual white text")
        print("Live selected harvest \(name): \(ratio):1")
        XCTAssertGreaterThanOrEqual(ratio, Self.minimumInformationalTextContrast,
                                    "Informational text must retain contrast on its painted backing")
    }
}
