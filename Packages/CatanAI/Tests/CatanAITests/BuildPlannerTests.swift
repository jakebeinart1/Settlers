import Testing
import CatanEngine
@testable import CatanAI

/// Walks `length` edges out from an arbitrary starting vertex, greedily
/// picking an unvisited neighbor each step - a real connected road chain on
/// `board`, for tests that need one without hand-writing coordinates.
/// Neighbor order is sorted rather than `board.adjacentVertices`' raw order
/// (backed by a `Set`, so its iteration order isn't stable across process
/// runs) - without this, which neighbor the walk tries first varies run to
/// run, occasionally wandering into a shorter dead-end branch instead of a
/// path that reaches `length` (see the flaky `ThreatAssessmentTests`
/// failure this was pulled out to fix). Sorting makes the walk - and
/// therefore whether it reaches `length` at all - the same every run.
private func buildChain(from board: Board, length: Int) -> [EdgeID] {
    var edges: [EdgeID] = []
    var visited = Set<VertexID>()
    var current = board.onBoardVertices.sorted().first!
    visited.insert(current)
    for _ in 0..<length {
        guard let next = board.adjacentVertices(of: current).sorted().first(where: { !visited.contains($0) }) else { break }
        // Exactly one edge connects `current` and `next` in a valid board
        // graph, so which order `edgesTouching` enumerates in doesn't
        // affect which edge this finds - only the neighbor pick above
        // (which determines the walked *path*) needed sorting.
        guard let edge = board.edgesTouching(current).first(where: { edge in
            let (a, b) = board.vertices(of: edge)
            return a == next || b == next
        }) else { break }
        edges.append(edge)
        visited.insert(next)
        current = next
    }
    return edges
}

@Test func claimsLongestRoadWhenAnEdgeWouldReachFiveAndNobodyElseHoldsIt() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let chain = buildChain(from: state.board, length: 5)
    #expect(chain.count == 5, "test board too small to build a 5-edge chain")
    state.players[0].roads = Set(chain.prefix(4))
    let candidateEdge = chain[4]

    // Only 4 edges so far - nobody holds the bonus yet.
    #expect(LongestRoad.compute(for: state) == nil)
    #expect(BuildPlanner.claimsLongestRoad(candidateEdge, for: player, in: state))
}

@Test func claimsLongestRoadIsFalseWhenAlreadyTheHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let chain = buildChain(from: state.board, length: 5)
    state.players[0].roads = Set(chain.prefix(4))
    state.longestRoadPlayer = player // already holds it (however that came to be)

    #expect(!BuildPlanner.claimsLongestRoad(chain[4], for: player, in: state))
}

@Test func buildRoadScoreIncludesLongestRoadBonusOnlyWhenItWouldBeClaimed() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let chain = buildChain(from: state.board, length: 5)
    state.players[0].roads = Set(chain.prefix(4))
    let claimingEdge = chain[4]

    let claimingScore = BuildPlanner.score(.buildRoad(claimingEdge), for: state, player: player, personality: .balanced)!

    // Same edge, but player already holds longest road - no bonus applies,
    // so the score should be ~2.5 lower (the bonus amount). Compared with a
    // tolerance rather than `==` - under parallel test execution this
    // Double subtraction can land a fraction of a ULP off exact equality.
    state.longestRoadPlayer = player
    let noBonusScore = BuildPlanner.score(.buildRoad(claimingEdge), for: state, player: player, personality: .balanced)!

    #expect(abs((claimingScore - noBonusScore) - 2.5) < 0.0001)
}

@Test func buyDevCardScoreIsBoostedTwoKnightsFromLargestArmy() {
    let state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let baseline = BuildPlanner.score(.buyDevCard, for: state, player: player, personality: .balanced)!

    var closeToArmy = state
    closeToArmy.players[0].playedKnights = 2
    let boosted = BuildPlanner.score(.buyDevCard, for: closeToArmy, player: player, personality: .balanced)!

    #expect(boosted - baseline == 1.0)
}

