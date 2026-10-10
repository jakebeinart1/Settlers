import XCTest

/// Inspect the new terrain after real collection, focusing a publicly charted
/// field at local, World and maximum zoom instead of photographing it offscreen.
@MainActor
final class NavalHarvestArtworkFlowTests: XCTestCase {
    func testPaintedHarvestFieldKeepsItsTokenAtLocalWorldAndMaximumZoom() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode", "-qaNavalCityResourcePosition"]
        app.launch()
        for _ in 0..<2 {
            XCTAssertTrue(app.buttons["naval.resource.ore"].waitForExistence(timeout: 10))
            app.buttons["naval.resource.ore"].tap()
        }
        app.buttons["naval.resource.confirm"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: 5))
        app.buttons["naval.fleet.open"].tap()
        app.buttons["naval.fleet.ship.0"].tap()
        let board = app.otherElements["board.surface"]
        let viewport = board.frame
        let field = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH %@", "naval.harvest.position.")).firstMatch
        XCTAssertTrue(field.exists, "The screenshot must contain a discovered harvest field")
        panIntoView(field, app: app)
        retain("Painted harvest field at local colony scale", app: app)
        app.buttons["naval.overview"].tap()
        XCTAssertEqual(board.frame, viewport)
        retain("Painted harvest fields in the charted world", app: app)
        app.buttons["naval.overview"].tap()
        board.pinch(withScale: 4, velocity: 2)
        panIntoView(field, app: app)
        XCTAssertEqual(board.frame, viewport)
        XCTAssertTrue((app.otherElements["naval.camera.reference"].value as? String ?? "").contains("zoom=9.000000"))
        retain("Painted harvest field and numbered token at maximum zoom", app: app)
    }

    private func panIntoView(_ marker: XCUIElement, app: XCUIApplication) {
        let board = app.otherElements["board.surface"]
        for _ in 0..<10 {
            let fields = geometry(marker.value as? String ?? "")
            guard let x = fields["x"], let y = fields["y"], let size = fields["hexSize"] else {
                XCTFail("Missing public field geometry"); return
            }
            let viewport = CGRect(origin: .zero, size: board.frame.size)
            let visibleField = CGRect(x: x - size, y: y - size, width: size * 2, height: size * 2)
            if viewport.contains(visibleField) { return }
            let dx = board.frame.width / 2 - x, dy = board.frame.height / 2 - y
            if abs(dx) < 8 && abs(dy) < 8 { return }
            let start = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let offset = CGVector(dx: min(max(dx, -board.frame.width * 0.35), board.frame.width * 0.35),
                                  dy: min(max(dy, -board.frame.height * 0.35), board.frame.height * 0.35))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(offset))
        }
        retain("Harvest field framing failure", app: app)
        XCTFail("Real panning did not bring the whole field into view: \(marker.value ?? "missing")")
    }

    private func geometry(_ text: String) -> [String: CGFloat] {
        Dictionary(uniqueKeysWithValues: text.split(separator: ";").compactMap { pair in
            let fields = pair.split(separator: "=", maxSplits: 1)
            guard fields.count == 2, let number = Double(fields[1]) else { return nil }
            return (String(fields[0]), CGFloat(number))
        })
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
