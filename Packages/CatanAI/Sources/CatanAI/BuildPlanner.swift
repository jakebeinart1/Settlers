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
    /// this task only plans building, not those other categories.
    private static func score(_ move: GameMove, for state: GameState, player: PlayerID, personality: BotPersonality) -> Double? {
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
            // for opening up a newly-reachable high-value settlement spot.
            let (a, b) = state.board.vertices(of: edge)
            let reachable = [a, b].flatMap { state.board.adjacentVertices(of: $0) }
            let bestReachable = reachable
                .map { PlacementHeuristics.score(vertex: $0, board: state.board) }
                .max() ?? 0
            return 0.5 + personality.expansionBias + bestReachable * 0.2

        case .buyDevCard:
            // A flat, personality-nudged value: knights help aggressive
            // bots, but dev cards are a reasonable default use of surplus
            // ore/grain/wool for anyone.
            return 1.6 + personality.aggressiveness * 0.5

        default:
            return nil
        }
    }
}
