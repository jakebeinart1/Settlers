import XCTest

/// Native taps prove that maritime controls commit rules transactions, while
/// screenshots retain the actual simulator geometry for visual review.
@MainActor
final class NavalFlowTests: XCTestCase {
    // AX rectangles subtract screen-space floating-point origins. This
    // nanoscopic allowance rejects real undersized controls without treating
    // 43.999999999999986 as a smaller physical hit region than 44 points.
    private static let frameRoundingTolerance: CGFloat = 1e-9

    /// All three coordinates belong to the home island, so this is an actual
    /// inland corner rather than a coastal vertex whose artwork looks central.
    /// Start an ordinary seeded match; no fixture installs a settlement or ship.
    func testFreshNavalSetupAllowsInlandSettlementPreviewClearConfirmAndColdResume() {
        let app = launch("-qaNavalSeed=7501", extra: ["-qaNavalFamily=archipelago"])
        app.buttons["naval.home"].tap()
        let inlandIdentifier = "board.vertex.-1_0.0_-1.0_0"
        let inland = app.buttons[inlandIdentifier]
        XCTAssertTrue(inland.waitForExistence(timeout: 5), "Setup excluded a corner touching three home-island land tiles")
        XCTAssertTrue(inland.isEnabled && inland.isHittable)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.vertex.")).count, 54,
                       "Fresh home-island setup must offer every land corner, including the interior")
        XCTAssertFalse(app.staticTexts["Choose a highlighted coastal corner."].exists)
        XCTAssertEqual(charted(in: app), 19)
        retainScreenshot("Voyages — inland home corners are legal at setup", app: app)
        assertInlandPreviewCanBeCleared(inland, in: app)
        inland.tap()
        app.buttons["board-decision.confirm"].tap()
        let roads = assertInlandOpeningRoads(in: app, settlementIdentifier: inlandIdentifier)
        retainScreenshot("Voyages — confirmed inland settlement and adjacent road choices", app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: 5))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.home"].waitForExistence(timeout: 5))
        XCTAssertEqual(assertInlandOpeningRoads(in: app, settlementIdentifier: inlandIdentifier), roads,
                       "Cold resume must retain the actual inland settlement and its mandatory adjacent road")
        retainScreenshot("Voyages — inland settlement persists through cold resume", app: app)
    }

    private func assertInlandPreviewCanBeCleared(_ inland: XCUIElement, in app: XCUIApplication) {
        let confirm = app.buttons["board-decision.confirm"]
        let preview = app.otherElements["board.building-preview"]
        let resources = ["brick", "lumber", "ore", "grain", "wool"]
        let holdings = resources.map { resource($0, in: app) }
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertFalse(preview.exists)
        inland.tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 2))
        XCTAssertEqual(inland.value as? String, "Selected")
        XCTAssertTrue(confirm.isEnabled && confirm.isHittable)
        XCTAssertEqual(charted(in: app), 19, "A preview must not uncover mist")
        XCTAssertEqual(resources.map { resource($0, in: app) }, holdings)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.edge.")).firstMatch.exists,
                       "An unconfirmed inland settlement must not open road placement")
        app.buttons["board-decision.clear"].tap()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 2))
        XCTAssertEqual(inland.value as? String, "Available")
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertEqual(charted(in: app), 19)
        XCTAssertEqual(resources.map { resource($0, in: app) }, holdings)
    }

    private func assertInlandOpeningRoads(in app: XCUIApplication, settlementIdentifier: String) -> [String] {
        let roads = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.edge."))
        XCTAssertTrue(roads.firstMatch.waitForExistence(timeout: 5), "Confirmed inland setup must advance to an adjacent road")
        let identifiers = roads.allElementsBoundByIndex.map(\.identifier).sorted()
        XCTAssertEqual(identifiers.count, 3)
        XCTAssertTrue(identifiers.allSatisfy { $0.contains(settlementIdentifier) },
                      "Road targets must meet the inland settlement that was actually confirmed")
        XCTAssertFalse(app.otherElements["board.building-preview"].exists)
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
        XCTAssertFalse(app.buttons["board-decision.cancel"].exists, "The adjacent opening road is mandatory")
        XCTAssertEqual(charted(in: app), 19, "A central inland settlement must not expose distant sea")
        return identifiers
    }

    func testNewSettlementRevealsFromItsActualCornerOnlyAfterConfirmation() {
        let app = launch("-qaNavalSeed=19")
        XCTAssertEqual(charted(in: app), 19)
        let corner = app.buttons["board.vertex.1_1.2_0.2_1"]
        XCTAssertTrue(corner.waitForExistence(timeout: 5))
        XCTAssertTrue(corner.isHittable)
        corner.tap()
        XCTAssertEqual(corner.value as? String, "Selected")
        XCTAssertEqual(charted(in: app), 19, "A settlement preview must not discover terrain")
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.isEnabled && confirm.isHittable)
        confirm.tap()
        let revealed = NSPredicate { _, _ in self.charted(in: app) == 25 }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: revealed, object: nil)], timeout: 5), .completed)
        XCTAssertEqual(charted(in: app), 25, "This actual corner discovers six sea hexes, not the legacy thirteen")
        retainScreenshot("Voyages — exact corner reveals six nearby sea hexes", app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 5))
        XCTAssertEqual(charted(in: app), 25, "Corner discoveries remain public after a cold resume")
    }

    func testShippingSetupSelectsFamilyTogglesAndExpertThenResumes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame", "-qaNavalSeed=7501"]
        app.launch()
        let naval = app.buttons["new-game.rules.naval"]
        XCTAssertTrue(naval.waitForExistence(timeout: 10))
        reveal(naval, in: app)
        XCTAssertEqual(naval.label, "Naval")
        XCTAssertGreaterThanOrEqual(naval.frame.height, 44)
        for rule in ["standard", "conquest"] {
            let option = app.buttons["new-game.rules.\(rule)"]
            XCTAssertTrue(option.exists)
            XCTAssertEqual(option.frame.midY, naval.frame.midY, accuracy: 1)
        }
        retainScreenshot("Naval — Rules option beside Standard and Conquest", app: app)
        naval.tap()
        XCTAssertTrue(naval.isSelected)
        XCTAssertTrue(app.staticTexts["new-game.mode.islands"].exists)
        XCTAssertEqual(app.buttons["About Game Mode"].frame.minX,
                       app.buttons["About Rules"].frame.minX, accuracy: 1,
                       "The island-world label must preserve the settings label column")
        XCTAssertFalse(app.buttons["new-game.mode.naval"].exists)
        XCTAssertFalse(app.buttons["new-game.naval.fog"].exists)
        openNavalSettings(in: app)
        let family = app.buttons["new-game.naval.family.twinIslands"]
        reveal(family, in: app)
        XCTAssertGreaterThanOrEqual(family.frame.height, 44)
        family.tap()
        for identifier in ["new-game.naval.fog", "new-game.naval.resources"] {
            let toggle = app.buttons[identifier]
            reveal(toggle, in: app)
            XCTAssertEqual(toggle.value as? String, "On")
            toggle.tap()
            XCTAssertEqual(toggle.value as? String, "Off")
        }
        retainScreenshot("Voyages — advanced island options", app: app)
        app.buttons["new-game.naval.advanced.done"].tap()
        reveal(app.buttons["Expert"], in: app)
        app.buttons["Expert"].tap()
        reveal(app.buttons["As Shown"], in: app)
        app.buttons["As Shown"].tap()
        retainScreenshot("Voyages — match options", app: app)
        app.buttons["new-game.start"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 10))
        XCTAssertEqual(charted(in: app), 169)
        retainScreenshot("Voyages — clear Twin Islands", app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 10))
        XCTAssertEqual(charted(in: app), 169)
        assertNavalSetupPrefill(in: app)
    }

    private func assertNavalSetupPrefill(in app: XCUIApplication) {
        app.buttons["game.settings"].tap()
        app.buttons["in-game-settings.quit"].tap()
        app.buttons["Main Menu"].tap()
        app.buttons["main-menu.new-game"].tap()
        let naval = app.buttons["new-game.rules.naval"]
        XCTAssertTrue(naval.waitForExistence(timeout: 5))
        reveal(naval, in: app)
        XCTAssertTrue(naval.isSelected, "Saved naval setup must reopen on Rules → Naval")
        XCTAssertEqual(app.buttons["new-game.naval.advanced"].value as? String, "Twin Islands · Mist off · Resources off")
        openNavalSettings(in: app)
        let family = app.buttons["new-game.naval.family.twinIslands"]
        reveal(family, in: app)
        XCTAssertTrue(family.isSelected)
        for identifier in ["new-game.naval.fog", "new-game.naval.resources"] {
            let toggle = app.buttons[identifier]
            reveal(toggle, in: app)
            XCTAssertEqual(toggle.value as? String, "Off")
        }
        retainScreenshot("Naval — saved Rules selection and island options", app: app)
        app.buttons["new-game.naval.advanced.done"].tap()
    }

    private func openNavalSettings(in app: XCUIApplication) {
        let advanced = app.buttons["new-game.naval.advanced"]
        reveal(advanced, in: app)
        advanced.tap()
        XCTAssertTrue(app.buttons["new-game.naval.advanced.done"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["new-game.start"].isHittable,
                       "Advanced Settings must not expose Start beneath the configuration panel")
    }

    func testBuyShipPreviewCancelSailAndColdResume() {
        let app = launch("-qaNavalVoyagePosition")
        let lumberBefore = resource("lumber", in: app)
        let chartedBefore = charted(in: app)
        app.buttons["Build"].tap()
        app.buttons["build.ship"].tap()
        tapOutwardSea(in: app)
        XCTAssertTrue(app.otherElements["board.ship-preview"].exists)
        XCTAssertEqual(resource("lumber", in: app), lumberBefore)
        XCTAssertEqual(charted(in: app), chartedBefore)
        app.buttons["board-decision.cancel"].tap()
        XCTAssertFalse(app.buttons["board.ship.0"].exists)
        XCTAssertEqual(charted(in: app), chartedBefore)
        app.buttons["Build"].tap()
        app.buttons["build.ship"].tap()
        tapOutwardSea(in: app)
        app.buttons["board-decision.confirm"].tap()
        XCTAssertTrue(app.buttons["board.ship.0"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("lumber", in: app), lumberBefore - 2)
        retainScreenshot("Voyages — launched vessel", app: app)
        for _ in 0..<2 {
            if shipPosition(0, in: app).contains("steps=0") { break }
            app.buttons["naval.fleet.open"].tap()
            let ship = app.buttons["naval.fleet.ship.0"]
            XCTAssertTrue(ship.waitForExistence(timeout: 3))
            ship.tap()
            let pose = app.otherElements["naval.camera.reference"].value as? String
            let discovered = charted(in: app)
            tapOutwardSea(in: app)
            XCTAssertEqual(charted(in: app), discovered, "A sailing proposal must not uncover terrain")
            XCTAssertTrue(app.buttons["board-decision.confirm"].isEnabled)
            app.buttons["board-decision.confirm"].tap()
            XCTAssertEqual(app.otherElements["naval.camera.reference"].value as? String, pose,
                           "Committed discovery must not change the camera")
        }
        let chartedAfter = charted(in: app)
        XCTAssertGreaterThan(chartedAfter, chartedBefore)
        app.buttons["naval.overview"].tap()
        retainScreenshot("Voyages — discovery and world overview", app: app)
        XCTAssertTrue(app.buttons["End Turn"].exists)
        let after = resource("lumber", in: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: 5))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("lumber", in: app), after)
        XCTAssertEqual(charted(in: app), chartedAfter)
        XCTAssertTrue(app.buttons["board.ship.0"].exists)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
    }

    func testWorldShipTouchOpensNearbyIdentityChooserBeforeSelectingOrFocusing() {
        let app = launch("-qaNavalAdjacentShipsPosition")
        app.buttons["naval.overview"].tap()
        let positions = [shipPosition(0, in: app), shipPosition(1, in: app)]
        let camera = app.otherElements["naval.camera.reference"].value as? String
        let first = app.buttons["board.ship.0"]
        XCTAssertGreaterThanOrEqual(first.frame.width + Self.frameRoundingTolerance, 44)
        XCTAssertGreaterThanOrEqual(first.frame.height + Self.frameRoundingTolerance, 44)
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["naval.nearby.ship.0"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["naval.nearby.ship.1"].exists)
        XCTAssertEqual(app.otherElements["naval.camera.reference"].value as? String, camera)
        XCTAssertEqual([shipPosition(0, in: app), shipPosition(1, in: app)], positions)
        XCTAssertFalse(app.buttons["board-decision.confirm"].exists,
                       "A crowded touch must not silently select whichever ship was drawn last")
        retainScreenshot("Voyages — nearby vessels at World zoom", app: app)
        app.buttons["naval.nearby.ship.0"].tap()
        XCTAssertTrue(app.buttons["board-decision.cancel"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
        app.buttons["board-decision.cancel"].tap()
        XCTAssertEqual([shipPosition(0, in: app), shipPosition(1, in: app)], positions)
    }

    func testStackedWorldChooserIncludesAdjacentHullAndMovesOnlyChosenIdentity() {
        let app = launch("-qaNavalStackedShipsPosition")
        app.buttons["naval.overview"].tap()
        let positions = (0..<3).map { shipPosition($0, in: app) }
        let adjacent = app.buttons["board.ship.1"]
        adjacent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        for id in 0..<3 { XCTAssertTrue(app.buttons["naval.nearby.ship.\(id)"].waitForExistence(timeout: 3)) }
        XCTAssertFalse(app.buttons["board-decision.confirm"].exists)
        app.buttons["naval.nearby.ship.2"].tap()
        app.buttons["naval.overview"].tap()
        let destination = chooseEachWorldSeaCenter(in: app, shipCount: 3)
        XCTAssertTrue(app.staticTexts["Sail your ship"].exists)
        let destinationTarget = app.buttons["board.tile.\(destination[0])_\(destination[1])"]
        let cost = (destinationTarget.value as? String ?? "").contains("2 hexes") ? 2 : 1
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertTrue(confirm.isHittable)
        confirm.tap()
        let expected = "q=\(destination[0]);r=\(destination[1]);steps=\(2 - cost)"
        let marker = app.otherElements["naval.ship.position.2"]
        let committed = marker.waitForExistence(timeout: 3) && marker.value as? String == expected
        if !committed {
            let wait = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: marker)
            if XCTWaiter.wait(for: [wait], timeout: 5) != .completed {
                retainScreenshot("Voyages — stacked confirmation failure", app: app)
                XCTFail("Ship 3 did not commit \(expected); actual \(marker.value ?? "missing")\n\(app.debugDescription)")
                return
            }
        }
        XCTAssertEqual(shipPosition(0, in: app), positions[0])
        XCTAssertEqual(shipPosition(1, in: app), positions[1])
        XCTAssertEqual(shipPosition(2, in: app), expected)
        retainScreenshot("Voyages — exact crowded-map sailing", app: app)
        let finalPosition = shipPosition(2, in: app)
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: 5))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 5))
        XCTAssertEqual(shipPosition(2, in: app), finalPosition)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
    }

    func testNearbyChooserKeepsEveryHullReachableAtMaximumTextWithoutCommitting() {
        let app = launch("-qaNavalStackedShipsPosition", extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let positions = (0..<3).map { shipPosition($0, in: app) }
        let chart = charted(in: app)
        let resources = ["brick", "lumber", "ore", "grain", "wool"]
        let holdings = resources.map { resource($0, in: app) }
        for prefix in ["naval.nearby", "naval.fleet"] {
            for id in 0..<3 {
                let chooser = openLargeFleet(prefix, in: app)
                selectWholeFleetRow(id, prefix: prefix, chooser: chooser, in: app)
                let confirm = app.buttons["board-decision.confirm"]
                XCTAssertFalse(confirm.isEnabled)
                tapOutwardSea(in: app)
                XCTAssertTrue(confirm.isEnabled)
                XCTAssertTrue(app.otherElements["board.ship-preview"].exists)
                XCTAssertEqual(charted(in: app), chart, "A large-text sailing draft must not reveal fog")
                XCTAssertTrue(app.buttons["board-decision.cancel"].isHittable)
                app.buttons["board-decision.cancel"].tap()
                XCTAssertEqual((0..<3).map { shipPosition($0, in: app) }, positions)
                XCTAssertEqual(charted(in: app), chart)
                XCTAssertEqual(resources.map { resource($0, in: app) }, holdings)
                XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
            }
            _ = openLargeFleet(prefix, in: app)
            app.buttons["\(prefix).close"].tap()
            XCTAssertTrue(app.buttons["Build"].isHittable, "Closing the chooser must restore the game")
        }
    }

    private func openLargeFleet(_ prefix: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons["naval.overview"].tap()
        if prefix == "naval.nearby" {
            app.buttons["board.ship.1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            app.buttons["naval.fleet.open"].tap()
        }
        let chooser = app.otherElements[prefix]
        XCTAssertTrue(chooser.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["\(prefix).close"].isHittable, "Large text must keep the chooser dismissible")
        XCTAssertFalse(app.buttons["Build"].isHittable, "The accessible chooser must own its native presentation")
        return chooser
    }

    private func selectWholeFleetRow(_ id: Int, prefix: String, chooser: XCUIElement, in app: XCUIApplication) {
        let scroll = chooser.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "Scroll only the identified chooser, never the board or another overlay")
        XCTAssertTrue(scroll.isHittable, "The fleet list has no visible scroll area")
        let row = app.buttons["\(prefix).ship.\(id)"]
        XCTAssertTrue(row.exists)
        revealWholeFleetRow(row, in: scroll, chooser: chooser, app: app)
        XCTAssertTrue(row.isHittable)
        XCTAssertEqual(row.identifier, "\(prefix).ship.\(id)", "Each large-text row must retain its exact identity")
        if id == 2 { retainScreenshot("Voyages — maximum-text \(prefix) with a complete vessel", app: app) }
        row.tap()
        XCTAssertTrue(app.staticTexts["Sail your ship"].waitForExistence(timeout: 3),
                      "Choosing a crowded-map row must draft that exact vessel")
    }

    /// A hittable centre can sit inside a cropped card. Require the entire
    /// painted row inside the visible list, then drag only that list by the
    /// distance needed to centre it; full swipes can overshoot a tall row.
    private func revealWholeFleetRow(_ row: XCUIElement, in scroll: XCUIElement, chooser: XCUIElement, app: XCUIApplication) {
        for _ in 0..<12 {
            let visible = scroll.frame.intersection(chooser.frame).intersection(app.frame)
            guard !visible.isNull, !visible.isEmpty else { XCTFail("The chooser list has no visible bounds"); return }
            let tolerated = visible.insetBy(dx: -Self.frameRoundingTolerance, dy: -Self.frameRoundingTolerance)
            if tolerated.contains(row.frame) {
                XCTAssertTrue(row.isHittable, "A fully visible fleet row must accept interaction")
                return
            }
            XCTAssertLessThanOrEqual(row.frame.height, visible.height + Self.frameRoundingTolerance,
                                     "A complete fleet card cannot fit the actual visible list")
            let travel = max(-visible.height * 0.45, min(visible.height * 0.45, row.frame.midY - visible.midY))
            let start = CGVector(dx: (visible.midX - scroll.frame.minX) / scroll.frame.width,
                                 dy: (visible.midY + travel / 2 - scroll.frame.minY) / scroll.frame.height)
            let finish = CGVector(dx: start.dx,
                                  dy: (visible.midY - travel / 2 - scroll.frame.minY) / scroll.frame.height)
            scroll.coordinate(withNormalizedOffset: start).press(forDuration: 0.05,
                thenDragTo: scroll.coordinate(withNormalizedOffset: finish))
        }
        let visible = scroll.frame.intersection(chooser.frame).intersection(app.frame)
            .insetBy(dx: -Self.frameRoundingTolerance, dy: -Self.frameRoundingTolerance)
        XCTAssertTrue(visible.contains(row.frame), "The fleet card remains visually cropped: \(row.identifier)")
    }

    func testWorldLaunchTouchesStageTheExactSeaAndCancelWithoutPurchasing() {
        let app = launch("-qaNavalVoyagePosition")
        app.buttons["naval.overview"].tap()
        let lumber = resource("lumber", in: app)
        app.buttons["Build"].tap()
        app.buttons["build.ship"].tap()
        _ = chooseEachWorldSeaCenter(in: app, shipCount: 0)
        XCTAssertEqual(resource("lumber", in: app), lumber)
        XCTAssertFalse(app.buttons["board.ship.0"].exists)
        retainScreenshot("Voyages — exact World launch preview", app: app)
        app.buttons["board-decision.cancel"].tap()
        XCTAssertEqual(resource("lumber", in: app), lumber)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
        XCTAssertFalse(app.buttons["board.ship.0"].exists)
    }

    /// Native centre touches, rather than semantic element activation, expose
    /// draw-order interception when several 44pt destination circles overlap.
    private func chooseEachWorldSeaCenter(in app: XCUIApplication, shipCount: Int) -> [Int] {
        let targets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        XCTAssertTrue(targets.firstMatch.waitForExistence(timeout: 3))
        let identifiers = targets.allElementsBoundByIndex.map(\.identifier).sorted()
        XCTAssertGreaterThanOrEqual(identifiers.count, 3)
        let chart = charted(in: app)
        let camera = app.otherElements["naval.camera.reference"].value as? String
        let positions = (0..<shipCount).map { shipPosition($0, in: app) }
        for identifier in identifiers {
            let target = app.buttons[identifier]
            XCTAssertTrue(target.isHittable)
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue((target.value as? String ?? "").hasPrefix("Selected destination"),
                          "Another circle intercepted \(identifier)")
            XCTAssertEqual(charted(in: app), chart)
            XCTAssertEqual((0..<shipCount).map { shipPosition($0, in: app) }, positions)
            XCTAssertEqual(app.otherElements["naval.camera.reference"].value as? String, camera)
        }
        let coordinate = identifiers.last!.split(separator: ".").last!.split(separator: "_").map { Int($0)! }
        XCTAssertEqual(coordinate.count, 2)
        return coordinate
    }

    private func shipPosition(_ id: Int, in app: XCUIApplication) -> String {
        let marker = app.otherElements["naval.ship.position.\(id)"]
        XCTAssertTrue(marker.exists, "A committed public ship position is missing")
        return marker.value as? String ?? ""
    }

    func testGlobalCaptureRequiresConfirmationAndCanBeSkippedAfterResume() {
        let app = launch("-qaNavalCapturePosition")
        let ship = app.buttons["board.ship.0"]
        let originalLabel = ship.label
        let captureRow = app.buttons["naval.choose-ship.0"]
        XCTAssertTrue(captureRow.waitForExistence(timeout: 5))
        captureRow.tap()
        XCTAssertEqual(ship.label, originalLabel)
        XCTAssertTrue(app.otherElements["board.ship-capture-preview"].exists)
        retainScreenshot("Voyages — capture proposal", app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.buttons["naval.capture.skip"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
        app.buttons["naval.choose-ship.0"].tap()
        app.buttons["board-decision.confirm"].tap()
        XCTAssertTrue(app.alerts["naval.capture.receipt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["End Turn"].exists)
        retainScreenshot("Voyages — acknowledged ownership notice", app: app)
        app.buttons["naval.capture.continue"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.buttons["board.ship.0"].label, originalLabel)
        retainScreenshot("Voyages — captured vessel", app: app)
    }

    func testCaptureSkipDoesNotTransferOwnership() {
        let app = launch("-qaNavalCapturePosition")
        let originalLabel = app.buttons["board.ship.0"].label
        app.buttons["naval.capture.skip"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["board.ship.0"].label, originalLabel)
    }

    func testWildHarvestIsOneBankCardAndSurvivesColdResume() {
        let app = launch("-qaNavalResourcePosition")
        XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["naval.resource.source"].label, "Settlement harvest")
        XCTAssertTrue(app.staticTexts["naval.resource.choice"].label.contains("Choose 1 resource"))
        let oreBefore = resource("ore", in: app)
        app.buttons["naval.resource.ore"].tap()
        XCTAssertEqual(resource("ore", in: app), oreBefore)
        retainScreenshot("Voyages — island harvest", app: app)
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["naval.resource.confirm"].isEnabled)
        app.buttons["naval.resource.ore"].tap()
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), oreBefore + 1)
        app.buttons["naval.overview"].tap()
        retainScreenshot("Voyages — founded colony", app: app)
    }

    func testOverviewHomeZoomAndPanStayWithinTheFixedViewport() {
        let app = launch("-qaNavalVoyagePosition")
        let board = app.otherElements["board.surface"]
        let bounds = board.frame
        app.buttons["naval.overview"].tap()
        XCTAssertEqual(board.frame, bounds)
        retainScreenshot("Voyages — unexplored world", app: app)
        app.buttons["naval.home"].tap()
        XCTAssertEqual(board.frame, bounds)
        board.pinch(withScale: 1.8, velocity: 2)
        board.swipeLeft()
        XCTAssertEqual(board.frame, bounds)
        retainScreenshot("Voyages — zoomed and panned", app: app)
        app.buttons["naval.home"].tap()
        board.pinch(withScale: 4, velocity: 2)
        let camera = app.otherElements["naval.camera.reference"]
        let maximum = NSPredicate { _, _ in (camera.value as? String)?.contains("zoom=9.000000") == true }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: maximum, object: nil)], timeout: 3), .completed)
        XCTAssertEqual(board.frame, bounds)
        retainScreenshot("Voyages — clipped home at maximum zoom", app: app)
        for index in 1...4 {
            board.swipeRight()
            XCTAssertEqual(board.frame, bounds)
            retainScreenshot("Voyages — maximum zoom coastal pan \(index)", app: app)
        }
        app.buttons["naval.home"].tap()
        XCTAssertTrue(app.buttons["Build"].isHittable)
        XCTAssertTrue(app.buttons["End Turn"].isHittable)
    }

    func testCityHarvestRequiresBothSelectionsBeforeOneCollection() {
        let app = launch("-qaNavalCityResourcePosition")
        let ore = app.buttons["naval.resource.ore"]
        let confirm = app.buttons["naval.resource.confirm"]
        XCTAssertTrue(ore.waitForExistence(timeout: 5))
        let before = resource("ore", in: app)
        XCTAssertFalse(confirm.isEnabled)
        ore.tap()
        XCTAssertFalse(confirm.isEnabled, "Selecting one of two cards must not enable collection")
        XCTAssertEqual(resource("ore", in: app), before, "A selection cannot collect a card")
        ore.tap()
        XCTAssertTrue(confirm.isEnabled, "Repeated selection must allow two of the same resource")
        XCTAssertEqual(resource("ore", in: app), before)
        confirm.tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(resource("ore", in: app), before + 2)
    }

    func testLargeTextHarvestKeepsEveryChoiceAndConfirmationReachable() {
        let app = launch("-qaNavalResourcePosition", extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let collect = app.buttons["naval.resource.confirm"]
        XCTAssertTrue(collect.isHittable)
        XCTAssertGreaterThanOrEqual(collect.frame.height, 44)
        var selected: String?
        for resource in ["brick", "lumber", "ore", "grain", "wool"] {
            if let selected {
                let remove = app.buttons["naval.resource.remove.\(selected)"]
                for _ in 0..<10 where !remove.isHittable { app.scrollViews["naval.resource.scroll"].swipeDown() }
                XCTAssertTrue(remove.isHittable)
                XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
                remove.tap()
            }
            let choice = app.buttons["naval.resource.\(resource)"]
            for _ in 0..<10 where !choice.isHittable {
                app.scrollViews["naval.resource.scroll"].swipeUp()
            }
            XCTAssertTrue(choice.isHittable, "The harvest choice cannot be reached: \(resource)")
            XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
            choice.tap()
            selected = resource
            XCTAssertTrue(collect.isHittable, "Confirmation must remain pinned while the choices scroll")
            XCTAssertEqual(collect.value as? String, "1 of 1 selected")
        }
        retainScreenshot("Voyages — accessible island harvest", app: app)
        collect.tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
    }

    func testHarvestPassesNativeAccessibilityAudit() throws {
        let app = launch("-qaNavalResourcePosition")
        XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Build"].isHittable, "A mandatory overlay must block underlying commands")
        XCTAssertFalse(app.staticTexts["Greece"].isHittable, "Covered opponent information must not accept interaction")
        XCTAssertFalse(app.buttons["naval.overview"].isHittable, "Covered navigation must not accept interaction")
        try app.performAccessibilityAudit(for: [.contrast, .hitRegion, .sufficientElementDescription, .textClipped]) { issue in
            print("Naval accessibility audit: \(issue.detailedDescription), \(issue.element?.debugDescription ?? "no element")")
            if issue.auditType == .contrast, let element = issue.element,
               ["naval.resource.source", "naval.resource.progress.collected", "naval.resource.progress.remaining"]
                .contains(element.identifier) {
                let screenshot = element.screenshot()
                let attachment = XCTAttachment(screenshot: screenshot)
                attachment.name = "\(element.identifier) — independently measured rendered contrast"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                let ratio = WhiteTextContrast.ratio(in: screenshot.image) ?? 0
                print("Live \(element.identifier) white-text contrast: \(ratio):1")
                XCTAssertGreaterThanOrEqual(ratio, WhiteTextContrast.requiredRatio)
                return ratio >= WhiteTextContrast.requiredRatio
            }
            return false
        }
        retainScreenshot("Voyages — audited island harvest", app: app)
    }

    func testResultsRemainReachableAtMaximumTextSize() {
        let app = launch("-qaShowEndGame", extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ], waitsForBoard: false)
        let menu = app.buttons["game-over.main-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["YOU WIN!"].exists)
        retainScreenshot("Victory — painted emblem before scrolling at maximum text", app: app)
        reveal(menu, in: app)
        XCTAssertGreaterThanOrEqual(menu.frame.height, 44)
        retainScreenshot("Voyages — accessible results", app: app)
        menu.tap()
        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 5))
    }

    func testReducedMotionNavigationUsesTheSystemPreference() {
        continueAfterFailure = false
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let preference = settings.switches["Reduce Motion"]
        if !preference.waitForExistence(timeout: 1) {
            openSettingsRow("Accessibility", in: settings)
            openSettingsRow("Motion", in: settings)
        }
        XCTAssertTrue(preference.waitForExistence(timeout: 5), settings.debugDescription)
        let original = preference.value as? String
        defer {
            settings.activate()
            if original != "1", preference.value as? String == "1" {
                preference.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            settings.terminate()
        }
        if original != "1" {
            preference.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: preference)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(preference.value as? String, "1")
        let app = launch("-qaNavalVoyagePosition")
        XCTAssertTrue((app.otherElements["naval.camera.reference"].value as? String ?? "").contains("reduceMotion=1"),
                      "The actual system preference must reach the SwiftUI board environment")
        let board = app.otherElements["board.surface"]
        let frame = board.frame
        app.buttons["naval.overview"].tap()
        app.buttons["naval.home"].tap()
        XCTAssertEqual(board.frame, frame)
        XCTAssertTrue(app.buttons["Build"].isHittable)
        retainScreenshot("Voyages — system Reduce Motion", app: app)
        app.terminate()
    }

    func testARealNavalExpertMatchReachesGameOverAndArchives() {
        let app = launch("-qaNavalExpert", extra: ["-qaPlayToEnd", "-qaNavalSeed=7501"], waitsForBoard: false)
        // ~650 moves at onscreen Debug speed is ~200s, then the victory cutscene.
        let skip = app.buttons["game-over.cutscene.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 360), "A production naval session must reach an actual winner")
        skip.tap()
        XCTAssertTrue(app.buttons["game-over.new-game"].waitForExistence(timeout: 10))
        retainScreenshot("Voyages — complete Expert match", app: app)
        XCTAssertTrue(app.buttons["game-over.replay"].waitForExistence(timeout: 10))
        app.buttons["game-over.replay"].tap()
        XCTAssertTrue(app.buttons["replay.end"].waitForExistence(timeout: 30))
        app.buttons["replay.start"].tap()
        let openingChart = charted(in: app)
        app.buttons["naval.overview"].tap()
        retainScreenshot("Voyages — historical opening fog", app: app)
        app.buttons["replay.end"].tap()
        XCTAssertGreaterThan(charted(in: app), openingChart)
        retainScreenshot("Voyages — final world replay", app: app)
        app.buttons["replay.score.0"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["replay.breakdown.colonies"].waitForExistence(timeout: 3))
        app.buttons["replay.breakdown.close"].tap()
        app.buttons["replay.close"].tap()
        app.buttons["game-over.main-menu"].tap()
        XCTAssertFalse(app.buttons["main-menu.resume"].exists, "A completed match must clear its resumable save")
    }

    private func launch(_ fixture: String, extra: [String] = [], waitsForBoard: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode", fixture] + extra
        app.launch()
        if ["-qaNavalResourcePosition", "-qaNavalCityResourcePosition"].contains(fixture) {
            XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 15))
        } else if waitsForBoard {
            XCTAssertTrue(app.otherElements["board.surface"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 5))
        }
        return app
    }

    private func resource(_ resource: String, in app: XCUIApplication,
                          file: StaticString = #filePath, line: UInt = #line) -> Int {
        NavalResourceOracle.ownedCount(resource, in: app, file: file, line: line)
    }

    private func charted(in app: XCUIApplication) -> Int {
        let value = app.buttons["naval.overview"].value as? String ?? ""
        let counts = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(counts.count, 2, "Shared discovery summary is missing: \(value)")
        return counts.first ?? -1
    }

    private func tapOutwardSea(in app: XCUIApplication) {
        let targets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        XCTAssertTrue(targets.firstMatch.waitForExistence(timeout: 5), "No legal sea target is exposed")
        let target = targets.allElementsBoundByIndex.filter(\.isHittable).max {
            radialScore($0.identifier) < radialScore($1.identifier)
        }
        XCTAssertNotNil(target, "No sea target is tappable in the current camera")
        target?.tap()
    }

    private func radialScore(_ identifier: String) -> Int {
        let numbers = identifier.split(separator: ".").last?.split(separator: "_").compactMap { Int($0) } ?? []
        guard numbers.count == 2 else { return 0 }
        return max(abs(numbers[0]), abs(numbers[1]), abs(numbers[0] + numbers[1]))
    }

    private func retainScreenshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { return }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "The control cannot be reached: \(element.identifier)")
    }

    private func openSettingsRow(_ label: String, in settings: XCUIApplication) {
        let row = settings.staticTexts[label].firstMatch
        for _ in 0..<10 where !row.isHittable { settings.swipeUp() }
        XCTAssertTrue(row.isHittable, settings.debugDescription)
        row.tap()
    }
}
