import CatanEngine

/// Chooses the best build-type move (road/settlement/city/dev card) available
/// on a bot's turn, if any is worth taking.
public enum BuildPlanner {
    /// The minimum score a candidate must clear to be worth taking over
    /// simply ending the turn (banking resources for something better).
    private static let worthItThreshold = 1.5

    /// How close a candidate's score has to be to the best one to be treated
    /// as a genuine toss-up rather than clearly worse. Real players don't
    /// deliberate the same way over "obviously the best move" vs. "several
    /// reasonable options" - a wide scoring gap means one move is just
    /// better and should always win, while a near-tie is the kind of close
    /// call a human might decide either way. Only ties within this margin
    /// get randomized; anything outside it is picked deterministically.
    private static let tieMargin = 0.35

    /// Scores every legal build move for `player` in `state` and returns
    /// one of the highest-scoring ones, or `nil` if nothing clears
    /// `worthItThreshold` (in which case the caller should fall back to
    /// something else, e.g. `.endTurn`). Only ever returns a move that
    /// appears in `RulesEngine.legalMoves(for: state)`.
    ///
    /// When multiple candidates land within `tieMargin` of the top score,
    /// picks among them uniformly at random via `rng` instead of always the
    /// first one `legalMoves` happens to enumerate - an unbroken run of
    /// genuinely close calls always resolving the same deterministic way
    /// (e.g. always the lowest edge ID) is exactly what reads as robotic; a
    /// move that clearly outscores the rest is never affected, since
    /// nothing else falls within the margin to compete with it.
    public static func chooseBuild(
        for state: GameState,
        player: PlayerID,
        personality: BotPersonality,
        rng: inout some RandomNumberGenerator
    ) -> GameMove? {
        let legal = RulesEngine.legalMoves(for: state)
        var scored: [(move: GameMove, score: Double)] = []

        for move in legal {
            guard let score = score(move, for: state, player: player, personality: personality) else { continue }
            scored.append((move, score))
        }

        guard let topScore = scored.map(\.score).max(), topScore >= worthItThreshold else { return nil }
        let tied = scored.filter { $0.score >= topScore - tieMargin }
        return tied.randomElement(using: &rng)?.move
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
            let reachable = newlyReachableVertices(for: edge, player: player, in: state)
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
            } else if state.longestRoadPlayer == player {
                longestRoadBonus = longestRoadDefenseBonus(edge: edge, player: player, state: state)
            } else if let playerIndex = state.players.firstIndex(where: { $0.id == player }) {
                // Not the qualifying edge itself, and not already held (in
                // which case there's nothing left to pursue) - but real
                // Longest Road pursuit is a multi-turn commitment, not a
                // single lucky edge, so reward extending our own chain once
                // we're seriously in range (3+ segments long after this
                // edge), scaling up as it approaches the 5-edge minimum, so
                // the connective roads leading up to a real claim actually
                // get built instead of only ever the one that happens to
                // complete it.
                var simulated = state
                simulated.players[playerIndex].roads.insert(edge)
                let ownLengthAfter = LongestRoad.length(for: simulated.players[playerIndex], in: simulated)
                if ownLengthAfter >= 3 {
                    longestRoadBonus = 0.3 * Double(ownLengthAfter - 2)
                }
            }
            // A road going somewhere specific reads as planned; one that
            // doesn't reads as aimless. `committedPathBonus` rewards edges
            // that measurably close the distance to a single, consistently
            // chosen expansion target rather than scattering across
            // whichever vertex looks marginally reachable this turn.
            let pathBonus = committedPathBonus(edge: edge, player: player, state: state)
            return 0.5 + personality.expansionBias + bestReachable * 0.2 + blockingBonus + longestRoadBonus + pathBonus

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
            if let me = state.players.first(where: { $0.id == player }) {
                // Diminishing returns for hoarding: only one development
                // card can be played per turn (`DevCards.canPlay`), so a
                // bot already sitting on several unplayed ones has less
                // real need for another - real-player advice is not to get
                // "caught with too many". Victory-point cards are excluded:
                // they're never played, so holding one doesn't compete for
                // next turn's one-card slot the way a knight/road-building/
                // year-of-plenty/monopoly card does.
                let unplayedPlayable = me.devCards.filter { $0 != .victoryPoint }.count
                value -= Double(unplayedPlayable) * 0.35

                if state.largestArmyPlayer != player {
                    let wouldReach = me.playedKnights + 1
                    let holderCount = state.largestArmyPlayer
                        .flatMap { holder in state.players.first(where: { $0.id == holder })?.playedKnights }
                        ?? 0
                    if wouldReach >= 3, wouldReach > holderCount {
                        value += 1.0
                    }
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

    /// The vertices `edge` newly puts one road within reach of, for
    /// `.buildRoad`'s `bestReachable` term - legal, vacant, and not already
    /// reachable via a single more road from elsewhere in `player`'s
    /// existing network (see `immediateFrontier`). Without that exclusion,
    /// a redundant/parallel road (adjacent to a vertex the player could
    /// already reach some other way) scored exactly as high as one that
    /// actually opened new territory - confirmed via a bots-only
    /// simulation: ~19% of all road builds opened no new territory, claimed
    /// no Longest Road, and blocked no opponent.
    static func newlyReachableVertices(for edge: EdgeID, player: PlayerID, in state: GameState) -> Set<VertexID> {
        let (a, b) = state.board.vertices(of: edge)
        let alreadyReachable = immediateFrontier(for: player, in: state)
        return Set([a, b].flatMap { state.board.adjacentVertices(of: $0) })
            .filter { isBuildableVertex($0, in: state) && !alreadyReachable.contains($0) }
    }

    /// Vacant, currently-legal vertices `player` could reach with exactly
    /// one more road from *anywhere* in their existing settlements/cities/
    /// roads right now - distinct from `opponentFrontier`'s two-hops-out
    /// view (built for "where might an opponent expand *next*", which
    /// treats every vertex touching an existing building as a pass-through
    /// only, since the distance rule always blocks it): this is "what could
    /// I reach with the very next road I build", used to tell whether a
    /// *candidate* road is opening up new territory or just re-reaching
    /// somewhere already one road away some other way.
    static func immediateFrontier(for player: PlayerID, in state: GameState) -> Set<VertexID> {
        guard let me = state.players.first(where: { $0.id == player }) else { return [] }
        var touched = me.settlements.union(me.cities)
        for edge in me.roads {
            let (a, b) = state.board.vertices(of: edge)
            touched.insert(a)
            touched.insert(b)
        }
        return Set(touched.flatMap { state.board.adjacentVertices(of: $0) }).filter { isBuildableVertex($0, in: state) }
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

    /// Bonus for `edge` denying a threatening opponent a vertex they could
    /// actually reach *next* (their `immediateFrontier`) - not merely
    /// sharing a vertex with wherever their network already sits, which
    /// isn't denying them anything (they already hold it, or it's still
    /// several roads away either way). Merely bordering an opponent's
    /// network on a crowded board used to score exactly the same as
    /// genuinely racing them for a contested spot - confirmed via a
    /// bots-only simulation as a real source of roads that "don't make
    /// sense" (touching some opponent road segment with nothing actually at
    /// stake there).
    private static func blocksOpponentNetwork(_ edge: EdgeID, state: GameState, player: PlayerID) -> Double {
        let (a, b) = state.board.vertices(of: edge)
        var bonus = 0.0
        for opponent in state.players where opponent.id != player {
            guard !opponent.roads.contains(edge) else { continue }
            let deniesFrontier = [a, b].contains { immediateFrontier(for: opponent.id, in: state).contains($0) }
            guard deniesFrontier else { continue }
            bonus += 1.0 * ThreatAssessment.relativeWeight(for: opponent.id, excluding: player, in: state)
        }
        return bonus
    }

    /// The single best vertex `player` could aim their road network toward
    /// right now: the highest-scoring buildable vertex within `maxHops`
    /// roads of their existing network (settlements/cities/roads), with
    /// production discounted by distance so a mediocre-but-close spot can
    /// beat a great-but-far one. Recomputed fresh from `state` every call -
    /// no memory of past turns - but deterministic, so as long as the
    /// target stays open and still the best option, successive turns keep
    /// aiming the same direction instead of flip-flopping; that consistency
    /// (not any stored plan) is what `committedPathBonus` relies on. `nil`
    /// once `player` has no network yet (setup phase) or no buildable
    /// vertex is reachable within `maxHops`.
    static func expansionTarget(for player: PlayerID, in state: GameState, maxHops: Int = 4) -> VertexID? {
        guard let me = state.players.first(where: { $0.id == player }) else { return nil }
        var networkVertices = me.settlements.union(me.cities)
        for edge in me.roads {
            let (a, b) = state.board.vertices(of: edge)
            networkVertices.insert(a)
            networkVertices.insert(b)
        }
        guard !networkVertices.isEmpty else { return nil }

        var visited = networkVertices
        var frontier = networkVertices
        var best: (vertex: VertexID, score: Double)?
        var hop = 1
        while hop <= maxHops && !frontier.isEmpty {
            let next = Set(frontier.flatMap { state.board.adjacentVertices(of: $0) }).subtracting(visited)
            for vertex in next where isBuildableVertex(vertex, in: state) {
                let discounted = PlacementHeuristics.score(vertex: vertex, board: state.board) - Double(hop) * 0.5
                if best == nil || discounted > best!.score {
                    best = (vertex, discounted)
                }
            }
            visited.formUnion(next)
            frontier = next
            hop += 1
        }
        return best?.vertex
    }

    /// Shortest hop-count from every board vertex to `target`, over the
    /// board's plain vertex-adjacency graph (ignores road ownership/
    /// legality - roads follow this same graph, so it's a fine distance
    /// proxy for "how many roads away").
    private static func vertexDistances(to target: VertexID, board: Board) -> [VertexID: Int] {
        var distances: [VertexID: Int] = [target: 0]
        var frontier: Set<VertexID> = [target]
        var hop = 0
        while !frontier.isEmpty {
            hop += 1
            let next = Set(frontier.flatMap { board.adjacentVertices(of: $0) }).subtracting(distances.keys)
            for vertex in next { distances[vertex] = hop }
            frontier = next
        }
        return distances
    }

    /// Bonus for `edge` measurably closing the distance to `player`'s
    /// current `expansionTarget` - `0` if there's no target, or if neither
    /// of `edge`'s endpoints is closer to it than the player's existing
    /// network already is (so a road built *away* from the chosen target,
    /// or one that's merely redundant with reaching it some other way,
    /// gets nothing here). Scales up as the target gets closer, since the
    /// final approach matters more than a first speculative step. Internal
    /// rather than private so `BuildPlannerTests` can compare it directly,
    /// isolated from `.buildRoad`'s other bonuses (bestReachable/blocking/
    /// longest-road), which can otherwise swamp the difference on a real
    /// board.
    static func committedPathBonus(edge: EdgeID, player: PlayerID, state: GameState) -> Double {
        guard let target = expansionTarget(for: player, in: state),
              let me = state.players.first(where: { $0.id == player })
        else { return 0 }

        let distances = vertexDistances(to: target, board: state.board)
        var networkVertices = me.settlements.union(me.cities)
        for existingEdge in me.roads {
            let (a, b) = state.board.vertices(of: existingEdge)
            networkVertices.insert(a)
            networkVertices.insert(b)
        }
        let networkDistance = networkVertices.compactMap { distances[$0] }.min() ?? Int.max

        let (a, b) = state.board.vertices(of: edge)
        let edgeDistance = min(distances[a] ?? Int.max, distances[b] ?? Int.max)
        guard edgeDistance < networkDistance else { return 0 }
        return 1.0 / Double(edgeDistance + 1)
    }

    /// Bonus for `edge` extending `player`'s road chain while they already
    /// hold Longest Road - `0` unless a rival sits within one segment of
    /// catching up. Longest Road only matters if it's still held *at game
    /// end*, so defending a lead that's genuinely under threat is real
    /// value; reinforcing a lead nobody is close to contesting is a wasted
    /// road (the resources were better spent elsewhere). Internal rather
    /// than private so `BuildPlannerTests` can compare it directly, isolated
    /// from `.buildRoad`'s other bonuses (bestReachable/blocking/path),
    /// which can otherwise swamp the difference on a real board.
    static func longestRoadDefenseBonus(edge: EdgeID, player: PlayerID, state: GameState) -> Double {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else { return 0 }
        let me = state.players[playerIndex]
        let ownLength = LongestRoad.length(for: me, in: state)
        let closestRivalLength = state.players
            .filter { $0.id != player }
            .map { LongestRoad.length(for: $0, in: state) }
            .max() ?? 0
        guard ownLength - closestRivalLength <= 1 else { return 0 }

        var simulated = state
        simulated.players[playerIndex].roads.insert(edge)
        let ownLengthAfter = LongestRoad.length(for: simulated.players[playerIndex], in: simulated)
        return ownLengthAfter > ownLength ? 1.2 : 0
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
