import XCTest

/// Camera navigation must work through real setup and CPU pacing. A stable
/// viewport rectangle alone cannot prove that a visible navigation button acts.
@MainActor
final class NativeNavigationFlowTests: XCTestCase {
    private static let timeout: TimeInterval = 5
    private static let cpuTimeout: TimeInterval = 30
    private static let frameTolerance: CGFloat = 0.01
    private static let poseTolerance = 0.001
    private static let minimumHitSide: CGFloat = 44
    private static let navigationHeight: CGFloat = 56
    private static let homeZoom = 2.6
    private static let resources = ["brick", "lumber", "ore", "grain", "wool"]
    private static let center = CGVector(dx: 0.5, dy: 0.5)
    // The left padding is outside the centered icon/text column. A button
    // that only accepts touches on its glyph cannot satisfy its 44pt target.
    private static let padding = CGVector(dx: 0.125, dy: 0.5)

    func testThreeSeatHomeReturnsFromWorldUsingTheWholeHitRegion() throws {
        try assertHomeOnlyJourney(playerCount: 3)
    }

    func testFourSeatHomeReturnsFromWorldUsingTheWholeHitRegion() throws {
        try assertHomeOnlyJourney(playerCount: 4)
    }

    func testThreeSeatNavigationThroughRealSetupCPUPacingAndColdResume() throws {
        try assertOrdinaryJourney(playerCount: 3)
    }

    func testFourSeatNavigationThroughRealSetupCPUPacingAndColdResume() throws {
        try assertOrdinaryJourney(playerCount: 4)
    }

    func testReturnPreservesAnAlreadyFittedPreviousPose() throws {
        let app = launchOpening(playerCount: 4)
        let board = app.otherElements["board.surface"]
        board.pinch(withScale: 0.2, velocity: -1)
        try waitForZoom(1, in: app)
        let fitted = try pose(in: app)
        let before = gameplaySnapshot(in: app)
        tap(app.buttons["naval.overview"], offset: Self.center)
        XCTAssertTrue(app.buttons["naval.overview"].label.localizedCaseInsensitiveContains("return"))
        tap(app.buttons["naval.overview"], offset: Self.padding)
        assertPose(try pose(in: app), equals: fitted)
        XCTAssertEqual(gameplaySnapshot(in: app), before)
        XCTAssertTrue(app.buttons["naval.overview"].label.localizedCaseInsensitiveContains("world"))
    }

    /// Independent of the new Return affordance: these fail only when real
    /// Home touches or the camera reset itself stop working.
    private func assertHomeOnlyJourney(playerCount: Int) throws {
        let app = launchOpening(playerCount: playerCount)
        let before = gameplaySnapshot(in: app)
        for offset in [Self.center, Self.padding] {
            tap(app.buttons["naval.overview"], offset: offset)
            try waitForZoom(1, in: app)
            tap(app.buttons["naval.home"], offset: offset)
            try waitForZoom(Self.homeZoom, in: app)
            let home = try pose(in: app)
            XCTAssertEqual(home.panX, 0, accuracy: Self.poseTolerance)
            XCTAssertEqual(home.panY, 0, accuracy: Self.poseTolerance)
            XCTAssertEqual(gameplaySnapshot(in: app), before)
            assertNavigationFrames(in: app)
        }
        retain("Naval navigation — \(playerCount) seats physical Home hit region", app: app)
    }

    private func assertOrdinaryJourney(playerCount: Int) throws {
        let app = launchOpening(playerCount: playerCount)
        try assertCustomViewReturnsExactly(in: app)
        try assertDraftNavigation(prefix: "board.vertex.", in: app)
        confirmDraft(in: app)
        try assertDraftNavigation(prefix: "board.edge.", in: app)
        confirmDraft(in: app)
        try assertCPUViewingNavigation(in: app, playerCount: playerCount)
        let skip = app.buttons["bot-progress.skip"]
        if skip.exists { tap(skip, offset: Self.center) }
        XCTAssertTrue(targets(prefix: "board.vertex.", in: app).firstMatch.waitForExistence(timeout: Self.cpuTimeout))
        try assertDraftNavigation(prefix: "board.vertex.", in: app)
        confirmDraft(in: app)
        try assertDraftNavigation(prefix: "board.edge.", in: app)
        confirmDraft(in: app)
        XCTAssertTrue(app.buttons["Roll Dice"].waitForExistence(timeout: Self.timeout))
        try assertStableRoundTrip(in: app)
        finishFirstRoll(in: app)
        try assertStableRoundTrip(in: app)
        let committed = gameplaySnapshot(in: app)
        coldResume(in: app)
        XCTAssertEqual(gameplaySnapshot(in: app), committed)
        try assertStableRoundTrip(in: app)
        retain("Naval navigation — \(playerCount) seats after ordinary cold resume", app: app)
    }

