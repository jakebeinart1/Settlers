import XCTest

/// Recreate the reported coastal two-road approach to a rival inland town.
/// Both exits use the ordinary Build, proposal and durable Confirm paths;
/// the Debug marker reads committed state without supplying any move.
@MainActor
final class NavalRoadJunctionFlowTests: XCTestCase {
    private static let inspectionFlag = "-qaNavalRoadJunctionInspection"
    private static let stateMarker = "qa.naval-road-junction.state"
    private static let upper = "board.edge.board.vertex.-6_6.-6_7.-5_6.board.vertex.-6_6.-5_5.-5_6"
    private static let lower = "board.edge.board.vertex.-6_6.-6_7.-5_6.board.vertex.-6_7.-5_6.-5_7"
    private static let timeout: TimeInterval = 10
    private static let poseTolerance: CGFloat = 0.01
    private static let maximumPanFraction: CGFloat = 0.35
    private static let inspectionRadius: CGFloat = 1.8

    func testBothRivalTownExitsCanBePreviewedBuiltAndResumed() throws {
        continueAfterFailure = false
        let app = launch()
        defer { app.terminate() }
        try focusJunction(in: app)
        try assertRoads([2, 0, 0], holdings: [2, 2], in: app)
        try assertWorldReturnsToTheIsland(in: app)
        retain("Naval roads — coastal founder reaches rival inland town", app: app)
        let frames = stableFrames(in: app)
        try assertBothBranchesPreviewWithoutSpending(in: app, frames: frames)
        beginRoad(in: app)
        try stage(Self.upper, in: app)
        app.buttons["board-decision.confirm"].tap()
        try assertRoads([3, 1, 0], holdings: [1, 1], in: app)
        assertFrames(frames, in: app)
        retain("Naval roads — first exit past the rival town is committed", app: app)
        coldResume(app)
        try assertRoads([3, 1, 0], holdings: [1, 1], in: app)
        try focusJunction(in: app)
        try buildRemainingBranch(in: app, frames: stableFrames(in: app))
        coldResume(app)
        try assertRoads([4, 1, 1], holdings: [0, 0], in: app)
        try focusJunction(in: app)
        try assertWorldReturnsToTheIsland(in: app)
        retain("Naval roads — both rival-town exits survive a cold resume", app: app)
    }

    private func assertBothBranchesPreviewWithoutSpending(in app: XCUIApplication, frames: [CGRect]) throws {
        beginRoad(in: app)
        for identifier in [Self.upper, Self.lower] {
            let exit = app.buttons[identifier]
            XCTAssertTrue(exit.waitForExistence(timeout: Self.timeout))
            XCTAssertTrue(exit.isEnabled && exit.isHittable, "The rival inland town must expose both exact land exits")
        }
        try stage(Self.upper, in: app)
        try assertRoads([2, 0, 0], holdings: [2, 2], in: app)
        assertFrames(frames, in: app)
        retain("Naval roads — upper exit is a proposal, not a spent road", app: app)
        app.buttons["board-decision.clear"].tap()
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
        try stage(Self.lower, in: app)
        retain("Naval roads — lower exit is independently selectable", app: app)
        app.buttons["board-decision.cancel"].tap()
        try assertRoads([2, 0, 0], holdings: [2, 2], in: app)
        assertFrames(frames, in: app)
    }

