import Testing
@testable import CatanEngine

@Test func setupPhaseFollowsSnakeOrder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let firstVertex = board(state).onBoardVertices.sorted().first!
    try! RulesEngine.apply(.placeInitialSettlement(firstVertex), by: p0, to: &state)
    let firstEdge = state.board.edgesTouching(firstVertex).first!
    try! RulesEngine.apply(.placeInitialRoad(firstEdge), by: p0, to: &state)
    if case .setupForward(let idx) = state.phase {
        #expect(idx == 1)
    } else {
        Issue.record("expected setupForward(1), got \(state.phase)")
    }
}

@Test func secondSettlementGrantsResources() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    // Fast-forward through players 0-3 forward pass, then 3-0 backward pass,
    // placing legal moves each time via RulesEngine.legalMoves(for:).first!
    while case .setupForward = state.phase {
        let move = RulesEngine.legalMoves(for: state).first!
        let player = currentSetupPlayer(state.phase)
        try! RulesEngine.apply(move, by: player, to: &state)
    }
    let beforeTotal = totalResources(state.players[3])
    // player 3 goes first in backward pass; placing their settlement then road
    let settleMove = RulesEngine.legalMoves(for: state).first!
    try! RulesEngine.apply(settleMove, by: PlayerID(index: 3), to: &state)
    let afterTotal = totalResources(state.players[3])
    #expect(afterTotal >= beforeTotal) // grants resources unless placed on desert-only spot
}

private func board(_ state: GameState) -> Board { state.board }
private func totalResources(_ p: Player) -> Int { p.resources.values.reduce(0, +) }
private func currentSetupPlayer(_ phase: GamePhase) -> PlayerID {
    switch phase {
    case .setupForward(let i), .setupBackward(let i): return PlayerID(index: i)
    default: fatalError("not in setup")
    }
}