/// Reaching 3 knights wouldn't actually take largest army from a holder
/// who's already well past it - the boost shouldn't apply, since one more
/// dev card can't plausibly get us there this turn either way.
@Test func buyDevCardScoreIsNotBoostedWhenTheHolderIsFarAhead() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)

    state.players[0].playedKnights = 2
    state.players[1].playedKnights = 5
    state.largestArmyPlayer = holder

    let baseline = BuildPlanner.score(.buyDevCard, for: state, player: player, personality: .balanced)!
    var noBonus = state
    noBonus.players[0].playedKnights = 0
    let unboosted = BuildPlanner.score(.buyDevCard, for: noBonus, player: player, personality: .balanced)!

    #expect(baseline == unboosted)
}

@Test func opponentFrontierIncludesVacantVertexTwoHopsFromTheirSettlementButNotOneHop() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let opponent = PlayerID(index: 1)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex)

    let frontier = BuildPlanner.opponentFrontier(for: opponent, in: state)
    let oneHop = state.board.adjacentVertices(of: vertex)

    // A vertex directly adjacent to the settlement is illegal for anyone
    // (distance rule) - it must never appear in the frontier.
    for adjacent in oneHop {
        #expect(!frontier.contains(adjacent))
    }

    // But `opponent` can still road *through* that illegal vertex to reach
    // a genuinely buildable one two hops out.
    let twoHopCandidates = oneHop.flatMap { state.board.adjacentVertices(of: $0) }.filter { $0 != vertex && !oneHop.contains($0) }
    #expect(!twoHopCandidates.isEmpty, "test board too small for a 2-hop chain")
    #expect(twoHopCandidates.contains { frontier.contains($0) })
}

@Test func opponentFrontierExcludesVerticesTooCloseToAnyExistingBuilding() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let opponent = PlayerID(index: 1)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex)

    let oneHop = state.board.adjacentVertices(of: vertex)
    guard let hop1 = oneHop.first,
          let frontierVertex = state.board.adjacentVertices(of: hop1).first(where: { $0 != vertex && !oneHop.contains($0) })
    else {
        Issue.record("test board too small for a 2-hop chain")
        return
    }
    // Without interference, `frontierVertex` is a legal 2-hop candidate.
    #expect(BuildPlanner.opponentFrontier(for: opponent, in: state).contains(frontierVertex))

    // A third player's settlement adjacent to `frontierVertex` makes it
    // illegal for anyone (distance rule) - it must drop out.
    guard let blockingVertex = state.board.adjacentVertices(of: frontierVertex).first(where: { $0 != hop1 }) else {
        Issue.record("test board too small for a blocking vertex")
        return
    }
    state.players[2].settlements.insert(blockingVertex)

    let frontier = BuildPlanner.opponentFrontier(for: opponent, in: state)
    #expect(!frontier.contains(frontierVertex))
}

@Test func buildSettlementScoreIsHigherWhenItDeniesAHighThreatOpponentsFrontier() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let opponentVertex = state.board.onBoardVertices.sorted().first!
    let oneHop = state.board.adjacentVertices(of: opponentVertex)
    guard let candidate = oneHop.flatMap({ state.board.adjacentVertices(of: $0) }).first(where: { $0 != opponentVertex && !oneHop.contains($0) }) else {
        Issue.record("test board too small for a 2-hop chain")
        return
    }

    state.players[1].settlements.insert(opponentVertex)
    let withOpponentNearby = BuildPlanner.score(.buildSettlement(candidate), for: state, player: player, personality: .balanced)!

    var noOpponent = state
    noOpponent.players[1].settlements.removeAll()
    let withoutOpponentNearby = BuildPlanner.score(.buildSettlement(candidate), for: noOpponent, player: player, personality: .balanced)!

    #expect(withOpponentNearby > withoutOpponentNearby)
}

