import XCTest

/// The New Game screen must not resize when the keyboard comes up.
///
/// It used to. The whole configuration lives inside a `GeometryReader` that
/// derives `isShortScreen` (and every spacing from it) from the height it is
/// given, and the keyboard shrinks the safe area - so tapping a name field
/// visibly scrunched the seat cards, the section headers and the bottom bar
/// upward, animated, and sprang them back on dismiss. Jake reported it from
/// the phone on 2026-09-07. `.ignoresSafeArea(.keyboard)` makes the keyboard an
/// overlay instead.
///
/// The bottom bar is the right thing to measure: it is pinned to the bottom of
/// the screen, so it moves first and furthest when the safe area changes.
@MainActor
final class NewGameKeyboardInvarianceTests: XCTestCase {
    func testTheLayoutDoesNotMoveWhenTheKeyboardOpens() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset", "-qaShowNewGame"]
        app.launch()

        let start = app.buttons["new-game.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let before = start.frame

        let name = app.textFields["new-game.seat-name.0"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5), "The keyboard never appeared")

        XCTAssertEqual(start.frame, before,
                       "The bottom bar moved when the keyboard opened: the screen is still resizing around it")
    }
}
