import XCTest

/// The board camera, driven through real touches.
///
/// `BoardCameraTests` proves the camera's arithmetic; this proves the arithmetic
/// is actually wired to fingers. Both are needed: the clamp can be perfect while
/// the gesture is attached to a layer that never receives it, and a gesture can
/// fire while drawing through a geometry that nothing else on the board follows.
@MainActor
final class BoardCameraFlowTests: XCTestCase {
    private enum CameraID {
        static let board = "board.surface"
        static let recenter = "board.recenter"
        static let vertexPrefix = "board.vertex."
        static let buildingPreview = "board.building-preview"
    }

    func testPinchingZoomsTheBoardAndRecenterRestoresTheFit() {
        continueAfterFailure = false
        let app = launchOpeningPlacement()

        let recenter = app.buttons[CameraID.recenter]
        XCTAssertFalse(recenter.exists,
                       "the board must start at its fitted resting camera, with nothing to recenter")

        let witnesses = witnessRings(in: app)
        let fitted = positions(of: witnesses, in: app)

        app.otherElements[CameraID.board].pinch(withScale: 2.5, velocity: 3)

        XCTAssertTrue(recenter.waitForExistence(timeout: 2),
                      "the recenter control appears only once the camera has left its fit")
        let zoomed = positions(of: witnesses, in: app)
        XCTAssertGreaterThan(spread(zoomed), spread(fitted) * 1.2,
                             "pinching did not spread the board out: \(fitted) -> \(zoomed)")

        recenter.tap()

        XCTAssertTrue(recenter.waitForNonExistence(timeout: 3),
                      "recenter must return the camera to the fit, which hides the control")
        assertPositions(positions(of: witnesses, in: app), match: fitted,
                        "recenter did not land back on the fitted board")
    }

    /// The reported bug: the board re-zoomed and shifted by itself as panels
    /// came and went. Staging a settlement changes the dock's contents, which is
    /// exactly the sibling-height change that used to move the board.
    func testStagingAPieceDoesNotMoveTheBoard() {
        continueAfterFailure = false
        let app = launchOpeningPlacement()

        let witnesses = witnessRings(in: app)
        let before = positions(of: witnesses, in: app)

        stageSettlement(in: app, avoiding: witnesses)

        assertPositions(positions(of: witnesses, in: app), match: before,
                        "the board moved when the decision panel changed")
    }

    /// Zoom is player state, not a transient: a panel appearing must not throw
    /// away where the player was looking.
    func testTheCameraSurvivesAPanelChange() {
        continueAfterFailure = false
        let app = launchOpeningPlacement()

        app.otherElements[CameraID.board].pinch(withScale: 2.5, velocity: 3)
        let recenter = app.buttons[CameraID.recenter]
        XCTAssertTrue(recenter.waitForExistence(timeout: 2))

        let witnesses = witnessRings(in: app)
        let zoomed = positions(of: witnesses, in: app)

        stageSettlement(in: app, avoiding: witnesses)

        XCTAssertTrue(recenter.exists, "the zoom was silently discarded by a panel change")
        assertPositions(positions(of: witnesses, in: app), match: zoomed,
                        "the zoomed board moved when the decision panel changed")
    }

    // MARK: - Helpers

    /// The opening settlement placement: the one screen that is on the board,
    /// needs no prior moves, and exposes placement rings to measure.
    private func launchOpeningPlacement() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart"]
        app.launch()
        XCTAssertTrue(app.otherElements[CameraID.board].waitForExistence(timeout: 10))
        return app
    }

    private func vertexTargets(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", CameraID.vertexPrefix))
    }

    /// Two placement rings, held by identifier rather than by position in the
    /// query: staging a piece rebuilds the target layer, and a positional query
    /// would silently start measuring different rings, making every frame
    /// comparison below meaningless.
    private func witnessRings(in app: XCUIApplication) -> [String] {
        let targets = vertexTargets(in: app)
        XCTAssertTrue(targets.element(boundBy: 0).waitForExistence(timeout: 5),
                      "the opening settlement placement offers no target")
        XCTAssertGreaterThan(targets.count, 2, "need several rings to measure the camera by")
        return [targets.element(boundBy: 0).identifier, targets.element(boundBy: 1).identifier]
    }

    /// Ring centers are the camera-independent witness: they are positioned
    /// from the same `HexGeometry` the camera produces. Their *sizes* are not -
    /// a tap target has a 44pt minimum and stays 44pt at any zoom - so zoom has
    /// to be read from how far apart they sit, not from how big they are.
    private func positions(of identifiers: [String], in app: XCUIApplication) -> [CGPoint] {
        identifiers.map {
            let frame = app.buttons[$0].frame
            return CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    private func spread(_ points: [CGPoint]) -> CGFloat {
        hypot(points[0].x - points[1].x, points[0].y - points[1].y)
    }

    /// Stages a settlement on some ring that is neither witness and is actually
    /// on screen - zoomed in, most of the board is not.
    private func stageSettlement(in app: XCUIApplication, avoiding witnesses: [String]) {
        let targets = vertexTargets(in: app)
        let window = app.windows.element(boundBy: 0).frame
        let center = CGPoint(x: window.midX, y: window.midY)

        // Nearest the middle of the screen, not merely on it. `isHittable`
        // cannot be asked here: for an element the camera has pushed off
        // screen it raises rather than answering false, which is what made an
        // earlier version of this fail on the zoomed board.
        let ring = (0..<targets.count)
            .map { targets.element(boundBy: $0) }
            .filter { !witnesses.contains($0.identifier) && window.contains($0.frame) }
            .min { hypot($0.frame.midX - center.x, $0.frame.midY - center.y)
                 < hypot($1.frame.midX - center.x, $1.frame.midY - center.y) }
        guard let ring else { return XCTFail("no ring on screen to stage a settlement on") }
        ring.tap()
        XCTAssertTrue(app.otherElements[CameraID.buildingPreview].waitForExistence(timeout: 3),
                      "tapping a ring did not stage a settlement")
    }

    private func assertPositions(_ actual: [CGPoint], match expected: [CGPoint], _ message: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let tolerance: CGFloat = 0.5
        for (actual, expected) in zip(actual, expected) {
            XCTAssertEqual(actual.x, expected.x, accuracy: tolerance, message, file: file, line: line)
            XCTAssertEqual(actual.y, expected.y, accuracy: tolerance, message, file: file, line: line)
        }
    }
}
