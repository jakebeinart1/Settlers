import Testing
import CatanEngine
@testable import CatanAI

/// Walks `length` edges out from an arbitrary starting vertex, greedily
/// picking an unvisited neighbor each step - a real connected road chain on
/// `board`, for tests that need one without hand-writing coordinates.
private func buildChain(from board: Board, length: Int) -> [EdgeID] {
    var edges: [EdgeID] = []
    var visited = Set<VertexID>()
    var current = board.onBoardVertices.sorted().first!
    visited.insert(current)
    for _ in 0..<length {
        guard let next = board.adjacentVertices(of: current).first(where: { !visited.contains($0) }) else { break }
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

@Test func buildRoadScoreIsHigherWhenItBlocksAHighThreatOpponentsNetwork() {
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

    #expect(touchingOpponent > notTouchingOpponent)
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
