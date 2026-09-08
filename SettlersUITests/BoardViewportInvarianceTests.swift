import XCTest

/// The board occupies the same rectangle in every phase of a game.
///
/// ## Why this test exists
/// The board's size and position were a *remainder*: `GameView` gave it
/// `maxHeight: .infinity` in a column whose other rows came and went, so its
/// container measured 362.67, 382.67 or 503.67 points on the same device in
/// the same game depending on which panels happened to be up. `BoardView`
/// papered over that by locking its fit to the tallest container it had been
/// given, which turned a frame-dependent board size into a history-dependent
/// one: a game that rolled a seven kept a board 39% too big for every later
/// screen, drawn below its container and clipped at the bottom edge, and a
/// game that never rolled one did not. Two identical games, two board sizes.
///
/// `GameView.belowBoardReserve` fixes the height of everything under the
/// board so the board's container cannot vary, and `BoardView.solvedFit` is a
/// pure function again. **This test is what holds that.** It reads the board's
/// own frame - not any ring or tile, which depend on the randomised board -
/// so it compares the one thing that must be identical no matter what is on
/// the board or which phase produced it.
///
/// A failure here means some panel is taking height from the board again.
/// The fix is in `GameView`'s layout, never in `BoardView`: do not answer it
/// by re-introducing a remembered fit.
@MainActor
final class BoardViewportInvarianceTests: XCTestCase {
    private static let boardSurface = "board.surface"

    /// Every fixture that puts a different set of panels under the board.
    /// `-qaShowDiscard` is the one that used to be 141 points taller than the
    /// rest, because it replaces the whole below-board stack with a sheet.
    private static let phaseFixtures: [[String]] = [
        ["-qaAutoStart"],
        ["-qaAutoStart", "-qaFastForwardToRollDice"],
        ["-qaAutoStart", "-qaShowIncomingOffer"],
        ["-qaAutoStart", "-qaShowMandatoryRobberDecision"],
        ["-qaAutoStart", "-qaShowDiscard"],
        ["-qaAutoStart", "-qaShowRoadBuildingDecision"]
    ]

    func testTheBoardOccupiesTheSameFrameInEveryPhase() {
        continueAfterFailure = false

        var measured: [(flags: String, frame: CGRect)] = []
        for fixture in Self.phaseFixtures {
            measured.append((fixture.joined(separator: " "), boardFrame(launchedWith: fixture)))
        }

        guard let reference = measured.first else { return XCTFail("no fixtures") }
        for candidate in measured.dropFirst() {
            assertEqual(candidate.frame, reference.frame,
                        "the board moved between phases:\n"
                        + "  \(reference.flags) -> \(reference.frame)\n"
                        + "  \(candidate.flags) -> \(candidate.frame)\n"
                        + "Some panel is taking height from the board again - fix GameView's "
                        + "layout, not BoardView's fit.")
        }
    }

    // MARK: - Helpers

    private func boardFrame(launchedWith flags: [String]) -> CGRect {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"] + flags
        app.launch()
        let board = app.otherElements[Self.boardSurface]
        XCTAssertTrue(board.waitForExistence(timeout: 15),
                      "the board never appeared for \(flags.joined(separator: " "))")
        let frame = board.frame
        app.terminate()
        return frame
    }

    /// A point of tolerance, and not more. The heights this guards against
    /// differ by 20 points at the very least, so anything looser would let the
    /// original bug back through while still passing.
    private func assertEqual(_ actual: CGRect, _ expected: CGRect, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let tolerance: CGFloat = 1
        XCTAssertEqual(actual.minX, expected.minX, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: tolerance, message, file: file, line: line)
    }
}
