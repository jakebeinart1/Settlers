import Testing
@testable import CatanEngine

@Test func settlementProducesOneResourceOnMatchingRoll() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = resourceTile(in: state.board, notUnderRobber: true)
    let vertex = HexGeometry.corners(of: tile.coordinate).first!
    state.players[0].settlements.insert(vertex)

    MainPhase.rollDice(state: &state, roll: tile.numberToken!)

    #expect(state.players[0].resources[resource(of: tile)] == 1)
}

@Test func cityProducesTwoResourcesOnMatchingRoll() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = resourceTile(in: state.board, notUnderRobber: true)
    let vertex = HexGeometry.corners(of: tile.coordinate).first!
    state.players[0].cities.insert(vertex)

    MainPhase.rollDice(state: &state, roll: tile.numberToken!)

    #expect(state.players[0].resources[resource(of: tile)] == 2)
}

@Test func robberTileProducesNothing() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = resourceTile(in: state.board, notUnderRobber: true)
    state.board.robberTile = tile.coordinate
    let vertex = HexGeometry.corners(of: tile.coordinate).first!
    state.players[0].settlements.insert(vertex)

    MainPhase.rollDice(state: &state, roll: tile.numberToken!)

    #expect((state.players[0].resources[resource(of: tile)] ?? 0) == 0)
}

@Test func rollOfSevenProducesNoResources() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = state.board.tiles.first { $0.numberToken != nil }!
    let vertex = HexGeometry.corners(of: tile.coordinate).first!
    state.players[0].settlements.insert(vertex)

    MainPhase.rollDice(state: &state, roll: 7)

    #expect(state.players[0].resources.values.reduce(0, +) == 0)
    #expect(state.lastDiceRoll == 7)
}

@Test func soleDemandingPlayerGetsWhateverBankHasLeft() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = resourceTile(in: state.board, notUnderRobber: true)
    let vertex = HexGeometry.corners(of: tile.coordinate).first!
    state.players[0].cities.insert(vertex) // demands 2
    state.bank[resource(of: tile)] = 1 // bank only has 1 left

    MainPhase.rollDice(state: &state, roll: tile.numberToken!)

    #expect(state.players[0].resources[resource(of: tile)] == 1)
    #expect(state.bank[resource(of: tile)] == 0)
}

@Test func multipleDemandingPlayersGetNothingWhenBankCannotCoverAll() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = resourceTile(in: state.board, notUnderRobber: true)
    let vertices = HexGeometry.corners(of: tile.coordinate)
    state.players[0].settlements.insert(vertices[0])
    state.players[1].settlements.insert(vertices[2]) // non-adjacent corner, distinct player
    state.bank[resource(of: tile)] = 1 // not enough for both players' combined demand of 2

    MainPhase.rollDice(state: &state, roll: tile.numberToken!)

    #expect((state.players[0].resources[resource(of: tile)] ?? 0) == 0)
    #expect((state.players[1].resources[resource(of: tile)] ?? 0) == 0)
    #expect(state.bank[resource(of: tile)] == 1)
}

private func resource(of tile: Tile) -> Resource {
    guard case .resource(let resource) = tile.kind else { fatalError("expected a resource tile") }
    return resource
}

private func resourceTile(in board: Board, notUnderRobber: Bool) -> Tile {
    board.tiles.first {
        $0.numberToken != nil && (!notUnderRobber || $0.coordinate != board.robberTile)
    }!
}
