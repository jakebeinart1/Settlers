import Testing
@testable import CatanEngine

@Test func fiveConnectedRoadsGrantsLongestRoad() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let path = fiveEdgeChain(on: state.board)
    for edge in path { state.players[0].roads.insert(edge) }
    #expect(LongestRoad.compute(for: state) == p0)
}

@Test func branchingNetworkScoresOnlyLongestSimplePath() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let board = state.board

    // Player 0: a genuine straight 6-edge chain - true longest simple path is 6.
    let straightStart = board.onBoardVertices.sorted().first!
    var straightVisited: Set<VertexID> = [straightStart]
    let straightChain = chainEdges(from: straightStart, length: 6, on: board, avoiding: &straightVisited)
    for edge in straightChain { state.players[0].roads.insert(edge) }

    // Player 1: a Y-shaped network with the SAME total edge count (6: three
    // 2-edge arms radiating from one degree-3 vertex) but whose true longest
    // simple path is only 4 (any two arms strung together through the
    // center - the third arm would require revisiting the center vertex). A
    // naive "sum all of the player's edges" bug would wrongly compute 6
    // here too, tying (or beating) player 0's genuine 6-length chain, so
    // this distinguishes correct branch-aware DFS from that bug.
    let center = board.onBoardVertices.sorted().first { $0.touchingTiles.count == 3 && !straightVisited.contains($0) }!
    var branchVisited: Set<VertexID> = [center]
    for neighbor in board.adjacentVertices(of: center).sorted() {
        guard !branchVisited.contains(neighbor) else { continue }
        branchVisited.insert(neighbor)
        let firstEdge = board.edgesTouching(center).sorted(by: edgeOrder).first {
            board.vertices(of: $0).0 == neighbor || board.vertices(of: $0).1 == neighbor
        }!
        state.players[1].roads.insert(firstEdge)

        if let next = board.adjacentVertices(of: neighbor).sorted().first(where: { $0 != center && !branchVisited.contains($0) }) {
            branchVisited.insert(next)
            let secondEdge = board.edgesTouching(neighbor).sorted(by: edgeOrder).first {
                board.vertices(of: $0).0 == next || board.vertices(of: $0).1 == next
            }!
            state.players[1].roads.insert(secondEdge)
        }
    }

    #expect(LongestRoad.compute(for: state) == PlayerID(index: 0))
}

@Test func opponentSettlementBreaksRoadChain() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let path = fiveEdgeChain(on: state.board)
    for edge in path { state.players[0].roads.insert(edge) }
    let midVertex = state.board.vertices(of: path[2]).0
    state.players[1].settlements.insert(midVertex)
    #expect(LongestRoad.compute(for: state) != PlayerID(index: 0))
}

@Test func tieKeepsCurrentHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let board = state.board

    // Two genuinely tied 5-edge chains in disjoint regions of the board.
    let start0 = board.onBoardVertices.sorted().first!
    var visited0: Set<VertexID> = [start0]
    let chain0 = chainEdges(from: start0, length: 5, on: board, avoiding: &visited0)
    for edge in chain0 { state.players[0].roads.insert(edge) }

    let start1 = board.onBoardVertices.sorted().last!
    var visited1: Set<VertexID> = [start1]
    let chain1 = chainEdges(from: start1, length: 5, on: board, avoiding: &visited1)
    for edge in chain1 { state.players[1].roads.insert(edge) }

    state.longestRoadPlayer = p0
    #expect(LongestRoad.compute(for: state) == p0)
}

