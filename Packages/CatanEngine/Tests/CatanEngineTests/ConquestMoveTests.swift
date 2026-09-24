import Testing
@testable import CatanEngine

/// Seat 0 in its main turn, holding `hand`, with a settlement on `tile`.
private func conquest(hand: [Int] = [], seed: UInt64 = 1) -> (GameState, Tile) {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed, variant: .conquest)
    state.phase = .mainTurn(playerIndex: 0)
    let tile = state.board.tiles.first { $0.numberToken == 6 }!
    state.players[0].settlements.insert(HexGeometry.corners(of: tile.coordinate)[0])
    state.armyHands[state.players[0].id] = hand
    return (state, tile)
}

private let everyResource: [Resource: Int] = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]

@Test func buyingCostsAnyThreeAndDrawsTheTopCardUnplayableThisTurn() throws {
    var (state, _) = conquest()
    state.players[0].resources = everyResource
    let top = state.armyDeck[0]
    try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    #expect(state.players[0].resources.values.reduce(0, +) == 2)
    #expect(state.armyHands[state.players[0].id] == [top])
    #expect(Conquest.playableCards(for: state.players[0].id, in: state).isEmpty)
}

@Test func aCardBoughtThisTurnIsNotPlayableEvenWhenAnOlderTwinIs() throws {
    var (state, _) = conquest(hand: [3])
    state.armyDeck[0] = 3
    state.players[0].resources = everyResource
    try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    #expect(Conquest.playableCards(for: state.players[0].id, in: state) == [3])
}

@Test func anEmptyArmyDeckCannotBeBoughtFrom() {
    var (state, _) = conquest()
    state.armyDeck = []
    state.players[0].resources = everyResource
    #expect(!RulesEngine.legalMoves(for: state).contains(.buyArmyCard))
    #expect(throws: (any Error).self) { try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state) }
}

@Test func attackingPastATribeTakesTheHexWithTheOverflow() throws {
    var (state, tile) = conquest(hand: [9])
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [9]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == Garrison(owner: state.players[0].id, strength: 4))
    #expect(state.armyHands[state.players[0].id] == [])
}

@Test func anAttackThatFallsShortWeakensTheDefender() throws {
    var (state, tile) = conquest(hand: [2])
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [2]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == Garrison(owner: nil, strength: 3))
}

@Test func anExactlyEqualAttackLeavesTheHexUnoccupied() throws {
    var (state, tile) = conquest(hand: [2, 3])
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [2, 3]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == nil)
}

@Test func deployingOnYourOwnHexReinforcesIt() throws {
    var (state, tile) = conquest(hand: [4])
    state.garrisons[tile.coordinate] = Garrison(owner: state.players[0].id, strength: 10)
    try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [4]), by: state.players[0].id, to: &state)
    #expect(state.garrisons[tile.coordinate] == Garrison(owner: state.players[0].id, strength: 14))
}

@Test func aHexYourBuildingsDoNotTouchCannotBeDeployedTo() {
    var (state, tile) = conquest(hand: [9])
    let far = state.board.tiles.first { tile2 in
        tile2.numberToken != nil && tile2.coordinate != tile.coordinate
            && !HexGeometry.corners(of: tile2.coordinate).contains(HexGeometry.corners(of: tile.coordinate)[0])
    }!
    #expect(!Conquest.canDeploy(to: far.coordinate, by: state.players[0].id, in: state))
    #expect(throws: (any Error).self) {
        try RulesEngine.apply(.deployArmy(to: far.coordinate, strengths: [9]), by: state.players[0].id, to: &state)
    }
}

@Test func theDesertCannotBeDeployedTo() {
    var (state, _) = conquest(hand: [9])
    let desert = state.board.tiles.first { $0.numberToken == nil }!
    state.players[0].settlements.insert(HexGeometry.corners(of: desert.coordinate)[0])
    #expect(!Conquest.canDeploy(to: desert.coordinate, by: state.players[0].id, in: state))
}

@Test func deployingCardsNotHeldIsRefusedWithoutMutation() {
    let (start, tile) = conquest(hand: [3, 5])
    for strengths in [[9], [3, 3], [], [5, 5, 3]] {
        var state = start
        #expect(throws: (any Error).self) {
            try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: strengths),
                                  by: state.players[0].id, to: &state)
        }
        #expect(state == start)
    }
}

