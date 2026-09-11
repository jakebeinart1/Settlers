/// Victory-point tallying and win detection. Called by `RulesEngine.apply`
/// after every move that can change a player's VP total: building a
/// settlement/city, playing a VP dev card (via `buyDevCard`, since VP cards
/// are never "played" - they count as soon as they're in hand), and any move
/// that can change `longestRoadPlayer`/`largestArmyPlayer`.
public enum WinCondition {
    /// Total victory points for `player`: settlements + cities (at this
    /// mode's per-building rates) + VP dev cards, plus this mode's
    /// longest-road bonus if `player` holds it and its largest-army bonus if
    /// `player` holds that. A mode's supported targets and their reasoning
    /// live in `Ruleset.forMode(_:)`, not here - a global "the" target is
    /// exactly the assumption a second rule set breaks.
    public static func victoryPoints(for player: PlayerID, in state: GameState) -> Int {
        state.victoryPoints(for: player)
    }

    /// Sets `state.phase` to `.gameOver(winner:)` for the first player (in
    /// seat order) at or above **this game's** target. A no-op if nobody has
    /// reached it, or if the game is already over.
    ///
    /// The threshold comes from `state`, not from a constant here: a game
    /// started at eight has to end at eight after being saved, relaunched and
    /// resumed, and a replayed log has to end where the original did.
    public static func checkForWinner(_ state: inout GameState) {
        if case .gameOver = state.phase { return }
        let target = state.victoryPointTarget
        guard let winner = state.players.first(where: { victoryPoints(for: $0.id, in: state) >= target }) else {
            return
        }
        state.phase = .gameOver(winner: winner.id)
    }
}
