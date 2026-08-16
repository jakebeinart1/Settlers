import CatanEngine

/// A single per-opponent "how dangerous is this player" evaluation, used by
/// every other heuristic (`RobberHeuristics`, `BuildPlanner`,
/// `TradeHeuristics`, `DevCardHeuristics`) instead of each one inventing its
/// own notion of "the leader". See
/// `docs/superpowers/specs/2026-08-16-bot-threat-assessment-design.md`.
public enum ThreatAssessment {
    /// Weight applied to each victory point - the single biggest signal,
    /// since it's the actual win condition.
    private static let victoryPointWeight = 10.0
    /// Weight applied to a held (unplayed) dev card - a hidden but real
    /// threat (could be a knight toward Largest Army, or a VP card).
    private static let devCardWeight = 1.5

    /// The VP-equivalent bonus for being one move away from grabbing a
    /// bonus (`Largest Army` or `Longest Road`) that this player doesn't
    /// already hold - each is worth 2 real VP the instant it's claimed, so a
    /// player poised to grab one is more dangerous than their current VP
    /// total alone suggests.
    private static let milestoneSwingBonus = 2.5

    /// Raw threat score for a single player - current standing plus how
    /// close they are to a sudden VP swing. Not comparative on its own; see
    /// `scores`/`relativeWeight` for cross-player comparison.
    static func score(for playerID: PlayerID, in state: GameState) -> Double {
        guard let player = state.players.first(where: { $0.id == playerID }) else { return 0 }

        let production = player.settlements.reduce(0.0) { partial, vertex in
            partial + PlacementHeuristics.score(vertex: vertex, board: state.board)
        } + player.cities.reduce(0.0) { partial, vertex in
            partial + PlacementHeuristics.score(vertex: vertex, board: state.board) * 2.0
        }

        let vp = Double(state.victoryPoints(for: playerID)) * victoryPointWeight
        let devCards = Double(player.devCards.count) * devCardWeight

        return vp + production + devCards + milestoneSwing(for: player, in: state)
    }

    private static func milestoneSwing(for player: Player, in state: GameState) -> Double {
        var bonus = 0.0

        if state.largestArmyPlayer != player.id {
            let holderKnights = state.largestArmyPlayer
                .flatMap { holder in state.players.first(where: { $0.id == holder })?.playedKnights }
                ?? 0
            if player.playedKnights == 2, holderKnights <= 2 {
                bonus += milestoneSwingBonus
            }
        }

        if state.longestRoadPlayer != player.id {
            let length = LongestRoad.length(for: player, in: state)
            let holderLength = state.longestRoadPlayer
                .flatMap { holder in state.players.first(where: { $0.id == holder }) }
                .map { LongestRoad.length(for: $0, in: state) }
                ?? 0
            if length >= max(4, holderLength) {
                bonus += milestoneSwingBonus
            }
        }

        return bonus
    }

    /// Threat score for every player except `excluding`, highest first.
    public static func scores(excluding player: PlayerID, in state: GameState) -> [(player: PlayerID, score: Double)] {
        state.players
            .filter { $0.id != player }
            .map { (player: $0.id, score: score(for: $0.id, in: state)) }
            .sorted { $0.score > $1.score }
    }

    /// How threatening `target` is relative to the *average* opponent of
    /// `player` - 1.0 means "exactly average". Consumers multiply an
    /// existing effect by this instead of a flat leader/non-leader
    /// constant, so a dominant opponent draws sharply more attention and a
    /// close race doesn't get skewed onto whoever's nominally ahead by a
    /// hair. Clamped to `[0.4, 3.0]` so a single early-game outlier (e.g.
    /// the very first settlement placed) can't produce an extreme swing.
    /// Returns `1.0` for everyone when the average is `0` (e.g. before
    /// setup places anything) - dividing by zero would otherwise produce a
    /// meaningless weight at exactly the moment there's no real signal yet.
    public static func relativeWeight(for target: PlayerID, excluding player: PlayerID, in state: GameState) -> Double {
        let ranked = scores(excluding: player, in: state)
        guard !ranked.isEmpty else { return 1.0 }

        let average = ranked.reduce(0.0) { $0 + $1.score } / Double(ranked.count)
        guard average > 0, let targetScore = ranked.first(where: { $0.player == target })?.score else { return 1.0 }

        return min(3.0, max(0.4, targetScore / average))
    }
}