/// A road's "leads to a good future settlement spot" bonus should only
/// count vertices that could actually ever become a settlement - not ones
/// already occupied. Regression test for bots stacking up roads that lead
/// nowhere (player feedback: "sporadic road building with no plan to build
/// settlements") - `bestReachable` previously scored a reachable vertex by
/// raw production alone, so a road pointing at an opponent's already-built
/// settlement on a great tile scored just as high as one pointing at a
/// genuinely open spot with the same production, even though the former can
/// never be settled.
@Test func buildRoadScoreExcludesReachableVertexThatIsAlreadyOccupied() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let hub = state.board.onBoardVertices.sorted().first!
    let hubNeighbors = state.board.adjacentVertices(of: hub).sorted()
    guard hubNeighbors.count >= 2 else {
        Issue.record("test board too small")
        return
    }
    // `edge` connects hub to one neighbor; the *other* neighbors of hub are
    // reachable from `edge` (via hub) without being one of `edge`'s own two
    // vertices - isolates this from the blocking-bonus path, which only
    // looks at `edge`'s own endpoints.
    let otherEnd = hubNeighbors[0]
    guard let edge = state.board.edgesTouching(hub).first(where: { e in
        let (a, b) = state.board.vertices(of: e)
        return (a == hub && b == otherEnd) || (a == otherEnd && b == hub)
    }) else {
        Issue.record("test board too small")
        return
    }

    // Occupy whichever reachable vertex (other than `edge`'s own endpoints)
    // currently has the *highest* production - the one `bestReachable`
    // actually picks - so removing it is guaranteed to change the result
    // rather than risk landing on an already-second-best vertex.
    let reachable = [hub, otherEnd].flatMap { state.board.adjacentVertices(of: $0) }.filter { $0 != hub && $0 != otherEnd }
    guard let argmax = reachable.max(by: {
        PlacementHeuristics.score(vertex: $0, board: state.board) < PlacementHeuristics.score(vertex: $1, board: state.board)
    }) else {
        Issue.record("test board too small")
        return
    }

    let vacantScore = BuildPlanner.score(.buildRoad(edge), for: state, player: player, personality: .balanced)!

    state.players[1].settlements.insert(argmax)
    let occupiedScore = BuildPlanner.score(.buildRoad(edge), for: state, player: player, personality: .balanced)!

    #expect(occupiedScore < vacantScore)
}

/// Regression test for bot feedback: bots were building roads that lead
/// nowhere new - `bestReachable` credited a vertex just for being adjacent
/// to the candidate edge, even when that same vertex was already reachable
/// via a single more road from somewhere else in the player's *existing*
/// network. A bots-only simulation confirmed this: ~19% of all road builds
/// opened no new territory, claimed no Longest Road, and blocked no
/// opponent - purely redundant/parallel paths that happened to end near a
/// good vertex.
@Test func newlyReachableVerticesExcludesOneAlreadyReachableViaExistingNetwork() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    guard let target = state.board.onBoardVertices.first(where: { state.board.adjacentVertices(of: $0).count >= 2 }) else {
        Issue.record("test board too small")
        return
    }
    let neighbors = state.board.adjacentVertices(of: target).sorted()
    guard neighbors.count >= 2 else {
        Issue.record("test board too small")
        return
    }
    let q = neighbors[0]
    let m = neighbors[1]

    // A brand-new, unrelated candidate edge touching `m` (a neighbor of
    // `target`) - reaches `target` because it's geometrically adjacent to
    // `m`, regardless of whether the player's network is anywhere near it.
    guard let candidateEdge = state.board.edgesTouching(m).first(where: { e in
        let (x, y) = state.board.vertices(of: e)
        return x != target && y != target
    }) else {
        Issue.record("test board too small")
        return
    }

    // With no network at all, `target` is genuinely new territory.
    #expect(BuildPlanner.newlyReachableVertices(for: candidateEdge, player: player, in: state).contains(target))

    // Player's existing network reaches `q` (a *different* neighbor of
    // `target`) via an edge that doesn't itself touch `target` - `target`
    // is therefore already one more road away from the player's current
    // network, before `candidateEdge` is even considered.
    guard let roadToQ = state.board.edgesTouching(q).first(where: { e in
        let (x, y) = state.board.vertices(of: e)
        return x != target && y != target
    }) else {
        Issue.record("test board too small")
        return
    }
    state.players[0].roads = [roadToQ]

    #expect(!BuildPlanner.newlyReachableVertices(for: candidateEdge, player: player, in: state).contains(target))
}