    private func launchOpening(playerCount: Int) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame", "-qaNavalMode",
                               "-qaNavalSeed=7501", "-qaNavalFamily=archipelago"]
        if playerCount == 3 { app.launchArguments.append("-qaNewGameThreeSeats") }
        app.launch()
        XCTAssertTrue(app.buttons["new-game.start"].waitForExistence(timeout: Self.timeout))
        app.buttons["As Shown"].tap()
        app.buttons["new-game.start"].tap()
        XCTAssertTrue(app.buttons["naval.overview"].waitForExistence(timeout: Self.timeout))
        app.buttons["game.settings"].tap()
        XCTAssertTrue(app.buttons["Slow"].waitForExistence(timeout: Self.timeout))
        app.buttons["Slow"].tap()
        app.buttons["No Limit"].tap()
        app.buttons["in-game-settings.close"].tap()
        assertNavigationFrames(in: app)
        return app
    }

    private func assertCustomViewReturnsExactly(in app: XCUIApplication) throws {
        let board = app.otherElements["board.surface"]
        let before = gameplaySnapshot(in: app)
        board.pinch(withScale: 1.4, velocity: 1)
        board.swipeLeft()
        let local = try pose(in: app)
        XCTAssertGreaterThan(local.zoom, Self.homeZoom)
        XCTAssertGreaterThan(abs(local.panX) + abs(local.panY), Self.poseTolerance)
        try roundTrip(in: app, expectedLocal: local)
        XCTAssertEqual(gameplaySnapshot(in: app), before)
        tap(app.buttons["naval.overview"], offset: Self.padding)
        try waitForZoom(1, in: app)
        tap(app.buttons["naval.home"], offset: Self.padding)
        try waitForZoom(Self.homeZoom, in: app)
        let home = try pose(in: app)
        XCTAssertEqual(home.panX, 0, accuracy: Self.poseTolerance)
        XCTAssertEqual(home.panY, 0, accuracy: Self.poseTolerance)
        XCTAssertTrue(app.buttons["naval.overview"].label.localizedCaseInsensitiveContains("world"))
        XCTAssertEqual(gameplaySnapshot(in: app), before)
        retain("Naval navigation — real setup Home and restored custom view", app: app)
    }

    private func assertDraftNavigation(prefix: String, in app: XCUIApplication) throws {
        let available = targets(prefix: prefix, in: app)
        XCTAssertTrue(available.firstMatch.waitForExistence(timeout: Self.timeout))
        let target = try XCTUnwrap(available.allElementsBoundByIndex.first(where: \.isHittable))
        target.tap()
        XCTAssertEqual(target.value as? String, "Selected")
        XCTAssertTrue(app.buttons["board-decision.confirm"].isEnabled)
        try assertStableRoundTrip(in: app)
        XCTAssertEqual(target.value as? String, "Selected", "Navigation changed the staged setup location")
    }

    private func assertStableRoundTrip(in app: XCUIApplication) throws {
        let before = gameplaySnapshot(in: app)
        let local = try pose(in: app)
        try roundTrip(in: app, expectedLocal: local)
        XCTAssertEqual(gameplaySnapshot(in: app), before,
                       "Camera navigation changed resources, discoveries, legal targets or a proposal")
        assertNavigationFrames(in: app)
    }

    private func roundTrip(in app: XCUIApplication, expectedLocal: Pose) throws {
        let boardFrame = app.otherElements["board.surface"].frame
        let world = app.buttons["naval.overview"]
        tap(world, offset: Self.center)
        try waitForZoom(1, in: app)
        let overview = try pose(in: app)
        XCTAssertEqual(overview.panX, 0, accuracy: Self.poseTolerance)
        XCTAssertEqual(overview.panY, 0, accuracy: Self.poseTolerance)
        XCTAssertTrue(world.label.localizedCaseInsensitiveContains("return"), "World must expose the way back to the local view")
        assertMeasuredNavigationBounds(in: app)
        tap(world, offset: Self.padding)
        try waitForZoom(expectedLocal.zoom, in: app)
        let returned = try pose(in: app)
        assertPose(returned, equals: expectedLocal)
        XCTAssertEqual(returned.hexSize / overview.hexSize, expectedLocal.zoom, accuracy: Self.poseTolerance)
        XCTAssertTrue(world.label.localizedCaseInsensitiveContains("world"))
        XCTAssertEqual(app.otherElements["board.surface"].frame, boardFrame)
    }

    /// Bots legitimately commit discoveries while the player looks around.
    /// Check the live CPU boundary and camera effect, while allowing that
    /// public progress; strict whole-state equality belongs to human boundaries.
    private func assertCPUViewingNavigation(in app: XCUIApplication, playerCount: Int) throws {
        let status = app.otherElements["bot-progress.status"]
        XCTAssertTrue(status.waitForExistence(timeout: Self.timeout))
        let viewing = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Viewing pause")).firstMatch
        XCTAssertTrue(viewing.waitForExistence(timeout: Self.timeout), "Ordinary Slow CPU pacing was not reached")
        let cards = humanResources(in: app)
        let chartedBefore = charted(in: app)
        tap(app.buttons["naval.overview"], offset: Self.padding)
        try waitForZoom(1, in: app)
        XCTAssertTrue(app.buttons["naval.overview"].label.localizedCaseInsensitiveContains("return"))
        retain("Naval navigation — \(playerCount) seats World during real CPU progress", app: app)
        tap(app.buttons["naval.home"], offset: Self.padding)
        try waitForZoom(Self.homeZoom, in: app)
        XCTAssertEqual(humanResources(in: app), cards, "Looking around must not spend the human's cards")
        XCTAssertGreaterThanOrEqual(charted(in: app), chartedBefore)
        XCTAssertFalse(app.otherElements["board.building-preview"].exists)
        XCTAssertFalse(app.otherElements["board.road-preview"].exists)
        assertNavigationFrames(in: app)
    }

    private func assertNavigationFrames(in app: XCUIApplication) {
        let map = app.otherElements["board.surface"].frame
        let band = CGRect(x: map.minX, y: map.maxY, width: map.width, height: Self.navigationHeight)
        for identifier in ["naval.home", "naval.overview", "naval.fleet.open"] {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.exists && control.isEnabled && control.isHittable, identifier)
            let frame = control.frame
            XCTAssertGreaterThanOrEqual(frame.width + Self.frameTolerance, Self.minimumHitSide, identifier)
            XCTAssertGreaterThanOrEqual(frame.height + Self.frameTolerance, Self.minimumHitSide, identifier)
            XCTAssertTrue(band.insetBy(dx: -Self.frameTolerance, dy: -Self.frameTolerance).contains(frame),
                          "\(identifier) escaped the permanently reserved navigation band: \(frame), band \(band)")
            XCTAssertTrue(app.frame.contains(frame), "\(identifier) is partly off screen")
            let name = app.staticTexts["Alex"]
            if name.exists { XCTAssertLessThanOrEqual(frame.maxY, name.frame.minY, "Navigation paints over the human nameplate") }
        }
    }

    /// Measure sibling leaves, never AX ancestors of the actual controls.
    /// Check these after Return semantics so the old source's baseline fails
    /// for the missing affordance rather than for its missing new QA markers.
    private func assertMeasuredNavigationBounds(in app: XCUIApplication) {
        let navigation = app.otherElements["naval.navigation.bounds"]
        let humanPanel = app.otherElements["game.human-panel.frame"]
        XCTAssertTrue(navigation.waitForExistence(timeout: Self.timeout), "Missing navigation allocation evidence")
        XCTAssertTrue(humanPanel.waitForExistence(timeout: Self.timeout), "Missing human-panel frame evidence")
        let band = navigation.frame
        XCTAssertEqual(band.height, Self.navigationHeight, accuracy: Self.frameTolerance)
        XCTAssertEqual(band.minY, app.otherElements["board.surface"].frame.maxY, accuracy: Self.frameTolerance)
        XCTAssertLessThanOrEqual(band.maxY, humanPanel.frame.minY,
                                 "The navigation strip overlaps the painted private HUD")
        for identifier in ["naval.home", "naval.overview", "naval.fleet.open"] {
            XCTAssertTrue(band.insetBy(dx: -Self.frameTolerance, dy: -Self.frameTolerance).contains(app.buttons[identifier].frame),
                          "\(identifier) extends outside its measured allocation")
        }
    }

    private func tap(_ button: XCUIElement, offset: CGVector) {
        XCTAssertTrue(button.isEnabled && button.isHittable, "Navigation target is not physically tappable: \(button.identifier)")
        button.coordinate(withNormalizedOffset: offset).tap()
    }

    private func confirmDraft(in app: XCUIApplication) {
        let confirm = app.buttons["board-decision.confirm"]
        XCTAssertTrue(confirm.isEnabled && confirm.isHittable)
        confirm.tap()
    }

    private func targets(prefix: String, in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }

    private func finishFirstRoll(in app: XCUIApplication) {
        app.buttons["Roll Dice"].tap()
        if app.buttons["End Turn"].waitForExistence(timeout: Self.timeout) { return }
        let tiles = targets(prefix: "board.tile.", in: app)
        XCTAssertTrue(tiles.firstMatch.waitForExistence(timeout: Self.timeout), "First roll reached neither main turn nor rolled-seven decision")
        guard let tile = tiles.allElementsBoundByIndex.first(where: \.isHittable) else { return XCTFail("No rolled-seven destination is tappable") }
        tile.tap()
        let confirm = app.buttons["board-decision.confirm"]
        if !confirm.isEnabled {
            let victim = targets(prefix: "robber.victim.", in: app).firstMatch
            XCTAssertTrue(victim.waitForExistence(timeout: Self.timeout))
            victim.tap()
        }
        confirmDraft(in: app)
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: Self.timeout))
    }

    private func coldResume(in app: XCUIApplication) {
        app.terminate()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["main-menu.resume"].waitForExistence(timeout: Self.timeout))
        app.buttons["main-menu.resume"].tap()
        XCTAssertTrue(app.buttons["End Turn"].waitForExistence(timeout: Self.timeout))
    }

    private struct GameplaySnapshot: Equatable {
        let resources: [String]
        let discoveries: String
        let selectedTargets: [String]
        let legalTargetCounts: [Int]
        let previews: [String]
        let canConfirm: Bool
    }

    private func gameplaySnapshot(in app: XCUIApplication) -> GameplaySnapshot {
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "board.", "Selected"))
        let previews = ["board.building-preview", "board.road-preview", "board.ship-preview"].map { identifier in
            let element = app.otherElements[identifier]
            return element.exists ? element.value as? String ?? "Missing preview semantics" : "Absent"
        }
        let confirm = app.buttons["board-decision.confirm"]
        return GameplaySnapshot(resources: humanResources(in: app),
            discoveries: app.buttons["naval.overview"].value as? String ?? "Missing discovery summary",
            selectedTargets: selected.allElementsBoundByIndex.map(\.identifier).sorted(),
            legalTargetCounts: ["board.vertex.", "board.edge.", "board.tile."].map { targets(prefix: $0, in: app).count },
            previews: previews, canConfirm: confirm.exists && confirm.isEnabled)
    }

    private func humanResources(in app: XCUIApplication) -> [String] {
        Self.resources.map { resource in
            let value = app.otherElements["human-resource.\(resource)"].value as? String
            XCTAssertNotNil(value, "Human resource evidence is missing for \(resource)")
            return value ?? "Missing \(resource)"
        }
    }

    private func charted(in app: XCUIApplication) -> Int {
        let summary = app.buttons["naval.overview"].value as? String ?? ""
        let counts = summary.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(counts.count, 2, "The public discovery summary is missing")
        return counts.first ?? -1
    }

    private struct Pose {
        let zoom: Double
        let panX: Double
        let panY: Double
        let hexSize: Double
    }

    private func pose(in app: XCUIApplication) throws -> Pose {
        let value = try XCTUnwrap(app.otherElements["naval.camera.reference"].value as? String)
        let fields = Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { part -> (String, Double)? in
            let components = part.split(separator: "=")
            guard components.count == 2, let number = Double(components[1]) else { return nil }
            return (String(components[0]), number)
        })
        return Pose(zoom: try XCTUnwrap(fields["zoom"]), panX: try XCTUnwrap(fields["panX"]),
                    panY: try XCTUnwrap(fields["panY"]), hexSize: try XCTUnwrap(fields["hexSize"]))
    }

    private func waitForZoom(_ zoom: Double, in app: XCUIApplication) throws {
        let marker = app.otherElements["naval.camera.reference"]
        let expected = String(format: "zoom=%.6f;", zoom)
        let predicate = NSPredicate { _, _ in (marker.value as? String)?.hasPrefix(expected) == true }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: Self.timeout), .completed)
        XCTAssertEqual(try pose(in: app).zoom, zoom, accuracy: Self.poseTolerance)
    }

    private func assertPose(_ actual: Pose, equals expected: Pose) {
        XCTAssertEqual(actual.zoom, expected.zoom, accuracy: Self.poseTolerance)
        XCTAssertEqual(actual.panX, expected.panX, accuracy: Self.poseTolerance)
        XCTAssertEqual(actual.panY, expected.panY, accuracy: Self.poseTolerance)
        XCTAssertEqual(actual.hexSize, expected.hexSize, accuracy: Self.poseTolerance)
    }

    private func retain(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
