/// Victory-point tallying and win detection. Called by `RulesEngine.apply`
/// after every move that can change a player's VP total: building a
/// settlement/city, playing a VP dev card (via `buyDevCard`, since VP cards
/// are never "played" - they count as soon as they're in hand), and any move
/// that can change `longestRoadPlayer`/`largestArmyPlayer`.
public enum WinCondition {
    /// Total victory points for `player`: settlements + 2x cities + VP dev
    /// cards (from `Player.victoryPoints`), plus +2 if `player` holds
    /// longest road and +2 if `player` holds largest army.
    public static func victoryPoints(for player: PlayerID, in state: GameState) -> Int {
        state.victoryPoints(for: player)
    }

    /// Sets `state.phase` to `.gameOver(winner:)` for the first player (in
    /// seat order) found at 10 or more victory points. A no-op if nobody has
    /// reached the threshold, or if the game is already over.
    public static func checkForWinner(_ state: inout GameState) {
        if case .gameOver = state.phase { return }
        guard let winner = state.players.first(where: { victoryPoints(for: $0.id, in: state) >= 10 }) else {
            return
        }
        state.phase = .gameOver(winner: winner.id)
    }
}