/// The blocking bonus should key off denying the opponent a vertex they
/// could actually reach *next* (their `immediateFrontier`) - not merely
/// sharing a vertex with wherever their network already sits. A bots-only
/// simulation found that touching any of an opponent's existing road
/// endpoints (regardless of whether it denied them anything real) was
/// enough to justify a road, which is exactly the "roads that don't make
/// sense" pattern reported: two networks can innocently border each other
/// on a crowded board with nothing actually being contested there.
@Test func buildRoadScoreIsHigherWhenItDeniesAHighThreatOpponentsImmediateFrontier() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let opponentVertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(opponentVertex)
    // A settlement alone has no `immediateFrontier` (every vertex touching
    // it is distance-rule-illegal) - a road extending outward is needed so
    // there's a real, legal "next" vertex to deny.
    guard let roadOut = state.board.edgesTouching(opponentVertex).first else {
        Issue.record("test board too small")
        return
    }
    state.players[1].roads = [roadOut]

    let frontier = BuildPlanner.immediateFrontier(for: PlayerID(index: 1), in: state)
    guard let frontierVertex = frontier.sorted().first,
          let candidateEdge = state.board.edgesTouching(frontierVertex).first(where: { e in
              let (x, y) = state.board.vertices(of: e)
              return x != opponentVertex && y != opponentVertex
          })
    else {
        Issue.record("test board too small")
        return
    }

    let deniesFrontier = BuildPlanner.score(.buildRoad(candidateEdge), for: state, player: player, personality: .balanced)!

    var noOpponent = state
    noOpponent.players[1].settlements.removeAll()
    noOpponent.players[1].roads.removeAll()
    let noOpponentNearby = BuildPlanner.score(.buildRoad(candidateEdge), for: noOpponent, player: player, personality: .balanced)!

    #expect(deniesFrontier > noOpponentNearby)
}

/// The mirror case: an edge that merely touches an opponent's *existing*
/// settlement vertex directly (nothing left to deny there - they already
/// hold it) shouldn't score any differently than if that opponent didn't
/// exist at all.
@Test func buildRoadScoreIsUnaffectedByMerelyTouchingAnOpponentsOwnVertex() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let opponentVertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(opponentVertex)

    guard let candidateEdge = state.board.edgesTouching(opponentVertex).first else {
        Issue.record("test board too small")
        return
    }

    let touchingOpponent = BuildPlanner.score(.buildRoad(candidateEdge), for: state, player: player, personality: .balanced)!

    var noOpponent = state
    noOpponent.players[1].settlements.removeAll()
    let notTouchingOpponent = BuildPlanner.score(.buildRoad(candidateEdge), for: noOpponent, player: player, personality: .balanced)!

    #expect(touchingOpponent == notTouchingOpponent)
}

/// Real-player advice: don't buy development cards forever, since only one
/// can be played per turn - a bot already holding several unplayed ones
/// should value another less than a bot holding none.
@Test func buyDevCardScoreDecreasesWithEachUnplayedCardAlreadyHeld() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let noneHeld = BuildPlanner.score(.buyDevCard, for: state, player: player, personality: .balanced)!

    state.players[0].devCards = [.roadBuilding, .monopoly]
    let twoHeld = BuildPlanner.score(.buyDevCard, for: state, player: player, personality: .balanced)!

    #expect(twoHeld < noneHeld)
}

/// Victory-point cards are never played, so sitting on one shouldn't make
/// buying another card look any less appealing - only cards that compete
/// for next turn's one-play slot should count against it.
@Test func buyDevCardScoreIgnoresHeldVictoryPointCards() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let noneHeld = BuildPlanner.score(.buyDevCard, for: state, player: player, personality: .balanced)!

    state.players[0].devCards = [.victoryPoint, .victoryPoint]
    let vpHeld = BuildPlanner.score(.buyDevCard, for: state, player: player, personality: .balanced)!

    #expect(vpHeld == noneHeld)
}

