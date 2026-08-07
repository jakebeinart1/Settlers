import Testing
@testable import CatanEngine

@Test func roadMustConnectToOwnNetwork() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!
    let touchingEdge = state.board.edgesTouching(vertex).first!
    state.players[0].settlements.insert(vertex)

    #expect(Building.canBuildRoad(touchingEdge, for: p0, in: state))

    let farVertex = state.board.onBoardVertices.sorted().last!
    let farEdge = state.board.edgesTouching(farVertex).first { $0 != touchingEdge }!
    #expect(!Building.canBuildRoad(farEdge, for: p0, in: state))
}

@Test func roadCannotBeBuiltOnAnEdgeAnotherPlayerAlreadyOwns() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!
    let edge = state.board.edgesTouching(vertex).first!

    // p1 already owns this edge; p0 also has a settlement touching it, so
    // without the occupancy check p0's build would otherwise look legal.
    state.players[1].roads.insert(edge)
    state.players[0].settlements.insert(vertex)

    #expect(!Building.canBuildRoad(edge, for: p0, in: state))
}

@Test func settlementRespectsDistanceRuleAndRoadConnection() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .mainTurn(playerIndex: 0)
    let p0 = PlayerID(index: 0)
    let p1 = PlayerID(index: 1)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)
    let firstEdge = state.board.edgesTouching(vertex).first!
    state.players[0].roads.insert(firstEdge)
    let (a, b) = state.board.vertices(of: firstEdge)
    let midVertex = (a == vertex) ? b : a
    let secondEdge = state.board.edgesTouching(midVertex).first { $0 != firstEdge }!
    state.players[0].roads.insert(secondEdge)
    let (c, d) = state.board.vertices(of: secondEdge)
    let farVertex = (c == midVertex) ? d : c

    // Adjacent vertex violates the distance rule.
    let adjacentVertex = state.board.adjacentVertices(of: vertex).first!
    #expect(!Building.canBuildSettlement(adjacentVertex, for: p0, in: state))

    // A far vertex not touched by any of player 0's roads fails the road-connection rule.
    let unreachedVertex = state.board.onBoardVertices.sorted().last!
    #expect(!Building.canBuildSettlement(unreachedVertex, for: p0, in: state))
    #expect(!Building.canBuildSettlement(unreachedVertex, for: p1, in: state))

    // The far end of player 0's 2-road chain, unoccupied and undistanced, is legal.
    #expect(Building.canBuildSettlement(farVertex, for: p0, in: state))
    // But not for an opponent, who has no road reaching it.
    #expect(!Building.canBuildSettlement(farVertex, for: p1, in: state))
}

@Test func cityRequiresExistingOwnSettlement() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let p1 = PlayerID(index: 1)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)

    #expect(Building.canBuildCity(vertex, for: p0, in: state))
    #expect(!Building.canBuildCity(vertex, for: p1, in: state))

    let otherVertex = state.board.onBoardVertices.sorted().last!
    #expect(!Building.canBuildCity(otherVertex, for: p0, in: state))
}

@Test func buildRoadDeductsCostAndReturnsResourcesToBank() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)
    state.players[0].resources = [.brick: 1, .lumber: 1]
    state.phase = .mainTurn(playerIndex: 0)
    let bankBrickBefore = state.bank[.brick] ?? 0
    let edge = state.board.edgesTouching(vertex).first!

    try RulesEngine.apply(.buildRoad(edge), by: p0, to: &state)

    #expect(state.players[0].roads.contains(edge))
    #expect((state.players[0].resources[.brick] ?? 0) == 0)
    #expect((state.players[0].resources[.lumber] ?? 0) == 0)
    #expect(state.bank[.brick] == bankBrickBefore + 1)
}

@Test func buildRoadWithInsufficientResourcesThrows() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)
    state.players[0].resources = [:] // nothing to spend
    state.phase = .mainTurn(playerIndex: 0)
    let edge = state.board.edgesTouching(vertex).first!

    #expect(throws: MoveError.insufficientResources) {
        try RulesEngine.apply(.buildRoad(edge), by: p0, to: &state)
    }
}

@Test func buildCityUpgradesSettlementAndDeductsCost() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)
    state.players[0].resources = [.ore: 3, .grain: 2]
    state.phase = .mainTurn(playerIndex: 0)

    try RulesEngine.apply(.buildCity(vertex), by: p0, to: &state)

    #expect(!state.players[0].settlements.contains(vertex))
    #expect(state.players[0].cities.contains(vertex))
    #expect((state.players[0].resources[.ore] ?? 0) == 0)
    #expect((state.players[0].resources[.grain] ?? 0) == 0)
}
