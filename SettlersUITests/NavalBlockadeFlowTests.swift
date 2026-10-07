import XCTest

/// Real controls exercise the public blockade mask, physical sea touches,
/// capture confirmation and cold-resumed travel. Preparation is an explicit
/// conserved generated-world baseline, not an ordinary match economy claim.
@MainActor
final class NavalBlockadeFlowTests: XCTestCase {
    private let sailingDetail = "2 hexes left. Opposing ships block passage."

    func testOpposingShipBlocksEntryAndThroughVoyageAtLocalAndWorldZoomWithoutSnapping() {
        let app = launch("-qaNavalBlockadePosition")
        let original = positions(in: app)
        let resources = holdings(in: app)
        let charted = chart(in: app)
        let blocker = coordinates(position(1, in: app))
        let destination = beyondBlocker(in: app)
        for world in [false, true] {
            selectActorShip(in: app)
            if world { app.buttons["naval.overview"].tap() }
            assertBlockedTargets(blocker: blocker, beyond: destination, in: app)
            tapBlockedCenter(blocker, in: app)
            XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
            XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
            XCTAssertEqual(positions(in: app), original)
            XCTAssertEqual(holdings(in: app), resources)
            XCTAssertEqual(chart(in: app), charted)
            retain(world ? "Blockades — World touch cannot snap to another destination"
                   : "Blockades — opposing vessel closes the straight passage", app: app)
            let legal = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
            guard let target = legal.allElementsBoundByIndex.first(where: \.isHittable) else {
                XCTFail("Blockade should leave an alternative sea destination"); return
            }
            target.tap()
            XCTAssertTrue(app.buttons["board-decision.confirm"].isEnabled)
            let selected = target.value as? String
            tapBlockedCenter(blocker, in: app)
            XCTAssertEqual(target.value as? String, selected, "An invalid touch must keep the existing proposal")
            XCTAssertEqual(positions(in: app), original)
            XCTAssertEqual(holdings(in: app), resources)
            XCTAssertEqual(chart(in: app), charted)
            app.buttons["board-decision.cancel"].tap()
        }
    }

    func testCaptureConfirmationAndColdResumeOpenTheActualTwoHexVoyage() {
        let app = launch("-qaNavalBlockadeCapturePosition")
        let original = positions(in: app)
        let resources = holdings(in: app)
        let blocker = coordinates(position(1, in: app))
        let destination = beyondBlocker(in: app)
        XCTAssertEqual(owner(1, in: app), "1")
        app.buttons["naval.choose-ship.1"].tap()
        XCTAssertTrue(app.otherElements["board.ship-capture-preview"].exists)
        XCTAssertEqual(owner(1, in: app), "1")
        XCTAssertEqual(positions(in: app), original)
        retain("Blockades — capture remains a proposal", app: app)
        coldResume(app)
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
        XCTAssertEqual(owner(1, in: app), "1")
        app.buttons["naval.choose-ship.1"].tap()
        app.buttons["board-decision.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        XCTAssertEqual(owner(1, in: app), "0")
        XCTAssertEqual(coordinates(position(1, in: app)), blocker)
        XCTAssertTrue(position(1, in: app).contains("steps=2"))
        XCTAssertEqual(holdings(in: app), resources)
        selectActorShip(in: app)
        XCTAssertFalse(app.otherElements[blockadeID(blocker)].exists)
        let target = app.buttons[tileID(destination)]
        XCTAssertTrue(target.exists && target.isHittable)
        XCTAssertTrue((target.value as? String ?? "").contains("2 hexes of travel"))
        target.tap()
        XCTAssertTrue(app.staticTexts["Sail 2 hexes. 0 left afterward."].exists)
        XCTAssertEqual(position(0, in: app), original[0])
        retain("Blockades — captured vessel opens a two-hex route", app: app)
        app.buttons["board-decision.confirm"].tap()
        XCTAssertEqual(position(0, in: app), "q=\(destination[0]);r=\(destination[1]);steps=0")
        XCTAssertEqual(coordinates(position(1, in: app)), blocker)
        XCTAssertEqual(holdings(in: app), resources)
        let committed = positions(in: app)
        let charted = chart(in: app)
        coldResume(app)
        XCTAssertEqual(positions(in: app), committed)
        XCTAssertEqual(owner(1, in: app), "0")
        XCTAssertEqual(chart(in: app), charted)
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
        retain("Blockades — ownership and completed voyage survive cold resume", app: app)
    }

    func testOccupiedLaunchCoastExplainsUnavailableShipWithoutChargingResources() {
        let app = launch("-qaNavalBlockadeLaunchPosition")
        let resources = holdings(in: app)
        let charted = chart(in: app)
        app.buttons["Build"].tap()
        let ship = app.buttons["build.ship"]
        XCTAssertTrue(ship.waitForExistence(timeout: 5))
        XCTAssertFalse(ship.isEnabled)
        XCTAssertTrue((ship.value as? String ?? "").contains("Your launch coast is blocked by opposing ships"))
        XCTAssertFalse((ship.value as? String ?? "").contains("Requires your settlement"))
        retain("Blockades — funded ship purchase explains the occupied launch coast", app: app)
        ship.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.otherElements["board.ship-preview"].exists)
        XCTAssertFalse(app.buttons["board-decision.confirm"].exists)
        XCTAssertEqual(holdings(in: app), resources)
        XCTAssertEqual(chart(in: app), charted)
    }

