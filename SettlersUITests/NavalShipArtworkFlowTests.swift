import XCTest

/// Actual purchases put each civilization's image on the real map. World,
/// local focus, Fleet and magnification retain identity and camera bounds.
@MainActor
final class NavalShipArtworkFlowTests: XCTestCase {
    private static let civilizations = [
        ("medieval", "Britannia"), ("greece", "Greece"), ("egypt", "Egypt"), ("aztec", "Aztec"),
        ("columbia", "Columbia"), ("rome", "Rome"), ("japan", "Japan"), ("norse", "Norse")
    ]

    func testAllEightPaintedFleetsThroughRealPurchaseWorldHomeAndFleet() {
        continueAfterFailure = false
        for (raw, name) in Self.civilizations {
            let app = launch(raw)
            purchaseShip(in: app)
            let ship = app.buttons["board.ship.0"]
            XCTAssertTrue(ship.label.contains("\(name) vessel"), "Requested \(name), rendered \(ship.label)")
            app.buttons["naval.fleet.open"].tap()
            let fleet = app.buttons["naval.fleet.ship.0"]
            XCTAssertTrue(fleet.waitForExistence(timeout: 5))
            retain("Painted \(name) fleet chooser", app: app)
            fleet.tap()
            let viewport = app.otherElements["board.surface"].frame
            retain("Painted \(name) vessel at local scale", app: app)
            app.buttons["naval.overview"].tap()
            XCTAssertEqual(app.otherElements["board.surface"].frame, viewport)
            retain("Painted \(name) vessel at World scale", app: app)
            app.buttons["naval.overview"].tap()
            XCTAssertEqual(app.otherElements["board.surface"].frame, viewport)
            XCTAssertTrue(ship.label.contains("\(name) vessel"))
            app.terminate()
        }
    }

    func testPaintedVesselAtMaximumZoomKeepsItsCoastalHarborAndViewport() {
        let app = launch("medieval")
        purchaseShip(in: app)
        app.buttons["naval.fleet.open"].tap()
        app.buttons["naval.fleet.ship.0"].tap()
        let board = app.otherElements["board.surface"]
        let viewport = board.frame
        board.pinch(withScale: 4, velocity: 2)
        XCTAssertTrue((app.otherElements["naval.camera.reference"].value as? String ?? "").contains("zoom=9.000000"))
        panShipIntoView(in: app)
        XCTAssertEqual(board.frame, viewport)
        XCTAssertTrue(board.frame.contains(app.buttons["board.ship.0"].frame), "The maximum-zoom screenshot must actually contain the ship")
        XCTAssertTrue(app.buttons["board.ship.0"].label.contains("Britannia vessel"))
        retain("Painted Britannia vessel and harbor at maximum zoom", app: app)
        XCTAssertTrue(app.buttons["naval.home"].isHittable)
        app.buttons["naval.home"].tap()
        XCTAssertEqual(board.frame, viewport)
        app.terminate()
    }

    private func launch(_ civilization: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalVoyagePosition", "-qaNavalCivilization=\(civilization)"]
        app.launch()
        XCTAssertTrue(app.buttons["Build"].waitForExistence(timeout: 15))
        return app
    }

    func testMixedControllerStackShowsItsCountAndSeparateOwnerChoices() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode", "-qaNavalMixedShipsPosition"]
        app.launch()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: 15))
        app.buttons["naval.overview"].tap()
        let stack = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.ships.")).firstMatch
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        XCTAssertTrue(stack.label.contains("2 ships"))
        retain("Painted mixed-controller stack at World scale", app: app)
        stack.tap()
        let first = app.buttons["naval.nearby.ship.0"]
        let second = app.buttons["naval.nearby.ship.1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5) && second.exists)
        XCTAssertNotEqual(first.label, second.label)
        retain("Painted mixed-controller stack has separate owner choices", app: app)
        first.tap()
        retain("Painted mixed-controller stack at local scale", app: app)
        app.terminate()
    }

    private func purchaseShip(in app: XCUIApplication) {
        app.buttons["Build"].tap()
        XCTAssertTrue(app.buttons["build.ship"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["build.ship"].isEnabled)
        app.buttons["build.ship"].tap()
        let sea = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        XCTAssertTrue(sea.firstMatch.waitForExistence(timeout: 5))
        let target = sea.allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(target)
        target?.tap()
        app.buttons["board-decision.confirm"].tap()
        XCTAssertTrue(app.buttons["board.ship.0"].waitForExistence(timeout: 5))
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// A zoom may move an off-center inspection subject outside the crop.
    /// Use genuine board drags to bring its public position into the viewport;
    /// an offscreen accessibility label is not evidence of painted artwork.
    private func panShipIntoView(in app: XCUIApplication) {
        let board = app.otherElements["board.surface"]
        for _ in 0..<10 {
            let camera = fields(app.otherElements["naval.camera.reference"].value as? String ?? "")
            let ship = fields(app.otherElements["naval.ship.position.0"].value as? String ?? "")
            guard let x = camera["x"], let y = camera["y"], let size = camera["hexSize"],
                  let q = ship["q"], let r = ship["r"] else { XCTFail("Missing public map geometry"); return }
            let target = CGPoint(x: x + size * sqrt(3) * (q + r / 2), y: y + size * 1.5 * r)
            let dx = board.frame.width / 2 - target.x
            let dy = board.frame.height / 2 - target.y
            if abs(dx) < 8 && abs(dy) < 8 { return }
            let stepX = min(max(dx, -board.frame.width * 0.35), board.frame.width * 0.35)
            let stepY = min(max(dy, -board.frame.height * 0.35), board.frame.height * 0.35)
            let start = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: stepX, dy: stepY)))
        }
        XCTFail("Real board panning did not bring the ship into view")
    }

    private func fields(_ value: String) -> [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { part in
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, let number = Double(pair[1]) else { return nil }
            return (String(pair[0]), CGFloat(number))
        })
    }
}
