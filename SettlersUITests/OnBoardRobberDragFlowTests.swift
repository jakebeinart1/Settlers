import XCTest

/// Behavioral regressions use the existing origin identifier, so they compile
/// against Build 16 and fail there because an origin drag produces no preview.
@MainActor
final class OnBoardRobberDragFlowTests: XCTestCase {
    func testRolledSevenOriginDragRetargetsAndStillRequiresVictimAndConfirm() {
        let app = launch("-qaShowMandatoryRobberDecision")
        let destination = app.buttons[BoardDecisionUITestID.mandatoryRobberVictimTile]
        let origin = app.otherElements[BoardDecisionUITestID.robberOrigin]
        let before = origin.frame
        dragOrigin(to: destination, in: app)
        XCTAssertFalse(app.buttons[BoardDecisionUITestID.confirm].isEnabled)
        XCTAssertFalse(app.buttons[BoardDecisionUITestID.cancel].exists)
        victims(in: app).firstMatch.tap()
        XCTAssertTrue(app.buttons[BoardDecisionUITestID.confirm].isEnabled)

        let alternate = visibleTile(in: app, excluding: destination.identifier)
        dragOrigin(to: alternate, in: app)
        XCTAssertEqual(destination.value as? String, "Available destination")
        assertFrame(origin.frame, matches: before)
        app.buttons[BoardDecisionUITestID.clear].tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.robberPreview].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].exists)
        dragOrigin(to: destination, in: app)
        victims(in: app).firstMatch.tap()
        app.buttons[BoardDecisionUITestID.confirm].tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 3))
    }

    func testKnightOriginDragCanCancelAndPlayTheSameCardAgain() {
        let app = launch("-qaShowRobberTargeting", modifiers: ["-qaThreePlayerTable", "-qaHumanSeatTwo"])
        dragOrigin(to: visibleTile(in: app), in: app)
        XCTAssertFalse(app.staticTexts["dev-cards.result"].exists)
        app.buttons[BoardDecisionUITestID.cancel].tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["dev-cards.result"].exists)
        app.buttons["dev-cards.shelf"].tap()
        app.buttons["dev-cards.tile.knight"].tap()
        let play = app.buttons["dev-cards.play.knight"]
        XCTAssertTrue(play.isEnabled, "cancelling a robber preview must preserve the playable Knight")
        play.tap()
        dragOrigin(to: visibleTile(in: app), in: app)
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].exists)
    }

    func testOriginAndCradleDragsDoNotPanAZoomedBoard() {
        let app = launch("-qaShowMandatoryRobberDecision")
        let board = app.otherElements["board.surface"]
        board.pinch(withScale: 1.3, velocity: 2)
        XCTAssertTrue(app.buttons["board.recenter"].waitForExistence(timeout: 3))
        let origin = app.otherElements[BoardDecisionUITestID.robberOrigin]
        let before = origin.frame
        let destination = visibleTile(in: app)
        let targetBefore = destination.frame
        dragOrigin(to: destination, in: app)
        assertFrame(origin.frame, matches: before)
        assertFrame(destination.frame, matches: targetBefore)

        app.buttons[BoardDecisionUITestID.clear].tap()
        let cradle = app.otherElements[BoardDecisionUITestID.dragCradle]
        cradle.press(forDuration: 0.2, thenDragTo: destination)
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.robberPreview].waitForExistence(timeout: 3))
        assertFrame(origin.frame, matches: before)
        assertFrame(destination.frame, matches: targetBefore)
        app.buttons["board.recenter"].tap()
        XCTAssertTrue(app.buttons["board.recenter"].waitForNonExistence(timeout: 3))
    }

    func testInvalidOriginDropPreservesPreviewAndLegalTileTapsStillRetarget() {
        let app = launch("-qaShowMandatoryRobberDecision")
        let tile = visibleTile(in: app)
        tile.tap()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.robberPreview].waitForExistence(timeout: 3))
        let origin = app.otherElements[BoardDecisionUITestID.robberOrigin]
        let board = app.otherElements["board.surface"]
        let previewBefore = app.otherElements[BoardDecisionUITestID.robberPreview].frame
        let outside = board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -12))
        origin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2, thenDragTo: outside)
        assertFrame(app.otherElements[BoardDecisionUITestID.robberPreview].frame, matches: previewBefore)
        XCTAssertEqual(tile.value as? String, "Selected destination")
        let another = visibleTile(in: app, excluding: tile.identifier)
        another.tap()
        XCTAssertEqual(another.value as? String, "Selected destination")
        XCTAssertEqual(tile.value as? String, "Available destination")
    }

    private func launch(_ flag: String, modifiers: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaAutoStart", flag] + modifiers
        app.launch()
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.robberOrigin].exists)
        return app
    }

    private func dragOrigin(to destination: XCUIElement, in app: XCUIApplication) {
        let origin = app.otherElements[BoardDecisionUITestID.robberOrigin]
        XCTAssertTrue(destination.exists)
        let boardFrame = app.otherElements["board.surface"].frame
        XCTAssertTrue(boardFrame.contains(CGPoint(x: origin.frame.midX, y: origin.frame.midY)))
        let start = origin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.robberPreview].waitForExistence(timeout: 3),
                      "dragging the canonical on-board robber must stage a destination")
        XCTAssertEqual(destination.value as? String, "Selected destination")
        XCTAssertTrue(app.otherElements[BoardDecisionUITestID.dock].exists,
                      "a drop must not commit the move")
    }

    private func visibleTile(in app: XCUIApplication, excluding identifier: String? = nil) -> XCUIElement {
        let boardFrame = app.otherElements["board.surface"].frame
        let query = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "board.tile."))
        let targets = query.allElementsBoundByIndex.filter {
            $0.identifier != identifier && boardFrame.contains($0.frame)
        }
        let result = targets.min {
            hypot($0.frame.midX - boardFrame.midX, $0.frame.midY - boardFrame.midY)
            < hypot($1.frame.midX - boardFrame.midX, $1.frame.midY - boardFrame.midY)
        }
        guard let result else { XCTFail("no visible legal tile target"); return query.firstMatch }
        return result
    }

    private func victims(in app: XCUIApplication) -> XCUIElementQuery {
        let query = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", BoardDecisionUITestID.victimPrefix))
        XCTAssertTrue(query.firstMatch.waitForExistence(timeout: 3))
        return query
    }

    private func assertFrame(_ actual: CGRect, matches expected: CGRect,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.midX, expected.midX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.midY, expected.midY, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, file: file, line: line)
    }
}
