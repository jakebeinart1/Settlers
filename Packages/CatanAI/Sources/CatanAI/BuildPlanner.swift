import CatanEngine

/// Chooses the best build-type move (road/settlement/city/dev card) available
/// on a bot's turn, if any is worth taking.
public enum BuildPlanner {
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
        rng: inout some RandomNumberGenerator,
        weights: BotWeights = .default
    ) -> GameMove? {
        let legal = RulesEngine.legalMoves(for: state)
        // One memo for the whole scoring pass: every candidate asks the same
        // questions about the same unchanging `state` (see `PlanningContext`).
        let context = PlanningContext(state: state, player: player, weights: weights)
        var scored: [(move: GameMove, score: Double)] = []

        for move in legal {
            guard let score = score(move, for: state, player: player, personality: personality,
                                    weights: weights, context: context)
            else { continue }
            scored.append((move, score))
        }

        guard let topScore = scored.map(\.score).max(), topScore >= weights.worthItThreshold else { return nil }
        let tied = scored.filter { $0.score >= topScore - weights.tieMargin }
        return tied.randomElement(using: &rng)?.move
    }

    /// `nil` for non-build moves (trades, dev-card plays, endTurn, etc.) -
    /// this task only plans building, not those other categories. Internal
    /// rather than private so `BuildPlannerTests` can compare scores
    /// directly instead of only inferring them through `chooseBuild`'s
    /// final pick.
    ///
    /// `context` is the per-decision memo `chooseBuild` threads through every
    /// candidate; callers scoring a single move on their own (tests,
    /// `DevCardHeuristics`) leave it off and get a fresh one.
    static func score(
        _ move: GameMove,
        for state: GameState,
        player: PlayerID,
        personality: BotPersonality,
        weights: BotWeights = .default,
        context: PlanningContext? = nil
    ) -> Double? {
        let context = context ?? PlanningContext(state: state, player: player, weights: weights)
        switch move {
        case .buildSettlement(let vertex):
            // A new settlement is close to always worth it - weight
            // production heavily and scale up by expansion appetite. Also
            // adds a bonus for denying a threatening opponent's near-term
            // expansion spot, if this vertex is one.
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board, weights: weights)
            let denial = denialBonus(vertex: vertex, player: player, weights: weights, context: context)
            let appetite = weights.settlementProductionBase + personality.expansionBias
            return weights.settlementBase + production * appetite + denial

        case .buildCity(let vertex):
            // Upgrading doubles production on that vertex's tiles, so it's
            // valuable roughly in proportion to its existing production.
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board, weights: weights)
            let appetite = weights.cityProductionBase
                + personality.expansionBias * weights.cityProductionExpansionScale
            return weights.cityBase + production * appetite

        case .buildRoad(let edge):
            // Roads are cheap groundwork; value them modestly, with a bonus
            // for opening up a newly-reachable high-value settlement spot,
            // a bonus for blocking a threatening opponent's network, plus a
            // large bonus if this exact road would hand *us* the
            // longest-road bonus (2 VP) right now - larger still if it
            // would take that bonus away from a currently-threatening
            // holder, not just claim it fresh.
            let reachable = newlyReachableVertices(for: edge, player: player, in: state, context: context)
            let bestReachable = reachable
                .map { PlacementHeuristics.score(vertex: $0, board: state.board, weights: weights) }
                .max() ?? 0
            let blockingBonus = blocksOpponentNetwork(edge, player: player, weights: weights, context: context)
            var longestRoadBonus = 0.0
            if claimsLongestRoad(edge, for: player, in: state) {
                let holderWeight = state.longestRoadPlayer
                    .map { holder in
                        context.relativeWeight(for: holder)
                    }
                    ?? 1.0
                longestRoadBonus = weights.longestRoadClaimBonus
                    * (state.longestRoadPlayer == nil ? 1.0 : holderWeight)
            } else if state.longestRoadPlayer == player {
                longestRoadBonus = longestRoadDefenseBonus(edge: edge, player: player, state: state,
                                                           weights: weights, context: context)
            } else {
                longestRoadBonus = longestRoadPursuitBonus(edge: edge, player: player, state: state, weights: weights)
            }
            // A road going somewhere specific reads as planned; one that
            // doesn't reads as aimless. `committedPathBonus` rewards edges
            // that measurably close the distance to a single, consistently
            // chosen expansion target rather than scattering across
            // whichever vertex looks marginally reachable this turn.
            let pathBonus = committedPathBonus(edge: edge, player: player, state: state,
                                               weights: weights, context: context)
            return weights.roadBase + personality.expansionBias
                + bestReachable * weights.roadReachableScale
                + blockingBonus + longestRoadBonus + pathBonus

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
            var value = weights.buildDevCardBase + personality.aggressiveness * weights.buildDevCardAggressionScale
            if let me = state.players.first(where: { $0.id == player }) {
                if state.rules.isLargeBoard, shouldReserveForPermanentBuild(me, in: state) {
                    value -= weights.expandedBuildReserveDevCardPenalty
                }
                // Diminishing returns for hoarding: only one development
                // card can be played per turn (`DevCards.canPlay`), so a
                // bot already sitting on several unplayed ones has less
                // real need for another - real-player advice is not to get
                // "caught with too many". Victory-point cards are excluded:
                // they're never played, so holding one doesn't compete for
                // next turn's one-card slot the way a knight/road-building/
                // year-of-plenty/monopoly card does.
                let unplayedPlayable = me.devCards.filter { $0 != .victoryPoint }.count
                value -= Double(unplayedPlayable) * weights.devCardHoardingPenalty

                if state.largestArmyPlayer != player {
                    let wouldReach = me.playedKnights + 1
                    let holderCount = state.largestArmyPlayer
                        .flatMap { holder in state.players.first(where: { $0.id == holder })?.playedKnights }
                        ?? 0
                    if wouldReach >= weights.largestArmyKnightThreshold, wouldReach > holderCount {
                        value += weights.buildDevCardLargestArmyBonus
                    }
                }
            }
            return value

        default:
            return nil
        }
    }

    /// Whether an Expanded bot can turn a short period of saving into a city
    /// or settlement. Development cards consume three of the same resources;
    /// buying one whenever affordable otherwise prevents those hands from
    /// ever reaching the permanent build cost.
    static func shouldReserveForPermanentBuild(_ player: Player, in state: GameState) -> Bool {
        func deficit(for cost: [Resource: Int]) -> Int {
            cost.reduce(0) { total, entry in
                total + max(0, entry.value - player.resources[entry.key, default: 0])
            }
        }

        let hasCityPiece = player.cities.count < state.rules.pieceLimit(for: .city)
        if hasCityPiece, !player.settlements.isEmpty, deficit(for: Building.cityCost) <= 3 {
            return true
        }

        let hasSettlementPiece = player.settlements.count < state.rules.pieceLimit(for: .settlement)
        let hasBuildableFrontier = state.board.onBoardVertices.contains {
            Building.canBuildSettlement($0, for: player.id, in: state)
        }
        return hasSettlementPiece && hasBuildableFrontier && deficit(for: Building.settlementCost) <= 2
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
    static func newlyReachableVertices(for edge: EdgeID, player: PlayerID, in state: GameState,
                                       context: PlanningContext? = nil) -> Set<VertexID> {
        let context = context ?? PlanningContext(state: state, player: player)
        let (a, b) = state.board.vertices(of: edge)
        let alreadyReachable = context.immediateFrontier(for: player)
        return Set([a, b].flatMap { state.board.adjacentVertices(of: $0) })
            .filter { context.isBuildableVertex($0) && !alreadyReachable.contains($0) }
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
        PlanningContext(state: state, player: player).immediateFrontier(for: player)
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
        PlanningContext(state: state, player: opponentID).opponentFrontier(for: opponentID)
    }

    /// Bonus for `vertex` sitting in a high-threat opponent's near-term
    /// expansion frontier - taking it denies them a spot, worth close to
    /// (but less than) the production value of taking it for ourselves,
    /// scaled by how threatening that opponent is relative to the average
    /// opponent.
    private static func denialBonus(
        vertex: VertexID,
        player: PlayerID,
        weights: BotWeights,
        context: PlanningContext
    ) -> Double {
        let state = context.state
        var bonus = 0.0
        for opponent in state.players where opponent.id != player {
            guard context.opponentFrontier(for: opponent.id).contains(vertex) else { continue }
            let production = PlacementHeuristics.score(vertex: vertex, board: state.board, weights: weights)
            let threat = context.relativeWeight(for: opponent.id)
            bonus += production * weights.settlementDenialScale * threat
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
    private static func blocksOpponentNetwork(
        _ edge: EdgeID,
        player: PlayerID,
        weights: BotWeights,
        context: PlanningContext
    ) -> Double {
        let state = context.state
        let (a, b) = state.board.vertices(of: edge)
        var bonus = 0.0
        for opponent in state.players where opponent.id != player {
            guard !opponent.roads.contains(edge) else { continue }
            let deniesFrontier = [a, b].contains { context.immediateFrontier(for: opponent.id).contains($0) }
            guard deniesFrontier else { continue }
            bonus += weights.roadBlockingBonus * context.relativeWeight(for: opponent.id)
        }
        return bonus
    }

    /// The single best vertex `player` could aim their road network toward
    /// right now: the highest-scoring buildable vertex within `expansionTargetMaxHops`
    /// roads of their existing network (settlements/cities/roads), with
    /// production discounted by distance so a mediocre-but-close spot can
    /// beat a great-but-far one. Recomputed fresh from `state` every call -
    /// no memory of past turns - but deterministic, so as long as the
    /// target stays open and still the best option, successive turns keep
    /// aiming the same direction instead of flip-flopping; that consistency
    /// (not any stored plan) is what `committedPathBonus` relies on. `nil`
    /// once `player` has no network yet (setup phase) or no buildable
    /// vertex is reachable within `expansionTargetMaxHops`.
    static func expansionTarget(for player: PlayerID, in state: GameState,
                                weights: BotWeights = .default) -> VertexID? {
        PlanningContext(state: state, player: player, weights: weights).expansionTarget
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
    static func committedPathBonus(
        edge: EdgeID,
        player: PlayerID,
        state: GameState,
        weights: BotWeights = .default,
        context: PlanningContext? = nil
    ) -> Double {
        let context = context ?? PlanningContext(state: state, player: player, weights: weights)
        guard let target = context.expansionTarget,
              let networkVertices = context.networkVertices(for: player)
        else { return 0 }

        let distances = context.distances(to: target)
        let networkDistance = networkVertices.compactMap { distances[$0] }.min() ?? Int.max

        let (a, b) = state.board.vertices(of: edge)
        let edgeDistance = min(distances[a] ?? Int.max, distances[b] ?? Int.max)
        guard edgeDistance < networkDistance else { return 0 }
        // The `+ 1` is structural, not a weight: it keeps an edge that lands
        // exactly on the target (distance 0) from dividing by zero.
        return weights.committedPathScale / Double(edgeDistance + 1)
    }

    /// Bonus for `edge` when `player` doesn't yet hold Longest Road (the
    /// exact qualifying edge and the already-holding case are handled
    /// separately, by `claimsLongestRoad` and `longestRoadDefenseBonus`).
    /// Real pursuit is a multi-turn commitment, not a single lucky edge, so
    /// this rewards extending the chain once it's seriously in range
    /// (`longestRoadPursuitMinLength`+ segments after this edge), scaling up
    /// toward the 5-edge minimum, so the connective roads leading up to a
    /// claim actually get built instead of only ever the one that happens to
    /// complete it - plus, independent of that length gate, a flat bonus
    /// whenever `edge` bridges two of the player's own currently-disconnected
    /// road pieces into one.
    ///
    /// The bridge bonus needs to be a flat add, not folded into the length
    /// ramp above: `LongestRoad.length` already accounts for a merge
    /// correctly (a bridging edge connecting two 2-segment stubs legitimately
    /// computes length 5 and is credited by the ordinary gate/ramp, no
    /// special case needed there) - the actual gap is that a bridge edge, by
    /// definition, has *both* endpoints already inside the player's own
    /// network, so it structurally can never earn `bestReachable` (nothing
    /// newly reachable) or `committedPathBonus` (already at hop 0 either way)
    /// the way a same-position simple extension into open territory can. A
    /// merge landing below the length gate loses that scoring competition to
    /// a mundane extension every time, so bots kept extending a favored stub
    /// indefinitely rather than ever bridging - confirmed as a real,
    /// reproducible defect by a 90-game sim audit (2026-09-04): 53
    /// player-instances ended the game with enough total road segments
    /// (9-13) to clear Longest Road, split across disconnected pieces whose
    /// longest single connected chain topped out at 3-4. Internal rather
    /// than private so `BuildPlannerTests` can compare it directly, isolated
    /// from `.buildRoad`'s other bonuses, which can otherwise swamp the
    /// difference on a real board.
    static func longestRoadPursuitBonus(
        edge: EdgeID,
        player: PlayerID,
        state: GameState,
        weights: BotWeights = .default
    ) -> Double {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else { return 0 }
        var simulated = state
        simulated.players[playerIndex].roads.insert(edge)
        let ownLengthAfter = LongestRoad.length(for: simulated.players[playerIndex], in: simulated)

        var bonus = 0.0
        if ownLengthAfter >= weights.longestRoadPursuitMinLength {
            let segmentsAboveZeroPoint = ownLengthAfter - weights.longestRoadPursuitZeroLength
            bonus = weights.longestRoadPursuitScale * Double(segmentsAboveZeroPoint)
        }
        if bridgesOwnFragments(edge, player: state.players[playerIndex], in: state) {
            bonus += weights.longestRoadBridgeBonus
        }
        return bonus
    }

    /// Bonus for `edge` extending `player`'s road chain while they already
    /// hold Longest Road - `0` unless a rival sits within one segment of
    /// catching up, *or* `edge` bridges two of the player's own currently
    /// disconnected road pieces into one longer, more defensible chain.
    /// Longest Road only matters if it's still held *at game end*, so
    /// defending a lead that's genuinely under threat is real value;
    /// reinforcing a lead nobody is close to contesting is a wasted road
    /// (the resources were better spent elsewhere) - UNLESS that road also
    /// consolidates a fragmented network, which has defensive value a raw
    /// lead-margin comparison doesn't see: a single opponent settlement can
    /// cut a stub off entirely, while a merged chain has no such single
    /// point of failure. Confirmed as a real, reachable gap (not a
    /// `LongestRoad` bug - it correctly computes the merged length) via a
    /// real played game (2026-09-04, bot "Ragnar"): a comfortable lead made
    /// this return `0` for every road, so a bridging edge one board-edge
    /// away from an existing stub was never scored any differently from a
    /// pointless filler road and never got built. Internal rather than
    /// private so `BuildPlannerTests` can compare it directly, isolated from
    /// `.buildRoad`'s other bonuses (bestReachable/blocking/path), which can
    /// otherwise swamp the difference on a real board.
    static func longestRoadDefenseBonus(
        edge: EdgeID,
        player: PlayerID,
        state: GameState,
        weights: BotWeights = .default,
        context: PlanningContext? = nil
    ) -> Double {
        let context = context ?? PlanningContext(state: state, player: player, weights: weights)
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else { return 0 }
        let me = state.players[playerIndex]
        let ownLength = context.longestRoadLength(for: player)

        var simulated = state
        simulated.players[playerIndex].roads.insert(edge)
        let ownLengthAfter = LongestRoad.length(for: simulated.players[playerIndex], in: simulated)
        guard ownLengthAfter > ownLength else { return 0 }

        let closestRivalLength = state.players
            .filter { $0.id != player }
            .map { context.longestRoadLength(for: $0.id) }
            .max() ?? 0
        let leadIsContested = ownLength - closestRivalLength <= weights.longestRoadDefenseLeadGap
        if leadIsContested { return weights.longestRoadDefenseBonus }
        return bridgesOwnFragments(edge, player: me, in: state) ? weights.longestRoadBridgeBonus : 0
    }

    /// Whether `edge`'s two endpoints currently sit in two different
    /// connected pieces of `player`'s own road network (including bare
    /// settlements/cities with no road yet) - i.e. building it would merge
    /// two pieces that today can only be reached from each other by roads
    /// `player` doesn't own, rather than merely extending one piece that was
    /// already connected. Used by `longestRoadDefenseBonus` to recognize a
    /// consolidating road even when the current lead looks too comfortable
    /// to bother defending by the raw length-margin alone.
    static func bridgesOwnFragments(_ edge: EdgeID, player: Player, in state: GameState) -> Bool {
        var parent: [VertexID: VertexID] = [:]
        func find(_ vertex: VertexID) -> VertexID {
            var v = vertex
            while let p = parent[v], p != v { v = p }
            return v
        }
        func union(_ a: VertexID, _ b: VertexID) {
            let (ra, rb) = (find(a), find(b))
            guard ra != rb else { return }
            parent[ra] = rb
        }

        for vertex in player.settlements.union(player.cities) { parent[vertex] = vertex }
        for existingEdge in player.roads {
            let (a, b) = state.board.vertices(of: existingEdge)
            // `dict[key, default:] = value` is NOT a conditional insert - it's
            // a plain overwrite that happens to read `default` as its old
            // value first, so using it here would silently reset a vertex's
            // root on every edge that re-touches it, splitting an already-
            // connected chain into false "fragments". Insert only if absent.
            if parent[a] == nil { parent[a] = a }
            if parent[b] == nil { parent[b] = b }
            union(a, b)
        }

        let (a, b) = state.board.vertices(of: edge)
        guard let rootA = parent[a].map(find), let rootB = parent[b].map(find) else {
            // Neither endpoint touches any existing piece of the network yet
            // - not a bridge between two pieces, just an unconnected edge
            // (and not a legal road to begin with, but this helper doesn't
            // need to re-derive legality).
            return false
        }
        return rootA != rootB
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
