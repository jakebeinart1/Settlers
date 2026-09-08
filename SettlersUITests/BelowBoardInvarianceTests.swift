import XCTest

/// The panels under the board occupy the same rectangles in every phase.
///
/// ## Why this test exists
/// `BoardViewportInvarianceTests` fixed the board's own frame by giving
/// everything below it one fixed `GameView.belowBoardReserve` band. That
/// stopped the board moving, but not the panels *inside* the band: the
/// 20-point info banner at the top of it was still omitted whenever a board
/// decision was up, so the player nameplate and the command row under it
/// jumped 20 points up the screen the moment a settlement placement, a
/// knight, or a rolled seven started - and dropped back when it ended. Jake
/// reported it as "the bottom pane sets up in a different location than where
/// the 3 buttons normally are, and the nameplate shifts up".
///
/// It is the same bug one level in: **a row whose height depends on the phase
/// moves every row after it.** The banner is reserved unconditionally now and
/// only its content is conditional.
///
/// A failure here means some row under the board became conditional again.
/// Fix it by reserving the row, not by moving what sits after it.
@MainActor
final class BelowBoardInvarianceTests: XCTestCase {
    private static let commandRow = "game.command-row"
    private static let boardSurface = "board.surface"

    /// Every fixture that changes which panel occupies the command row.
    ///
    /// `-qaShowDiscard` is deliberately absent: it is the one state that also
    /// removes `HumanPlayerPanel`, and it does so under a full-screen discard
    /// sheet that covers this whole band, so nothing a player can see moves.
    /// Including it would assert about a rectangle nobody is looking at.
    private static let phaseFixtures: [[String]] = [
        ["-qaAutoStart"],
        ["-qaAutoStart", "-qaFastForwardToRollDice"],
        ["-qaAutoStart", "-qaShowIncomingOffer"],
        ["-qaAutoStart", "-qaShowMandatoryRobberDecision"],
        ["-qaAutoStart", "-qaShowRoadBuildingDecision"],
        ["-qaAutoStart", "-qaShowPaidSettlementDecision"]
    ]

    func testTheCommandRowOccupiesTheSameFrameInEveryPhase() {
        continueAfterFailure = false

        var measured: [(flags: String, frame: CGRect)] = []
        for fixture in Self.phaseFixtures {
            measured.append((fixture.joined(separator: " "), commandRowFrame(launchedWith: fixture)))
        }

        guard let reference = measured.first else { return XCTFail("no fixtures") }
        for candidate in measured.dropFirst() {
            assertEqual(candidate.frame, reference.frame,
                        "the command row moved between phases:\n"
                        + "  \(reference.flags) -> \(reference.frame)\n"
                        + "  \(candidate.flags) -> \(candidate.frame)\n"
                        + "A row above it became conditional again - reserve that row rather "
                        + "than letting everything after it slide.")
        }
    }

    // MARK: - Helpers

    private func commandRowFrame(launchedWith flags: [String]) -> CGRect {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"] + flags
        app.launch()
        XCTAssertTrue(app.otherElements[Self.boardSurface].waitForExistence(timeout: 15),
                      "the board never appeared for \(flags.joined(separator: " "))")
        let row = app.otherElements[Self.commandRow]
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "no command row for \(flags.joined(separator: " "))")
        let frame = row.frame
        app.terminate()
        return frame
    }

    /// A point of tolerance, and not more: the regression this guards against
    /// is exactly 20 points, so anything looser would let it straight back in.
    private func assertEqual(_ actual: CGRect, _ expected: CGRect, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let tolerance: CGFloat = 1
        XCTAssertEqual(actual.minX, expected.minX, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: tolerance, message, file: file, line: line)
    }
}
