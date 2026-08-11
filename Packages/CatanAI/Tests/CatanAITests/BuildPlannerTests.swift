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
    // so the score should be exactly 2.5 lower (the bonus amount).
    state.longestRoadPlayer = player
    let noBonusScore = BuildPlanner.score(.buildRoad(claimingEdge), for: state, player: player, personality: .balanced)!

    #expect(claimingScore - noBonusScore == 2.5)
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
