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
            // production heavily and scale up by expansion appetite. Also
            // adds a bonus for denying a threatening opponent's near-term
            // expansion spot, if this vertex is one.
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
            let denial = denialBonus(vertex: vertex, state: state, player: player)
            return 3.0 + production * (0.5 + personality.expansionBias) + denial

        case .buildCity(let vertex):
            // Upgrading doubles production on that vertex's tiles, so it's
            // valuable roughly in proportion to its existing production.
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
            return 2.5 + production * (0.4 + personality.expansionBias * 0.5)

        case .buildRoad(let edge):
            // Roads are cheap groundwork; value them modestly, with a bonus
            // for opening up a newly-reachable high-value settlement spot,
            // a bonus for blocking a threatening opponent's network, plus a
            // large bonus if this exact road would hand *us* the
            // longest-road bonus (2 VP) right now - larger still if it
            // would take that bonus away from a currently-threatening
            // holder, not just claim it fresh.
            let (a, b) = state.board.vertices(of: edge)
            let reachable = [a, b].flatMap { state.board.adjacentVertices(of: $0) }.filter { isBuildableVertex($0, in: state) }
            let bestReachable = reachable
                .map { PlacementHeuristics.score(vertex: $0, board: state.board) }
                .max() ?? 0
            let blockingBonus = blocksOpponentNetwork(edge, state: state, player: player)
            var longestRoadBonus = 0.0
            if claimsLongestRoad(edge, for: player, in: state) {
                let holderWeight = state.longestRoadPlayer
                    .map { holder in ThreatAssessment.relativeWeight(for: holder, excluding: player, in: state) }
                    ?? 1.0
                longestRoadBonus = 2.5 * (state.longestRoadPlayer == nil ? 1.0 : holderWeight)
            }
            return 0.5 + personality.expansionBias + bestReachable * 0.2 + blockingBonus + longestRoadBonus

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

    /// Whether `vertex` could ever legally hold a settlement right now -
    /// not already occupied by anyone, and not within the distance-rule
    /// radius of an existing settlement/city. A road's "leads to a good
    /// future spot" bonus (`bestReachable` in `.buildRoad`'s scoring) must
    /// only count vertices this is true for - otherwise a road pointing at
    /// an opponent's already-built settlement on a great tile scores just
    /// as high as one pointing at a genuinely open spot, even though the
    /// former can never actually be settled.
    private static func isBuildableVertex(_ vertex: VertexID, in state: GameState) -> Bool {
        let occupied = Set(state.players.flatMap { $0.settlements.union($0.cities) })
        guard !occupied.contains(vertex) else { return false }
        return !state.board.adjacentVertices(of: vertex).contains { occupied.contains($0) }
    }

    /// Vacant, currently-legal (per the distance rule) vertices `opponentID`
    /// could plausibly reach with one more road from their existing
    /// settlements/cities/roads - a proxy for "their near-term expansion
    /// options", used to value denying opponents a spot as well as taking
    /// one for ourselves. Internal rather than private so
    /// `BuildPlannerTests` can exercise it directly.
    ///
    /// A vertex directly adjacent to one of `opponentID`'s own buildings is
    /// never itself a candidate - the distance rule makes it illegal for
    /// anyone, including its owner - but roads (unlike settlements) aren't
    /// subject to the distance rule, so `opponentID` could still road out to
    /// it and beyond. The real frontier is therefore two hops out: one road
    /// segment to that (otherwise unbuildable) adjacent vertex, then one
    /// more to a vertex that's actually vacant and legal.
    static func opponentFrontier(for opponentID: PlayerID, in state: GameState) -> Set<VertexID> {
        guard let opponent = state.players.first(where: { $0.id == opponentID }) else { return [] }

        var touched = opponent.settlements.union(opponent.cities)
        for edge in opponent.roads {
            let (a, b) = state.board.vertices(of: edge)
            touched.insert(a)
            touched.insert(b)
        }

        let oneHopOut = Set(touched.flatMap { state.board.adjacentVertices(of: $0) })
        let occupied = Set(state.players.flatMap { $0.settlements.union($0.cities) })

        var frontier = Set<VertexID>()
        for vertex in oneHopOut {
            for candidate in state.board.adjacentVertices(of: vertex) {
                guard !touched.contains(candidate), !occupied.contains(candidate) else { continue }
                let tooClose = state.board.adjacentVertices(of: candidate).contains { occupied.contains($0) }
                guard !tooClose else { continue }
                frontier.insert(candidate)
            }
        }
        return frontier
    }

    /// Bonus for `vertex` sitting in a high-threat opponent's near-term
    /// expansion frontier - taking it denies them a spot, worth close to
    /// (but less than) the production value of taking it for ourselves,
    /// scaled by how threatening that opponent is relative to the average
    /// opponent.
    private static func denialBonus(vertex: VertexID, state: GameState, player: PlayerID) -> Double {
        var bonus = 0.0
        for opponent in state.players where opponent.id != player {
            guard opponentFrontier(for: opponent.id, in: state).contains(vertex) else { continue }
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
            bonus += production * 0.4 * ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state)
        }
        return bonus
    }

    /// Bonus for `edge` touching a threatening opponent's existing
    /// road/settlement/city network - building it here denies them that
    /// extension, scaled by how threatening they are relative to the
    /// average opponent.
    private static func blocksOpponentNetwork(_ edge: EdgeID, state: GameState, player: PlayerID) -> Double {
        let (a, b) = state.board.vertices(of: edge)
        var bonus = 0.0
        for opponent in state.players where opponent.id != player {
            guard !opponent.roads.contains(edge) else { continue }
            let opponentRoadVertices = opponent.roads.flatMap { roadEdge -> [VertexID] in
                let (ra, rb) = state.board.vertices(of: roadEdge)
                return [ra, rb]
            }
            let touchesOpponentNetwork = [a, b].contains { vertex in
                opponent.settlements.contains(vertex) || opponent.cities.contains(vertex) || opponentRoadVertices.contains(vertex)
            }
            guard touchesOpponentNetwork else { continue }
            bonus += 1.0 * ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state)
        }
        return bonus
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
