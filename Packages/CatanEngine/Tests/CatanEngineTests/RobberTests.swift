import Testing
@testable import CatanEngine

@Test func rollingSevenWithOverEightCardsRequiresDiscard() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[1].resources = [.brick: 5, .lumber: 4] // 9 cards
    MainPhase.rollDice(state: &state, roll: 7)
    #expect(Robber.playersWhoMustDiscard(state).contains(PlayerID(index: 1)))
    if case .discarding(let pending) = state.phase {
        #expect(pending.contains(PlayerID(index: 1)))
    } else {
        Issue.record("expected .discarding phase")
    }
}

@Test func discardingHalfRoundedDownResolvesPhase() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[1].resources = [.brick: 9] // 9 cards -> discard 4
    state.phase = .discarding(pending: [PlayerID(index: 1)])
    try! RulesEngine.apply(.discard([.brick: 4]), by: PlayerID(index: 1), to: &state)
    #expect(state.players[1].resources[.brick] == 5)
    if case .movingRobber = state.phase {} else { Issue.record("expected movingRobber next") }
}

@Test func movingRobberCanStealFromAdjacentPlayer() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let targetTile = state.board.tiles.first { $0.coordinate != state.board.robberTile }!.coordinate
    let victimVertex = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(targetTile) }!
    state.players[1].settlements.insert(victimVertex)
    state.players[1].resources = [.ore: 1]
    state.phase = .movingRobber(playerIndex: 0)
    try! RulesEngine.apply(.moveRobber(targetTile, stealFrom: PlayerID(index: 1)), by: PlayerID(index: 0), to: &state)
    #expect(state.board.robberTile == targetTile)
    #expect(state.players[0].resources[.ore] == 1)
    #expect(state.players[1].resources[.ore] == 0)
}
