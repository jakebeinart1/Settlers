import CatanEngine

/// A single per-opponent "how dangerous is this player" evaluation, used by
/// every other heuristic (`RobberHeuristics`, `BuildPlanner`,
/// `TradeHeuristics`, `DevCardHeuristics`) instead of each one inventing its
/// own notion of "the leader". See
/// `docs/superpowers/specs/2026-08-16-bot-threat-assessment-design.md`.
public enum ThreatAssessment {
    /// Raw threat score for a single player - current standing plus how
    /// close they are to a sudden VP swing. Not comparative on its own; see
    /// `scores`/`relativeWeight` for cross-player comparison.
    ///
    /// ## `viewer` is what keeps this honest
    /// A bot may INFER that someone is sitting on a victory-point card. It may
    /// not read the card. This scorer used to take `state.victoryPoints`, the
    /// engine's true total, for every player it judged - so the instant a
    /// human drew a victory-point card their threat score rose by
    /// `victoryPointWeight` (10.0, the largest single term here) and the bots
    /// turned on them. The player cannot see a bot's hidden cards and reported
    /// exactly this asymmetry from real play: "they know I have 3 victory
    /// points in development cards".
    ///
    /// `viewer` is the seat doing the judging, so the split is a rule rather
    /// than a convention: your own hand is yours to count, everyone else is
    /// worth only what the board shows - buildings, longest road, largest
    /// army. What remains legitimately visible about a hidden card is that it
    /// EXISTS: `devCardWeight` still counts how many cards a player holds,
    /// because a face-down count is public in real Catan. That is the whole of
    /// the inference a bot is entitled to.
    static func score(for playerID: PlayerID, asSeenBy viewer: PlayerID,
                      in state: GameState, weights: BotWeights = .default) -> Double {
        guard let player = state.players.first(where: { $0.id == playerID }) else { return 0 }

        // The `* 2.0` on cities is the rule that a city produces two of a
        // resource where a settlement produces one - not a tunable weight.
        let production = player.settlements.reduce(0.0) { partial, vertex in
            partial + PlacementHeuristics.score(vertex: vertex, board: state.board, weights: weights)
        } + player.cities.reduce(0.0) { partial, vertex in
            partial + PlacementHeuristics.score(vertex: vertex, board: state.board, weights: weights) * 2.0
        }

        let visiblePoints = playerID == viewer
            ? state.victoryPoints(for: playerID)
            : state.publicVictoryPoints(for: playerID)
        let vp = Double(visiblePoints) * weights.victoryPointWeight
        let devCards = Double(player.devCards.count) * weights.devCardWeight

        return vp + production + devCards + milestoneSwing(for: player, in: state, weights: weights)
    }

    private static func milestoneSwing(for player: Player, in state: GameState, weights: BotWeights) -> Double {
        var bonus = 0.0

        if state.largestArmyPlayer != player.id {
            let holderKnights = state.largestArmyPlayer
                .flatMap { holder in state.players.first(where: { $0.id == holder })?.playedKnights }
                ?? 0
            if player.playedKnights == weights.armyMilestoneWatchKnights,
               holderKnights <= weights.armyMilestoneWatchKnights {
                bonus += weights.milestoneSwingBonus
            }
        }

        if state.longestRoadPlayer != player.id {
            let length = LongestRoad.length(for: player, in: state)
            let holderLength = state.longestRoadPlayer
                .flatMap { holder in state.players.first(where: { $0.id == holder }) }
                .map { LongestRoad.length(for: $0, in: state) }
                ?? 0
            if length >= max(weights.roadMilestoneWatchLength, holderLength) {
                bonus += weights.milestoneSwingBonus
            }
        }

        return bonus
    }

    /// Threat score for every player except `excluding`, highest first.
    public static func scores(
        excluding player: PlayerID,
        in state: GameState,
        weights: BotWeights = .default
    ) -> [(player: PlayerID, score: Double)] {
        state.players
            .filter { $0.id != player }
            .map { (player: $0.id, score: score(for: $0.id, asSeenBy: player, in: state, weights: weights)) }
            .sorted { $0.score > $1.score }
    }

    /// How threatening `target` is relative to the *average* opponent of
    /// `player` - 1.0 means "exactly average". Consumers multiply an
    /// existing effect by this instead of a flat leader/non-leader
    /// constant, so a dominant opponent draws sharply more attention and a
    /// close race doesn't get skewed onto whoever's nominally ahead by a
    /// hair. Clamped to `[relativeWeightFloor, relativeWeightCeiling]` so a
    /// single early-game outlier (e.g. the very first settlement placed)
    /// can't produce an extreme swing.
    /// Returns `1.0` for everyone when the average is `0` (e.g. before
    /// setup places anything) - dividing by zero would otherwise produce a
    /// meaningless weight at exactly the moment there's no real signal yet.
    public static func relativeWeight(
        for target: PlayerID,
        excluding player: PlayerID,
        in state: GameState,
        weights: BotWeights = .default
    ) -> Double {
        let ranked = scores(excluding: player, in: state, weights: weights)
        guard !ranked.isEmpty else { return 1.0 }

        let average = ranked.reduce(0.0) { $0 + $1.score } / Double(ranked.count)
        guard average > 0, let targetScore = ranked.first(where: { $0.player == target })?.score else { return 1.0 }

        return min(weights.relativeWeightCeiling, max(weights.relativeWeightFloor, targetScore / average))
    }

    /// How `player` is doing relative to the average of every other player -
    /// same underlying score as `relativeWeight`, but for judging your own
    /// standing in the game rather than an opponent's threat level. `1.0` is
    /// "exactly average"; above that is ahead of the field, below is behind.
    /// Clamped to `[ownStandingFloor, ownStandingCeiling]` for the same reason
    /// `relativeWeight` clamps - a single early-game outlier shouldn't
    /// produce an extreme swing.
    /// Consumers (e.g. `TradeHeuristics`) use this to play with "winning in
    /// mind": a bot that's behind has more reason to take a genuinely fair
    /// deal to catch up, while a bot with a comfortable lead has less reason
    /// to hand an opponent resources for a merely-okay trade, since helping
    /// them catch up costs more than the deal itself is worth.
    public static func ownStanding(for player: PlayerID, in state: GameState, weights: BotWeights = .default) -> Double {
        let others = scores(excluding: player, in: state, weights: weights)
        guard !others.isEmpty else { return 1.0 }

        let average = others.reduce(0.0) { $0 + $1.score } / Double(others.count)
        // `asSeenBy: player` is the seat itself, so this one DOES count held
        // victory-point cards: a bot judging whether it is ahead knows its own
        // hand, and hiding it from itself would make it trade like a player
        // who cannot see their own cards.
        let myScore = score(for: player, asSeenBy: player, in: state, weights: weights)
        // Unlike `relativeWeight` (which compares one opponent to the
        // *other* opponents' average, and bails to a neutral `1.0` when
        // that average is still `0`, since it's judging someone else's
        // early outlier against a genuinely empty field), a `0` average
        // here doesn't mean there's no signal - `player`'s own score can
        // still be meaningfully ahead of a field that hasn't built anything
        // yet, and that's real information worth keeping.
        guard average > 0 else { return myScore > 0 ? weights.ownStandingCeiling : 1.0 }

        return min(weights.ownStandingCeiling, max(weights.ownStandingFloor, myScore / average))
    }
}