/// Regression test for bot feedback: roads read as "sporadic ... not
/// directed toward anything ... building in circles". A road that measurably
/// closes the distance to the player's own `expansionTarget` should outscore
/// an otherwise-identical road that doesn't - the mechanism that keeps a
/// bot's road-building aimed at one place across turns instead of
/// flip-flopping to whatever's marginally reachable each turn.
@Test func buildRoadScoreIsHigherWhenItClosesDistanceToTheExpansionTarget() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    // Try each on-board vertex as the hub until one has both a target and
    // two of its own edges sitting at genuinely different distances from
    // it - the standard board's real geometry (which vertex ends up a
    // 2-way corner vs. a 3-way junction) isn't worth hard-coding here.
    for hub in state.board.onBoardVertices.sorted() {
        var candidate = state
        candidate.players[0].settlements = [hub]

        guard let target = BuildPlanner.expansionTarget(for: player, in: candidate), target != hub else { continue }

        // Simple BFS distance-to-target over the board's vertex graph,
        // mirroring `BuildPlanner`'s own (private) `vertexDistances`.
        var distances: [VertexID: Int] = [target: 0]
        var frontier: Set<VertexID> = [target]
        var hop = 0
        while !frontier.isEmpty {
            hop += 1
            let next = Set(frontier.flatMap { candidate.board.adjacentVertices(of: $0) }).subtracting(distances.keys)
            for vertex in next { distances[vertex] = hop }
            frontier = next
        }
        func farVertexDistance(_ edge: EdgeID) -> Int {
            let (a, b) = candidate.board.vertices(of: edge)
            return distances[a == hub ? b : a] ?? Int.max
        }
        let rankedEdges = candidate.board.edgesTouching(hub).sorted { farVertexDistance($0) < farVertexDistance($1) }
        guard let towardTarget = rankedEdges.first, let awayFromTarget = rankedEdges.last,
              farVertexDistance(towardTarget) < farVertexDistance(awayFromTarget)
        else { continue }

        let towardBonus = BuildPlanner.committedPathBonus(edge: towardTarget, player: player, state: candidate)
        let awayBonus = BuildPlanner.committedPathBonus(edge: awayFromTarget, player: player, state: candidate)

        #expect(towardBonus > awayBonus)
        return
    }
    Issue.record("no vertex on the test board yielded a usable toward/away edge pair")
}

/// `chooseBuild` should pick deterministically when one move clearly
/// outscores the rest - no amount of re-rolling the RNG should ever surface
/// a dominated candidate.
@Test func chooseBuildIsDeterministicWhenOneMoveClearlyDominates() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .mainTurn(playerIndex: 0)
    let player = PlayerID(index: 0)
    // Player has no road network yet, so no settlement/city/road is legal
    // (both require connecting to an existing road) - buying a dev card is
    // the only affordable, legal build move, so there's no real tie to
    // break regardless of which candidates the RNG might otherwise favor.
    state.players[0].resources = [.ore: 1, .wool: 1, .grain: 1]

    var seenMoves = Set<String>()
    for seed: UInt64 in 0..<20 {
        var rng = SeededRNG(seed: seed)
        guard let move = BuildPlanner.chooseBuild(for: state, player: player, personality: .balanced, rng: &rng) else {
            Issue.record("expected a build move")
            continue
        }
        seenMoves.insert("\(move)")
    }
    #expect(seenMoves.count == 1)
}

/// A private, seedable RNG for deterministic test runs - `SystemRandomNumberGenerator`
/// can't be seeded, so `chooseBuild`'s `rng:` parameter needs a substitute
/// here to get reproducible picks.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Regression test for bot feedback: "every road built to protect that 2+
/// status that no one challenges is a waste." Already holding Longest Road
/// with a comfortable lead (nobody within striking distance), extending the
/// chain further shouldn't get a defensive bonus - nothing is actually being
/// defended.
@Test func longestRoadDefenseBonusIsAbsentWhenLeadIsUncontested() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let chain = buildChain(from: state.board, length: 6)
    #expect(chain.count == 6, "test board too small to build a 6-edge chain")
    state.players[0].roads = Set(chain.prefix(5)) // length 5, already qualifies
    state.longestRoadPlayer = player
    // No opponent has any roads at all - the lead is completely uncontested.

    let extendingEdge = chain[5]
    let bonus = BuildPlanner.longestRoadDefenseBonus(edge: extendingEdge, player: player, state: state)
    #expect(bonus == 0)
}

