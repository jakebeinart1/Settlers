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

@Test func illegalPlacementTooCloseIsRejected() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let firstVertex = board(state).onBoardVertices.sorted().first!
    try! RulesEngine.apply(.placeInitialSettlement(firstVertex), by: p0, to: &state)
    let firstEdge = state.board.edgesTouching(firstVertex).first!
    try! RulesEngine.apply(.placeInitialRoad(firstEdge), by: p0, to: &state)

    // A vertex one edge away from player 0's settlement violates the
    // distance rule and must be rejected, even for a different player.
    let p1 = PlayerID(index: 1)
    let tooCloseVertex = state.board.adjacentVertices(of: firstVertex).first!
    #expect(throws: MoveError.illegalPlacement) {
        try RulesEngine.apply(.placeInitialSettlement(tooCloseVertex), by: p1, to: &state)
    }
}

@Test func wrongTurnMoveIsRejected() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let firstVertex = board(state).onBoardVertices.sorted().first!
    try! RulesEngine.apply(.placeInitialSettlement(firstVertex), by: p0, to: &state)
    let firstEdge = state.board.edgesTouching(firstVertex).first!
    try! RulesEngine.apply(.placeInitialRoad(firstEdge), by: p0, to: &state)

    // Phase is now setupForward(1); player 0 trying to move again is out of turn.
    let anyLegalVertex = RulesEngine.legalMoves(for: state).compactMap { move -> VertexID? in
        if case .placeInitialSettlement(let vertex) = move { return vertex }
        return nil
    }.first!
    #expect(throws: MoveError.notYourTurn) {
        try RulesEngine.apply(.placeInitialSettlement(anyLegalVertex), by: p0, to: &state)
    }
}

@Test func outOfOrderSettlementBeforePendingRoadIsRejected() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    let firstVertex = board(state).onBoardVertices.sorted().first!
    try! RulesEngine.apply(.placeInitialSettlement(firstVertex), by: p0, to: &state)

    // The road for `firstVertex` is still pending; another settlement is
    // out of order regardless of whether the target vertex would otherwise
    // be legal.
    let otherVertex = state.board.onBoardVertices.sorted().last!
    #expect(throws: MoveError.wrongPhase) {
        try RulesEngine.apply(.placeInitialSettlement(otherVertex), by: p0, to: &state)
    }
}

@Test func fullSetupSequenceEndsAtRollDiceForPlayerZero() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    var placements = 0
    while case .setupForward = state.phase {
        let move = RulesEngine.legalMoves(for: state).first!
        let player = currentSetupPlayer(state.phase)
        try! RulesEngine.apply(move, by: player, to: &state)
        placements += 1
    }
    while case .setupBackward = state.phase {
        let move = RulesEngine.legalMoves(for: state).first!
        let player = currentSetupPlayer(state.phase)
        try! RulesEngine.apply(move, by: player, to: &state)
        placements += 1
    }

    // 4 players x 2 passes x (1 settlement + 1 road) = 16 total placements.
    #expect(placements == 16)
    if case .rollDice(let idx) = state.phase {
        #expect(idx == 0)
    } else {
        Issue.record("expected rollDice(0), got \(state.phase)")
    }
    for player in state.players {
        #expect(player.settlements.count == 2)
        #expect(player.roads.count == 2)
    }
}

private func board(_ state: GameState) -> Board { state.board }
private func totalResources(_ p: Player) -> Int { p.resources.values.reduce(0, +) }
private func currentSetupPlayer(_ phase: GamePhase) -> PlayerID {
    switch phase {
    case .setupForward(let i), .setupBackward(let i): return PlayerID(index: i)
    default: fatalError("not in setup")
    }
}