@Test func newTieBetweenTwoOtherPlayersDisplacesCurrentHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let board = state.board

    // Current holder p0 has only a 5-edge chain.
    let start0 = board.onBoardVertices.sorted().first!
    var visited0: Set<VertexID> = [start0]
    let chain0 = chainEdges(from: start0, length: 5, on: board, avoiding: &visited0)
    for edge in chain0 { state.players[0].roads.insert(edge) }
    state.longestRoadPlayer = p0

    // p1 and p2 both build longer, disjoint 6-edge chains that tie each
    // other and exceed p0's 5 - since neither p1 nor p2 is the current
    // holder, and they're tied with each other, nobody gets the bonus.
    let start1 = board.onBoardVertices.sorted()[10]
    var visited1: Set<VertexID> = [start1]
    let chain1 = chainEdges(from: start1, length: 6, on: board, avoiding: &visited1)
    for edge in chain1 { state.players[1].roads.insert(edge) }

    let start2 = board.onBoardVertices.sorted()[30]
    var visited2: Set<VertexID> = [start2]
    let chain2 = chainEdges(from: start2, length: 6, on: board, avoiding: &visited2)
    for edge in chain2 { state.players[2].roads.insert(edge) }

    #expect(LongestRoad.compute(for: state) == nil)
}

/// Regression test: `RulesEngine.apply` used to leave `longestRoadPlayer`
/// stale after `.buildSettlement`/`.buildCity` (only `.buildRoad`
/// recomputed it), so a settlement dropped onto the middle of an opponent's
/// road chain - severing it below the 5-segment minimum - wouldn't take the
/// bonus away until *someone* happened to build a road later. It must update
/// immediately, as part of the settlement build itself.
@Test func buildingSettlementOnOpponentRoadRecomputesLongestRoadImmediately() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .mainTurn(playerIndex: 1)
    let p0 = PlayerID(index: 0)

    let path = fiveEdgeChain(on: state.board)
    for edge in path { state.players[0].roads.insert(edge) }
    state.longestRoadPlayer = LongestRoad.compute(for: state)
    #expect(state.longestRoadPlayer == p0)

    // Player 1 builds a settlement on a vertex in the middle of player 0's
    // chain, cutting it below the 5-edge minimum. `canBuildSettlement`
    // requires the vertex to touch one of the builder's own roads outside
    // setup, so give player 1 a road on whichever edge at that vertex isn't
    // already part of player 0's chain.
    let midVertex = state.board.vertices(of: path[2]).0
    let ownEdge = state.board.edgesTouching(midVertex).sorted(by: edgeOrder).first { !path.contains($0) }!
    state.players[1].roads.insert(ownEdge)
    state.players[1].resources = [.lumber: 1, .brick: 1, .grain: 1, .wool: 1]

    try RulesEngine.apply(.buildSettlement(midVertex), by: PlayerID(index: 1), to: &state)

    #expect(state.longestRoadPlayer != p0)
}

private func fiveEdgeChain(on board: Board) -> [EdgeID] {
    var visited: Set<VertexID> = [board.onBoardVertices.sorted().first!]
    return chainEdges(from: board.onBoardVertices.sorted().first!, length: 5, on: board, avoiding: &visited)
}

/// Walks `length` connected on-board edges deep from `start`, always
/// stepping to an unvisited neighbor (deterministic given `board`'s fixed
/// vertex ordering), and marks every visited vertex in `visited` so callers
/// can chain further disjoint walks off the same visited set.
private func chainEdges(from start: VertexID, length: Int, on board: Board, avoiding visited: inout Set<VertexID>) -> [EdgeID] {
    var chain: [EdgeID] = []
    var current = start
    while chain.count < length {
        let next = board.adjacentVertices(of: current).sorted().first { !visited.contains($0) }!
        chain.append(board.edgesTouching(current).sorted(by: edgeOrder).first { board.vertices(of: $0).0 == next || board.vertices(of: $0).1 == next }!)
        visited.insert(next)
        current = next
    }
    return chain
}

/// `EdgeID` isn't `Comparable`, so this provides a stable total order (by
/// endpoint vertices, which are `Comparable`) for sorting the arrays
/// `adjacentVertices`/`edgesTouching` return before picking `.first` -
/// otherwise the choice would depend on `Set<EdgeID>`'s per-process hash-seed
/// iteration order and these tests' expected chains would vary run to run.
private func edgeOrder(_ lhs: EdgeID, _ rhs: EdgeID) -> Bool {
    if lhs.a != rhs.a { return lhs.a < rhs.a }
    return lhs.b < rhs.b
}