/// The mirror case: a rival's own chain has caught up to within one segment
/// of ours - extending our lead here is genuinely defending the bonus, and
/// should score higher than the uncontested case above.
@Test func longestRoadDefenseBonusAppliesWhenARivalIsCloseBehind() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let chain = buildChain(from: state.board, length: 6)
    #expect(chain.count == 6, "test board too small to build a 6-edge chain")
    state.players[0].roads = Set(chain.prefix(5)) // length 5
    state.longestRoadPlayer = player

    let extendingEdge = chain[5]
    let uncontestedBonus = BuildPlanner.longestRoadDefenseBonus(edge: extendingEdge, player: player, state: state)
    #expect(uncontestedBonus == 0)

    // Give the rival a same-board chain of length 4 - one behind, real
    // pressure to stay ahead.
    let rivalChain = buildChain(from: state.board, length: 4)
    state.players[1].roads = Set(rivalChain)

    let contestedBonus = BuildPlanner.longestRoadDefenseBonus(edge: extendingEdge, player: player, state: state)

    #expect(contestedBonus > uncontestedBonus)
}

/// Direct unit coverage of `bridgesOwnFragments`, isolated from the scoring
/// weights above it. Builds a genuine two-fragment network: fragment A is a
/// road chain reaching vertex `tail`, fragment B is a lone settlement at `w`
/// with no road of its own yet - exactly the real-game shape (a settlement
/// one road-hop from the main network, never connected) that motivated this
/// helper. `edgesTouching(tail)` on a real board always has at least one
/// edge besides the chain's own last edge (interior vertices are degree 3),
/// so `w` is reachable without hand-picked coordinates.
@Test func bridgesOwnFragmentsDetectsAGenuineBridgeBetweenTwoDisconnectedPieces() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let chain = buildChain(from: state.board, length: 3)
    #expect(chain.count == 3, "test board too small to build a 3-edge chain")
    state.players[0].roads = Set(chain)

    let tail = state.board.vertices(of: chain[2]).1
    guard let bridgeEdge = state.board.edgesTouching(tail).first(where: { $0 != chain[2] }) else {
        Issue.record("expected the chain's tail vertex to have a second edge")
        return
    }
    let (a, b) = state.board.vertices(of: bridgeEdge)
    let w = a == tail ? b : a
    state.players[0].settlements = [w] // fragment B: a lone settlement, no road yet

    #expect(BuildPlanner.bridgesOwnFragments(bridgeEdge, player: state.players[0], in: state))

    // Control: an edge fully inside fragment A already (both endpoints share
    // a root) is never a bridge.
    #expect(!BuildPlanner.bridgesOwnFragments(chain[1], player: state.players[0], in: state))
}

/// Regression test for the real-game gap (2026-09-04, bot "Ragnar"): a
/// comfortable, uncontested Longest Road lead used to zero out
/// `longestRoadDefenseBonus` for every road, including one that would merge
/// a stray settlement into the main network. That merge now scores above
/// zero even with no rival close behind; a plain filler road into open
/// territory (not touching any separate piece of the network) still doesn't.
@Test func longestRoadDefenseBonusRewardsBridgingEvenWithAnUncontestedLead() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let chain = buildChain(from: state.board, length: 5)
    #expect(chain.count == 5, "test board too small to build a 5-edge chain")
    state.players[0].roads = Set(chain)
    state.longestRoadPlayer = player
    // No opponent has any roads at all - the lead is completely uncontested.

    // Any vertex fragment A's roads touch will do for either edge, and the
    // two don't need to share a vertex - collect every (vertex, spare edge)
    // pair along the whole chain rather than assuming any single vertex
    // (e.g. the tail) has two spares of its own; a walk can end at a
    // low-degree/edge-of-board vertex with only one.
    let chainVertices = Set(chain.flatMap { [state.board.vertices(of: $0).0, state.board.vertices(of: $0).1] })
    var spares: [(vertex: VertexID, edge: EdgeID)] = []
    for vertex in chainVertices.sorted() {
        for spareEdge in state.board.edgesTouching(vertex).filter({ !chain.contains($0) }) {
            spares.append((vertex, spareEdge))
        }
    }
    guard spares.count >= 2 else {
        Issue.record("expected the chain to have two spare edges somewhere along it")
        return
    }
    let (hub, bridgeEdge) = spares[0]
    let fillerEdge = spares[1].edge
    let (a, b) = state.board.vertices(of: bridgeEdge)
    let w = a == hub ? b : a
    state.players[0].settlements = [w] // a lone, disconnected settlement

    let bridgeBonus = BuildPlanner.longestRoadDefenseBonus(edge: bridgeEdge, player: player, state: state)
    let fillerBonus = BuildPlanner.longestRoadDefenseBonus(edge: fillerEdge, player: player, state: state)

    #expect(bridgeBonus > 0)
    #expect(fillerBonus == 0)
}

