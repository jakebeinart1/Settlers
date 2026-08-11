import CatanEngine

/// Chooses the best build-type move (road/settlement/city/dev card) available
/// on a bot's turn, if any is worth taking.
public enum BuildPlanner {
    /// The minimum score a candidate must clear to be worth taking over
    /// simply ending the turn (banking resources for something better).
    private static let worthItThreshold = 1.5

    /// Scores every legal build move for `player` in `state` and returns the
    /// highest-scoring one, or `nil` if nothing clears `worthItThreshold`
    /// (in which case the caller should fall back to something else, e.g.
    /// `.endTurn`). Only ever returns a move that appears in
    /// `RulesEngine.legalMoves(for: state)`.
    public static func chooseBuild(for state: GameState, player: PlayerID, personality: BotPersonality) -> GameMove? {
        let legal = RulesEngine.legalMoves(for: state)
        var best: (move: GameMove, score: Double)?

        for move in legal {
            guard let score = score(move, for: state, player: player, personality: personality) else { continue }
            if best == nil || score > best!.score {
                best = (move, score)
            }
        }

        guard let best, best.score >= worthItThreshold else { return nil }
        return best.move
    }

    /// `nil` for non-build moves (trades, dev-card plays, endTurn, etc.) -
    /// this task only plans building, not those other categories. Internal
    /// rather than private so `BuildPlannerTests` can compare scores
    /// directly instead of only inferring them through `chooseBuild`'s
    /// final pick.
    static func score(_ move: GameMove, for state: GameState, player: PlayerID, personality: BotPersonality) -> Double? {
        switch move {
        case .buildSettlement(let vertex):
            // A new settlement is close to always worth it - weight
            // production heavily and scale up by expansion appetite.
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
            return 3.0 + production * (0.5 + personality.expansionBias)

        case .buildCity(let vertex):
            // Upgrading doubles production on that vertex's tiles, so it's
            // valuable roughly in proportion to its existing production.
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
            return 2.5 + production * (0.4 + personality.expansionBias * 0.5)

        case .buildRoad(let edge):
            // Roads are cheap groundwork; value them modestly, with a bonus
            // for opening up a newly-reachable high-value settlement spot -
            // plus a large bonus if this exact road would hand *us* the
            // longest-road bonus (2 VP) right now, since that's otherwise
            // never factored into road value at all.
            let (a, b) = state.board.vertices(of: edge)
            let reachable = [a, b].flatMap { state.board.adjacentVertices(of: $0) }
            let bestReachable = reachable
                .map { PlacementHeuristics.score(vertex: $0, board: state.board) }
                .max() ?? 0
            let longestRoadBonus = claimsLongestRoad(edge, for: player, in: state) ? 2.5 : 0.0
            return 0.5 + personality.expansionBias + bestReachable * 0.2 + longestRoadBonus

        case .buyDevCard:
            // A flat, personality-nudged value: knights help aggressive
            // bots, but dev cards are a reasonable default use of surplus
            // ore/grain/wool for anyone. Boosted when we're one knight away
            // from *reaching* largest army (2 VP) and one more knight would
            // actually be enough to take (or claim) it - i.e. we don't
            // already hold it, and reaching 3 would exceed whatever the
            // current holder has (an unclaimed bonus counts as 0) -
            // otherwise a bot only ever thought about largest army
            // reactively, once it happened to already have a knight in
            // hand. Checking against the holder's real count (not just
            // "someone holds it") matters: if they're already at 5 played
            // knights, reaching 3 ourselves wouldn't take it from them.
            var value = 1.6 + personality.aggressiveness * 0.5
            if let me = state.players.first(where: { $0.id == player }), state.largestArmyPlayer != player {
                let wouldReach = me.playedKnights + 1
                let holderCount = state.largestArmyPlayer
                    .flatMap { holder in state.players.first(where: { $0.id == holder })?.playedKnights }
                    ?? 0
                if wouldReach >= 3, wouldReach > holderCount {
                    value += 1.0
                }
            }
            return value

        default:
            return nil
        }
    }

    /// Whether adding `edge` to `player`'s roads would make `player` the
    /// longest-road holder right now, when they aren't already. Simulates
    /// the build on a scratch copy of `state` rather than duplicating
    /// `LongestRoad`'s own path-length logic here. Internal rather than
    /// private so `BuildPlannerTests` can exercise it directly.
    static func claimsLongestRoad(_ edge: EdgeID, for player: PlayerID, in state: GameState) -> Bool {
        guard state.longestRoadPlayer != player,
              let playerIndex = state.players.firstIndex(where: { $0.id == player }) else { return false }
        var simulated = state
        simulated.players[playerIndex].roads.insert(edge)
        return LongestRoad.compute(for: simulated) == player
    }
}