    func testBlockadeExplanationAndWorldTouchRemainUsableAtLargestText() {
        let app = launch("-qaNavalBlockadePosition", largestText: true)
        let original = positions(in: app)
        let resources = holdings(in: app)
        selectActorShip(in: app)
        let detail = app.staticTexts[sailingDetail]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        let dock = app.otherElements["board-decision.dock"]
        XCTAssertTrue(dock.frame.insetBy(dx: -1, dy: -1).contains(detail.frame))
        XCTAssertTrue(app.buttons["board-decision.cancel"].isHittable)
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
        app.buttons["naval.overview"].tap()
        let blocker = coordinates(position(1, in: app))
        tapBlockedCenter(blocker, in: app)
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
        XCTAssertEqual(positions(in: app), original)
        XCTAssertEqual(holdings(in: app), resources)
        retain("Blockades — maximum text retains explanation and safe World selection", app: app)
        app.buttons["board-decision.cancel"].tap()
        XCTAssertTrue(app.buttons["Build"].isHittable)
    }

    private func launch(_ position: String, largestText: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode", position]
        if largestText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["naval.fleet.open"].waitForExistence(timeout: 15))
        return app
    }

    private func selectActorShip(in app: XCUIApplication) {
        app.buttons["naval.fleet.open"].tap()
        let ship = app.buttons["naval.fleet.ship.0"]
        XCTAssertTrue(ship.waitForExistence(timeout: 5))
        XCTAssertTrue(ship.isHittable)
        ship.tap()
        XCTAssertTrue(app.buttons["board-decision.cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[sailingDetail].exists)
    }

    private func tapBlockedCenter(_ coordinate: [Int], in app: XCUIApplication) {
        let marker = app.otherElements[blockadeID(coordinate)]
        XCTAssertTrue(marker.exists)
        XCTAssertTrue(app.otherElements["board.surface"].frame.contains(marker.frame))
        let camera = app.otherElements["naval.camera.reference"].value as? String
        marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(app.otherElements["naval.camera.reference"].value as? String, camera)
    }

    private func assertBlockedTargets(blocker: [Int], beyond: [Int], in app: XCUIApplication) {
        XCTAssertFalse(app.buttons[tileID(blocker)].exists)
        XCTAssertFalse(app.buttons[tileID(beyond)].exists)
        XCTAssertTrue(app.otherElements[blockadeID(blocker)].exists)
        XCTAssertTrue(position(1, in: app).contains("steps=0"), "An exhausted defender must still block passage")
    }

    private func coldResume(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: 5))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["naval.fleet.open"].waitForExistence(timeout: 5))
    }

    private func positions(in app: XCUIApplication) -> [String] { (0..<2).map { position($0, in: app) } }

    private func position(_ id: Int, in app: XCUIApplication) -> String {
        let marker = app.otherElements["naval.ship.position.\(id)"]
        XCTAssertTrue(marker.exists)
        return marker.value as? String ?? ""
    }

    private func owner(_ id: Int, in app: XCUIApplication) -> String {
        app.otherElements["naval.ship.owner.\(id)"].value as? String ?? ""
    }

    private func beyondBlocker(in app: XCUIApplication) -> [Int] {
        let origin = coordinates(position(0, in: app)), blocker = coordinates(position(1, in: app))
        return [2 * blocker[0] - origin[0], 2 * blocker[1] - origin[1]]
    }

    private func coordinates(_ value: String) -> [Int] {
        let fields = value.split(separator: ";").map { $0.split(separator: "=").map(String.init) }
        let parts = Dictionary(uniqueKeysWithValues: fields.map { ($0[0], $0[1]) })
        guard let q = parts["q"].flatMap(Int.init), let r = parts["r"].flatMap(Int.init) else {
            XCTFail("Missing committed public ship coordinates: \(value)"); return [0, 0]
        }
        return [q, r]
    }

    private func tileID(_ coordinate: [Int]) -> String { "board.tile.\(coordinate[0])_\(coordinate[1])" }
    private func blockadeID(_ coordinate: [Int]) -> String { "naval.blockade.\(coordinate[0])_\(coordinate[1])" }
    private func chart(in app: XCUIApplication) -> String { app.buttons["naval.overview"].value as? String ?? "" }

    private func holdings(in app: XCUIApplication) -> [String] {
        ["brick", "lumber", "ore", "grain", "wool"].map {
            app.otherElements["human-resource.\($0)"].value as? String ?? ""
        }
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
