import Testing
@testable import CatanEngine

/// A Conquest game with seat 0 and seat 1 each settled on the same 6.
private func sharedSix() -> (GameState, Tile, Resource) {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 2, variant: .conquest)
    let tile = state.board.tiles.first { $0.numberToken == 6 && $0.coordinate != state.board.robberTile }!
    let corners = HexGeometry.corners(of: tile.coordinate)
    state.players[0].settlements.insert(corners[0])
    state.players[1].settlements.insert(corners[3])
    guard case .resource(let resource) = tile.kind else { fatalError("6 is always a resource") }
    return (state, tile, resource)
}

@Test func aTribeHeldHexPaysEveryoneAsNormal() {
    var (state, tile, resource) = sharedSix()
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[0].resources[resource] == 1)
    #expect(state.players[1].resources[resource] == 1)
}

@Test func anOccupiedHexPaysOnlyTheOccupierPlusOne() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 3)
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[0].resources[resource] == 2)
    #expect((state.players[1].resources[resource] ?? 0) == 0)
}

@Test func theRobberBlocksAnOccupiedHexIncludingTheBonus() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 3)
    state.board.robberTile = tile.coordinate
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect((state.players[0].resources[resource] ?? 0) == 0)
}

@Test func occupierBonusRespectsBankShortage() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 3)
    state.bank[resource] = 1
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[0].resources[resource] == 1, "a sole claimant takes what is left")
}

@Test func anUnoccupiedHexPaysEveryoneAsNormal() {
    var (state, tile, resource) = sharedSix()
    state.garrisons[tile.coordinate] = nil
    MainPhase.rollDice(state: &state, roll: tile.numberToken!)
    #expect(state.players[1].resources[resource] == 1)
}