@Test func legalMovesOfferEachSingleCardAndTheCheapestWinningSet() {
    let (state, tile) = conquest(hand: [1, 2, 4, 9])
    let deploys = RulesEngine.legalMoves(for: state).filter {
        if case .deployArmy(let hex, _) = $0 { return hex == tile.coordinate } else { return false }
    }
    // Tribe on a 6 holds at 5: the cheapest set that takes it sums to 6 ([2, 4]).
    #expect(Set(deploys) == [
        .deployArmy(to: tile.coordinate, strengths: [1]),
        .deployArmy(to: tile.coordinate, strengths: [2]),
        .deployArmy(to: tile.coordinate, strengths: [4]),
        .deployArmy(to: tile.coordinate, strengths: [9]),
        .deployArmy(to: tile.coordinate, strengths: [2, 4]),
    ])
}

@Test func setupEndDealsEveryPlayerOnePlayableArmyCard() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5, variant: .conquest)
    let top4 = Array(state.armyDeck.prefix(4))
    Conquest.dealStartingCards(&state)
    for (index, player) in state.players.enumerated() {
        #expect(state.armyHands[player.id] == [top4[index]])
        #expect(Conquest.playableCards(for: player.id, in: state) == [top4[index]])
    }
    #expect(state.armyDeck.count == 25)
}

@Test func aStandardGameListsNoArmyMovesAndRefusesThem() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = everyResource
    let tile = state.board.tiles.first { $0.numberToken == 6 }!
    #expect(!RulesEngine.legalMoves(for: state).contains(.buyArmyCard))
    #expect(throws: (any Error).self) {
        try RulesEngine.apply(.deployArmy(to: tile.coordinate, strengths: [1]), by: state.players[0].id, to: &state)
    }
}

@Test func endTurnMakesBoughtCardsPlayable() throws {
    var (state, _) = conquest()
    state.players[0].resources = everyResource
    try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    try RulesEngine.apply(.endTurn, by: state.players[0].id, to: &state)
    #expect(Conquest.playableCards(for: state.players[0].id, in: state).count == 1)
}

@Test func anyThreePricePaysFromTheBiggestPilesFirst() throws {
    var (state, _) = conquest()
    state.armyPrice = .anyThree
    state.players[0].resources = [.ore: 2, .wool: 2, .brick: 1]
    let events = try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    // Ties break in Resource.allCases order, so the result is the same in every process.
    let paid = Conquest.payment(for: [.ore: 2, .wool: 2, .brick: 1], price: .anyThree)!
    #expect(paid.values.reduce(0, +) == 3)
    #expect(events.contains(.boughtArmyCard(state.players[0].id, paid: paid)))
    #expect(state.players[0].resources.values.reduce(0, +) == 2)
    #expect(state.armyHands[state.players[0].id]?.count == 1)
}

@Test func anyThreePriceIsUnaffordableWithTwoCards() {
    var (state, _) = conquest()
    state.armyPrice = .anyThree
    state.players[0].resources = [.ore: 2]
    #expect(!RulesEngine.legalMoves(for: state).contains(.buyArmyCard))
}

@Test func anyOnePriceTakesASingleCard() throws {
    var (state, _) = conquest()
    state.armyPrice = .anyOne
    state.players[0].resources = [.grain: 1]
    try RulesEngine.apply(.buyArmyCard, by: state.players[0].id, to: &state)
    #expect(state.players[0].resources.values.reduce(0, +) == 0)
}

@Test func oneOfEachStillNeedsAllFive() {
    #expect(Conquest.payment(for: [.ore: 4, .wool: 4, .brick: 4, .grain: 4], price: .oneOfEach) == nil)
    #expect(Conquest.payment(for: everyResource, price: .oneOfEach) == Conquest.armyCardCost)
}

@Test func deployMovesOfferEveryCardSetOnEveryReachableHex() {
    let (state, tile) = conquest(hand: [3, 3, 5])
    let sets = Set(Conquest.deployMoves(for: state.players[0].id, in: state).compactMap { move -> [Int]? in
        guard case .deployArmy(let hex, let strengths) = move, hex == tile.coordinate else { return nil }
        return strengths
    })
    #expect(sets == [[3], [5], [3, 3], [3, 5], [3, 3, 5]])
}

@Test func deployMovesNeverOfferACardBoughtThisTurn() {
    var (state, _) = conquest(hand: [2, 5])
    state.armyCardsBoughtThisTurn[state.players[0].id] = [5]
    let offered = Conquest.deployMoves(for: state.players[0].id, in: state).allSatisfy {
        if case .deployArmy(_, let strengths) = $0 { return !strengths.contains(5) } else { return false }
    }
    #expect(offered)
}
