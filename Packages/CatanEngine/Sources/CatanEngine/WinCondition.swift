/// Victory-point tallying and win detection. Called by `RulesEngine.apply`
/// after every move that can change a player's VP total: building a
/// settlement/city, playing a VP dev card (via `buyDevCard`, since VP cards
/// are never "played" - they count as soon as they're in hand), and any move
/// that can change `longestRoadPlayer`/`largestArmyPlayer`.
public enum WinCondition {
    /// The standard game's target, and the default for any save that predates
    /// the setting.
    public static let standardTarget = 10

    /// Targets a game may be started at.
    ///
    /// The upper bound is not arbitrary: buildings alone cap at 13 victory
    /// points (five settlements upgraded to four cities is 4 + 2x4 = 12, plus
    /// one un-upgraded settlement), so a target far above that can only be
    /// reached through development cards and the two bonus tiles, which makes
    /// for a game that stalls rather than one that lasts. Below eight the
    /// setup placements have very nearly decided it.
    public static let supportedTargets = 8...12

    /// Total victory points for `player`: settlements + 2x cities + VP dev
    /// cards (from `Player.victoryPoints`), plus +2 if `player` holds
    /// longest road and +2 if `player` holds largest army.
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