    private func buildRemainingBranch(in app: XCUIApplication, frames: [CGRect]) throws {
        beginRoad(in: app)
        XCTAssertFalse(app.buttons[Self.upper].exists, "A committed road cannot remain an available target")
        let remaining = app.buttons[Self.lower]
        XCTAssertTrue(remaining.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(remaining.isEnabled && remaining.isHittable)
        try stage(Self.lower, in: app)
        try assertRoads([3, 1, 0], holdings: [1, 1], in: app)
        assertFrames(frames, in: app)
        app.buttons["board-decision.confirm"].tap()
        try assertRoads([4, 1, 1], holdings: [0, 0], in: app)
        XCTAssertFalse(app.otherElements["board.road-preview"].exists)
        assertFrames(frames, in: app)
        retain("Naval roads — purple claims both exits without taking the blue town", app: app)
    }

    private func beginRoad(in app: XCUIApplication) {
        let build = app.buttons["Build"]
        XCTAssertTrue(build.waitForExistence(timeout: Self.timeout))
        build.tap()
        let road = app.buttons["build.road"]
        XCTAssertTrue(road.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(road.isEnabled && road.isHittable)
        road.tap()
        XCTAssertTrue(app.buttons["board-decision.confirm"].waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(app.buttons["board-decision.confirm"].isEnabled)
    }

    private func stage(_ identifier: String, in app: XCUIApplication) throws {
        let target = app.buttons[identifier]
        XCTAssertTrue(target.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(target.isHittable)
        target.tap()
        XCTAssertEqual(target.value as? String, "Selected", "A tap must choose the intended exit at the shared junction")
        XCTAssertTrue(app.otherElements["board.road-preview"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["board-decision.confirm"].isEnabled)
    }

    private func assertRoads(_ expected: [Int], holdings: [Int], in app: XCUIApplication) throws {
        let marker = app.otherElements[Self.stateMarker]
        XCTAssertTrue(marker.waitForExistence(timeout: Self.timeout))
        let state = try fields(marker.value as? String)
        let actual = try ["roads", "upperOwned", "lowerOwned"].map { Int(try XCTUnwrap(state[$0])) }
        XCTAssertEqual(actual, expected)
        let hand = try ["brick", "lumber"].map { resource in
            let value = app.otherElements["human-resource.\(resource)"].value as? String
            return try XCTUnwrap(Int(try XCTUnwrap(value)))
        }
        XCTAssertEqual(hand, holdings, "Each confirmed road spends exactly one Brick and one Lumber")
    }

    /// Real native drags bring the fixed overseas junction into the local view.
    /// Geometry comes from the renderer's public-position leaf, not desktop
    /// coordinates or a changed fit. No target is selected while panning.
    private func focusJunction(in app: XCUIApplication) throws {
        let board = app.otherElements["board.surface"]
        XCTAssertTrue(board.waitForExistence(timeout: Self.timeout))
        for _ in 0..<12 {
            let geometry = try fields(app.otherElements[Self.stateMarker].value as? String)
            let x = try XCTUnwrap(geometry["x"]), y = try XCTUnwrap(geometry["y"])
            let radius = try XCTUnwrap(geometry["hexSize"]) * Self.inspectionRadius
            let viewport = CGRect(origin: .zero, size: board.frame.size)
            if viewport.contains(CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)) { return }
            let dx = viewport.midX - x, dy = viewport.midY - y
            let start = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let delta = CGVector(dx: bounded(dx, by: viewport.width), dy: bounded(dy, by: viewport.height))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(delta))
        }
        retain("Naval roads — island framing failure", app: app)
        XCTFail("Native panning did not bring the rival inland junction and its two exits into view")
    }

    private func bounded(_ distance: CGFloat, by extent: CGFloat) -> CGFloat {
        min(max(distance, -extent * Self.maximumPanFraction), extent * Self.maximumPanFraction)
    }

    private func assertWorldReturnsToTheIsland(in app: XCUIApplication) throws {
        let frames = stableFrames(in: app)
        let before = try fields(app.otherElements["naval.camera.reference"].value as? String)
        let roads = try fields(app.otherElements[Self.stateMarker].value as? String)
        app.buttons["naval.overview"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].label.localizedCaseInsensitiveContains("return"))
        assertFrames(frames, in: app)
        retain("Naval roads — world view retains the same committed island roads", app: app)
        app.buttons["naval.overview"].tap()
        let after = try fields(app.otherElements["naval.camera.reference"].value as? String)
        for key in ["zoom", "panX", "panY", "hexSize"] {
            XCTAssertEqual(try XCTUnwrap(after[key]), try XCTUnwrap(before[key]), accuracy: Self.poseTolerance)
        }
        let restored = try fields(app.otherElements[Self.stateMarker].value as? String)
        for key in ["roads", "upperOwned", "lowerOwned"] { XCTAssertEqual(restored[key], roads[key]) }
        assertFrames(frames, in: app)
    }

    private func stableFrames(in app: XCUIApplication) -> [CGRect] {
        let elements = [app.otherElements["board.surface"], app.otherElements["game.command-row"]]
        for element in elements {
            XCTAssertTrue(element.waitForExistence(timeout: Self.timeout), "A missing layout leaf cannot establish a stable viewport")
            XCTAssertGreaterThan(element.frame.width, 0)
            XCTAssertGreaterThan(element.frame.height, 0)
        }
        return elements.map(\.frame)
    }

    private func assertFrames(_ expected: [CGRect], in app: XCUIApplication) {
        XCTAssertEqual(stableFrames(in: app), expected, "The board and command row cannot resize around construction")
    }

    private func fields(_ value: String?) throws -> [String: CGFloat] {
        let text = try XCTUnwrap(value)
        return Dictionary(uniqueKeysWithValues: text.split(separator: ";").compactMap { pair in
            let pieces = pair.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2, let number = Double(pieces[1]) else { return nil }
            return (String(pieces[0]), CGFloat(number))
        })
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", "-qaNavalMode",
                               "-qaNavalRoadJunctionPosition", Self.inspectionFlag]
        app.launch()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: Self.timeout))
        return app
    }

    private func coldResume(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing", "-qaAutoStart", Self.inspectionFlag]
        app.launch()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: Self.timeout))
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
