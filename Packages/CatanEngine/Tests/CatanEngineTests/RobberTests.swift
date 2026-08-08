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

@Test func negativeDiscardAmountIsRejected() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[1].resources = [.brick: 0, .lumber: 9] // 9 cards -> discard 4
    state.phase = .discarding(pending: [PlayerID(index: 1)])
    #expect(throws: MoveError.illegalPlacement) {
        try RulesEngine.apply(.discard([.brick: -100, .lumber: 104]), by: PlayerID(index: 1), to: &state)
    }
    // Resources must be untouched and the bank uncorrupted.
    #expect(state.players[1].resources[.lumber] == 9)
    #expect(state.players[1].resources[.brick] == 0)
}

@Test func legalMovesEnumeratesDiscardCombinationsForEachPendingPlayer() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[1].resources = [.brick: 4] // 4 cards -> discard 2
    state.phase = .discarding(pending: [PlayerID(index: 1)])
    let moves = RulesEngine.legalMoves(for: state)
    #expect(!moves.isEmpty)
    #expect(moves.allSatisfy {
        if case .discard(let combo) = $0 { return combo.values.reduce(0, +) == 2 }
        return false
    })
    #expect(moves.contains {
        if case .discard(let combo) = $0 { return combo[.brick] == 2 }
        return false
    })
}

@Test func legalMovesEnumeratesMoveRobberTargetsAndVictims() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let targetTile = state.board.tiles.first { $0.coordinate != state.board.robberTile }!.coordinate
    let victimVertex = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(targetTile) }!
    state.players[1].settlements.insert(victimVertex)
    state.players[1].resources = [.ore: 1]
    state.phase = .movingRobber(playerIndex: 0)
    let moves = RulesEngine.legalMoves(for: state)
    let currentRobberTile = state.board.robberTile
    #expect(!moves.contains {
        if case .moveRobber(let tile, _) = $0 { return tile == currentRobberTile }
        return false
    })
    #expect(moves.contains {
        if case .moveRobber(let tile, let stealFrom) = $0 { return tile == targetTile && stealFrom == PlayerID(index: 1) }
        return false
    })
    #expect(moves.contains {
        if case .moveRobber(let tile, let stealFrom) = $0 { return tile == targetTile && stealFrom == nil }
        return false
    })
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
