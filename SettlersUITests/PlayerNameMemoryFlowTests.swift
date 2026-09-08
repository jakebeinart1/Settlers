import XCTest

/// The name typed on New Game is the prefill for the next New Game.
///
/// This was not true before 2026-09-07, and the reason is worth keeping: the
/// previous setup *was* saved (`MatchSetupStore`), but `NewGameSetupView`
/// overwrites the saved setup's human name with the `PlayerNameStore`
/// preference every time it opens, and only App Settings ever wrote that
/// preference. So a name typed here survived exactly until the next visit to
/// the screen. Starting a game now writes the preference too.
///
/// Driven through the real screens rather than the store, because the bug was
/// never in the store - it was in which of two saved values won.
@MainActor
final class PlayerNameMemoryFlowTests: XCTestCase {
    func testTheNameTypedOnNewGameIsPrefilledNextTime() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-reset"]
        app.launch()

        openNewGame(in: app)
        let name = app.textFields["new-game.seat-name.0"]
        XCTAssertTrue(name.waitForExistence(timeout: 3), "seat name field")
        replaceText(in: name, with: "Boudica")
        // The keyboard overlays this screen rather than compressing it (see
        // `NewGameKeyboardInvarianceTests`), so it covers the bottom bar while
        // it is up. Dismiss it the way the field's Done key does, then start.
        name.typeText("\n")
        XCTAssertTrue(app.keyboards.element.waitForNonExistence(timeout: 3), "keyboard did not dismiss")

        app.buttons["new-game.start"].tap()
        XCTAssertTrue(app.otherElements["screen.game"].waitForExistence(timeout: 15), "board after Start")

        quitToMainMenu(in: app)
        openNewGame(in: app)

        XCTAssertEqual(app.textFields["new-game.seat-name.0"].value as? String, "Boudica")
    }

    private func openNewGame(in app: XCUIApplication) {
        let newGame = app.buttons["main-menu.new-game"]
        XCTAssertTrue(newGame.waitForExistence(timeout: 5), "New Game button")
        newGame.tap()
        XCTAssertTrue(app.otherElements["screen.new-game"].waitForExistence(timeout: 3), "New Game screen")
    }

    private func quitToMainMenu(in app: XCUIApplication) {
        app.buttons["game.settings"].tap()
        XCTAssertTrue(app.otherElements["screen.in-game-settings"].waitForExistence(timeout: 3), "pause screen")
        app.buttons["in-game-settings.quit"].tap()
        let confirm = app.buttons["Main Menu"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2), "quit confirmation")
        confirm.tap()
        XCTAssertTrue(app.otherElements["screen.main-menu"].waitForExistence(timeout: 5), "main menu")
    }

    /// `-ui-testing-reset` seeds a name, so the field is never empty; delete
    /// what is there one character at a time rather than assuming a length.
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        field.typeText(text)
    }
}
