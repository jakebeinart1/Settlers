import Testing
@testable import CatanEngine

/// Proves each rule site reads its number from the ruleset rather than from a
/// literal. Each case sets up a position that classic and Expanded score or
/// permit differently, so a missed call site fails here rather than surfacing
/// as a 25-point game that ends at 10.
private func expandedGame(seed: UInt64 = 1) -> GameState {
    GameSetup.newGame(board: BoardGenerator.standard(BoardShape.expanded),
                      seed: seed, mode: .expanded)
}

@Test func expandedBonusesAreWorthFourPointsInBothFormulas() {
    var state = expandedGame()
    let seat = state.players[0].id
    // A fresh game: no buildings, so both formulas start at zero and the 8
    // below is purely the two bonuses.
    #expect(state.victoryPoints(for: seat) == 0)
    state.longestRoadPlayer = seat
    state.largestArmyPlayer = seat
    #expect(state.victoryPoints(for: seat) == 8)
    #expect(state.publicVictoryPoints(for: seat) == 8)
}

@Test func expandedSeatsAThirtyEightCardBankAndAFiftyCardDeck() {
    let state = expandedGame()
    for resource in Resource.allCases {
        #expect(state.bank[resource] == 38)
    }
    #expect(state.devCardDeck.count == 50)
    #expect(state.devCardDeck.filter { $0 == .knight }.count == 28)
    #expect(state.devCardDeck.filter { $0 == .victoryPoint }.count == 10)
}

@Test func expandedDiscardThresholdIsTenNotSeven() {
    var state = expandedGame()
    for resource in Resource.allCases {
        state.players[0].resources[resource] = 2   // 10 cards total
    }
    #expect(Robber.playersWhoMustDiscard(state).isEmpty)
    state.players[0].resources[.grain, default: 0] += 1   // 11
    #expect(Robber.playersWhoMustDiscard(state).contains(state.players[0].id))
}

@Test func classicDiscardThresholdIsStillSeven() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    for resource in Resource.allCases {
        state.players[0].resources[resource] = 1   // 5 cards
    }
    #expect(Robber.playersWhoMustDiscard(state).isEmpty)
    state.players[0].resources[.grain] = 4   // 8 cards
    #expect(Robber.playersWhoMustDiscard(state).contains(state.players[0].id))
}

@Test func expandedWinsAtTwentyFiveNotTen() {
    var state = expandedGame()
    let seat = state.players[0].id
    // `Player.victoryPoints` is COMPUTED and read-only (`Player.swift:35`) -
    // it cannot be assigned. Build the total out of real pieces instead:
    // 8 cities (16) + 1 settlement (1) = 17, so the two 4-point bonuses are
    // exactly what carries this seat from 21 to 25.
    let vertices = state.board.onBoardVertices.sorted()
    state.players[0].cities = Set(vertices.prefix(8))
    state.players[0].settlements = Set(vertices.dropFirst(8).prefix(1))
    #expect(state.victoryPoints(for: seat) == 17)

    state.longestRoadPlayer = seat   // 17 + 4 = 21
    WinCondition.checkForWinner(&state)
    if case .gameOver = state.phase { Issue.record("ended at 21 of 25") }

    state.largestArmyPlayer = seat   // 21 + 4 = 25
    #expect(state.victoryPoints(for: seat) == 25)
    WinCondition.checkForWinner(&state)
    #expect(state.phase == .gameOver(winner: seat))
}

@Test func expandedAllowsThirtyRoadsWhereClassicStopsAtFifteen() {
    #expect(Ruleset.forMode(.expanded).maxRoadsPerPlayer == 30)
    #expect(Ruleset.forMode(.classic).maxRoadsPerPlayer == 15)
    // The supply check reads the ruleset: a classic game must still refuse a
    // 16th road. `PieceSupplyTests` covers the classic path in full.
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    let seat = state.players[0].id
    state.players[0].roads = Set(state.board.onBoardEdges.sorted().prefix(15))
    let spare = state.board.onBoardEdges.sorted().dropFirst(15).first!
    #expect(!Building.canBuildRoad(spare, for: seat, in: state))
}
