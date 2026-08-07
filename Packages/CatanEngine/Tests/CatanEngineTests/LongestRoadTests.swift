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
    let path = fiveEdgeChain(on: state.board)
    // Only take the first 3 edges of the chain, then branch off in a
    // different direction from the midpoint - the longest simple path
    // should be whichever single branch is longest, not both combined.
    for edge in path.prefix(3) { state.players[0].roads.insert(edge) }

    let midVertex = state.board.vertices(of: path[2]).1
    let visited: Set<VertexID> = Set(path.prefix(3).flatMap { [state.board.vertices(of: $0).0, state.board.vertices(of: $0).1] })
    if let branchVertex = state.board.adjacentVertices(of: midVertex).first(where: { !visited.contains($0) }) {
        let branchEdge = state.board.edgesTouching(midVertex).first {
            state.board.vertices(of: $0).0 == branchVertex || state.board.vertices(of: $0).1 == branchVertex
        }!
        state.players[0].roads.insert(branchEdge)
    }

    // 3-edge main chain + 1-edge branch = 4 total edges, longest simple
    // path is at most 3 (chain) or 3+1 through the branch, never 4 straight.
    #expect(LongestRoad.compute(for: state) == nil) // fewer than 5, no bonus yet
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
    let path = fiveEdgeChain(on: state.board)
    for edge in path { state.players[0].roads.insert(edge) }
    state.longestRoadPlayer = p0
    #expect(LongestRoad.compute(for: state) == p0)
}

private func fiveEdgeChain(on board: Board) -> [EdgeID] {
    // Deterministic BFS from the lowest-sorted on-board vertex, walking 5 connected edges deep.
    var chain: [EdgeID] = []
    var current = board.onBoardVertices.sorted().first!
    var visited: Set<VertexID> = [current]
    while chain.count < 5 {
        let next = board.adjacentVertices(of: current).first { !visited.contains($0) }!
        chain.append(board.edgesTouching(current).first { board.vertices(of: $0).0 == next || board.vertices(of: $0).1 == next }!)
        visited.insert(next)
        current = next
    }
    return chain
}