/// Regression test for the confirmed fragmentation defect (2026-09-04
/// sim audit: 53 player-instances ended a game with enough total road
/// segments to clear Longest Road but split across disconnected pieces).
/// A bridge whose resulting length falls *below* `longestRoadPursuitMinLength`
/// (a lone settlement merged with a single-edge stub reaches only length 2,
/// under the default gate of 3) used to get zero pursuit credit at all - the
/// gated ramp only ever looked at the resulting length, never at whether the
/// edge merged two separate pieces. It should score above zero now, and
/// strictly above a same-position filler edge that doesn't touch the
/// settlement's separate piece.
@Test func longestRoadPursuitBonusCreditsABridgeEvenBelowThePursuitGate() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let chain = buildChain(from: state.board, length: 1)
    #expect(chain.count == 1, "test board too small to build a 1-edge chain")
    state.players[0].roads = Set(chain)

    // Collect every (vertex, spare edge) pair from either endpoint - the two
    // returned edges don't need to share a vertex, only to both extend the
    // 1-edge chain somehow; a single endpoint isn't guaranteed to have two
    // spares of its own (a walk can end at a low-degree/edge-of-board vertex).
    let (v0, v1) = state.board.vertices(of: chain[0])
    var spares: [(vertex: VertexID, edge: EdgeID)] = []
    for vertex in [v0, v1] {
        for spareEdge in state.board.edgesTouching(vertex) where spareEdge != chain[0] {
            spares.append((vertex, spareEdge))
        }
    }
    guard spares.count >= 2 else {
        Issue.record("expected the 1-edge chain's endpoints to have two spare edges between them")
        return
    }
    let (hub, bridgeEdge) = spares[0]
    let fillerEdge = spares[1].edge
    let (a, b) = state.board.vertices(of: bridgeEdge)
    let w = a == hub ? b : a
    state.players[0].settlements = [w] // a lone, disconnected settlement

    // The bridge reaches length 2 (settlement -> bridge -> chain's far end) -
    // below the default gate of 3, so only the merge-specific credit applies.
    var simulated = state
    simulated.players[0].roads.insert(bridgeEdge)
    #expect(LongestRoad.length(for: simulated.players[0], in: simulated) == 2)

    let bridgeBonus = BuildPlanner.longestRoadPursuitBonus(edge: bridgeEdge, player: player, state: state)
    let fillerBonus = BuildPlanner.longestRoadPursuitBonus(edge: fillerEdge, player: player, state: state)

    #expect(bridgeBonus > 0)
    #expect(fillerBonus == 0)
}

@Test func longestRoadClaimBonusIsLargerWhenTakingItFromAHighThreatHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)

    let chain = buildChain(from: state.board, length: 5)
    #expect(chain.count == 5, "test board too small to build a 5-edge chain")
    state.players[0].roads = Set(chain.prefix(4))
    let candidateEdge = chain[4]

    // Nobody holds it yet - baseline claim bonus.
    let baselineScore = BuildPlanner.score(.buildRoad(candidateEdge), for: state, player: player, personality: .balanced)!

    // Now a highly-developed opponent holds it instead - taking it should
    // score higher than the baseline claim.
    var withThreatHolder = state
    withThreatHolder.longestRoadPlayer = holder
    withThreatHolder.players[1].devCards = [.knight, .knight, .knight, .knight, .knight]
    let holderScore = BuildPlanner.score(.buildRoad(candidateEdge), for: withThreatHolder, player: player, personality: .balanced)!

    #expect(holderScore > baselineScore)
}
