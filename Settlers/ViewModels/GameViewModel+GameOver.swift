import CatanEngine

/// The game-over screen's two actions.
///
/// Jake, 2026-09-25: "from the game over menu, the buttons do the same thing.
/// New game should be the same as restart game. Main menu should take you to
/// main menu." The screen had one button, titled New Game, that cleared the
/// match and returned to the menu - so it never started a game.
extension GameViewModel {

    /// "New Game" on the game-over screen: the same table again, as the
    /// in-game Restart does. The finished match is cleared first, exactly as
    /// Main Menu clears it, so its completion receipt and recording are
    /// committed before the new match replaces the document.
    @discardableResult
    public func restartCompletedMatch() -> Bool {
        guard let finished = checkpointDocument?.activeMatch?.setup else { return false }
        guard clearCompletedMatch() else { return false }
        var table = finished
        table.randomizeSeatOrder = false
        table.normalizeNewGameOptions()
        var prefill = matchSetupStore.load().value ?? table
        prefill.normalizeNewGameOptions()
        startNewGame(setup: table, configuredAs: prefill)
        return true
    }
}
