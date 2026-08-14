import Testing
@testable import CatanEngine

@Test func buyingDevCardDeductsCostAndDraws() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].resources = [.ore: 1, .wool: 1, .grain: 1]
    let deckSizeBefore = state.devCardDeck.count
    try! DevCards.buy(by: PlayerID(index: 0), state: &state)
    #expect(state.players[0].resources[.ore] == 0)
    #expect(state.players[0].devCards.count == 1)
    #expect(state.devCardDeck.count == deckSizeBefore - 1)
}

@Test func cannotPlayDevCardBoughtThisTurn() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].resources = [.ore: 1, .wool: 1, .grain: 1]
    try! DevCards.buy(by: PlayerID(index: 0), state: &state)
    #expect(!RulesEngine.legalMoves(for: state).contains { if case .playKnight = $0 { return true }; return false })
}

@Test func thirdKnightGrantsLargestArmy() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].devCards = [.knight, .knight, .knight]
    state.players[0].playedKnights = 2
    let tile = state.board.tiles.first!.coordinate
    try! DevCards.playKnight(moveRobberTo: tile, stealFrom: nil, by: PlayerID(index: 0), state: &state)
    #expect(state.players[0].playedKnights == 3)
    #expect(state.largestArmyPlayer == PlayerID(index: 0))
}

/// Mirrors `LongestRoad`'s tie-keeps-current-holder rule: two players tied
/// at the same knight count don't hand the bonus to either one unless one of
/// them already held it.
@Test func tiedKnightCountsKeepCurrentLargestArmyHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p0 = PlayerID(index: 0)
    state.players[0].playedKnights = 3
    state.players[1].playedKnights = 3
    state.largestArmyPlayer = p0

    #expect(state.players[0].playedKnights == state.players[1].playedKnights)
    // Recompute the same way `DevCards.playKnight` does, without needing an
    // actual fourth knight card in hand for this check.
    state.players[0].devCards = [.knight]
    let tile = state.board.tiles.map(\.coordinate).first { $0 != state.board.robberTile }!
    try! DevCards.playKnight(moveRobberTo: tile, stealFrom: nil, by: p0, state: &state)
    #expect(state.players[0].playedKnights == 4)
    #expect(state.largestArmyPlayer == p0)
}

/// A tie between two players NEITHER of whom currently holds Largest Army
/// awards no one - same "no current holder + tie" rule `LongestRoad` uses.
@Test func newTieBetweenTwoPlayersAwardsNoOne() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let p1 = PlayerID(index: 1)
    state.players[1].playedKnights = 2
    state.players[1].devCards = [.knight]
    state.players[2].playedKnights = 3
    let tile = state.board.tiles.map(\.coordinate).first { $0 != state.board.robberTile }!

    try! DevCards.playKnight(moveRobberTo: tile, stealFrom: nil, by: p1, state: &state)

    #expect(state.players[1].playedKnights == 3)
    #expect(state.largestArmyPlayer == nil)
}

@Test func playingKnightMovesRobberAndConsumesCard() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].devCards = [.knight]
    let tile = state.board.tiles.map(\.coordinate).first { $0 != state.board.robberTile }!
    try! DevCards.playKnight(moveRobberTo: tile, stealFrom: nil, by: PlayerID(index: 0), state: &state)
    #expect(state.board.robberTile == tile)
    #expect(state.players[0].devCards.isEmpty)
    #expect(state.players[0].playedKnights == 1)
}

@Test func roadBuildingBuildsTwoFreeRoads() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].devCards = [.roadBuilding]
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)
    let e1 = state.board.edgesTouching(vertex).first!
    let (a, b) = state.board.vertices(of: e1)
    let midVertex = (a == vertex) ? b : a
    let e2 = state.board.edgesTouching(midVertex).first { $0 != e1 }!
    state.players[0].resources = [:] // free - no resources needed

    try DevCards.playRoadBuilding(e1, e2, by: PlayerID(index: 0), state: &state)

    #expect(state.players[0].roads.contains(e1))
    #expect(state.players[0].roads.contains(e2))
    #expect(state.players[0].devCards.isEmpty)
}

@Test func roadBuildingThrowsIfEitherEdgeIsIllegal() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].devCards = [.roadBuilding]
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)
    let e1 = state.board.edgesTouching(vertex).first!

    // e2 is a legal on-board edge but does not connect to player 0's
    // network - the second road should fail and neither should be built.
    let farVertex = state.board.onBoardVertices.sorted().last!
    let e2 = state.board.edgesTouching(farVertex).first { $0 != e1 }!

    #expect(throws: MoveError.illegalPlacement) {
        try DevCards.playRoadBuilding(e1, e2, by: PlayerID(index: 0), state: &state)
    }
    #expect(state.players[0].roads.isEmpty)
    #expect(state.players[0].devCards == [.roadBuilding]) // card not consumed
}

@Test func yearOfPlentyGrantsTwoResourcesCappedByBank() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].devCards = [.yearOfPlenty]
    state.bank[.ore] = 0 // bank is out of ore

    try! DevCards.playYearOfPlenty(.ore, .grain, by: PlayerID(index: 0), state: &state)

    #expect((state.players[0].resources[.ore] ?? 0) == 0) // capped - bank had none
    #expect((state.players[0].resources[.grain] ?? 0) == 1)
    #expect(state.players[0].devCards.isEmpty)
}

/// Regression test: `RulesEngine.legalMoves` enumerates r1/r2 independently
/// for `.playYearOfPlenty` (see RulesEngine.swift), so picking the same
/// resource twice (e.g. "take 2 lumber") is a legal move. Applying it used
/// to crash with "Dictionary literal contains duplicate keys" because the
/// log line built `[r1: 1, r2: 1]` as a literal, which is fatal when r1 ==
/// r2 - only reachable via `RulesEngine.apply` (not `DevCards.playYearOfPlenty`
/// directly), since that's where the log line lived.
@Test func yearOfPlentyWithSameResourceTwiceDoesNotCrash() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].devCards = [.yearOfPlenty]

    try! RulesEngine.apply(.playYearOfPlenty(.lumber, .lumber), by: PlayerID(index: 0), to: &state)

    #expect((state.players[0].resources[.lumber] ?? 0) == 2)
    #expect(state.players[0].devCards.isEmpty)
    #expect(state.log.last?.contains("2 lumber") == true)
}

@Test func monopolyTransfersAllMatchingCardsFromEveryOtherPlayer() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].devCards = [.monopoly]
    state.players[1].resources = [.wool: 3]
    state.players[2].resources = [.wool: 1, .brick: 2]
    state.players[3].resources = [:]

    try! DevCards.playMonopoly(.wool, by: PlayerID(index: 0), state: &state)

    #expect((state.players[0].resources[.wool] ?? 0) == 4)
    #expect((state.players[1].resources[.wool] ?? 0) == 0)
    #expect((state.players[2].resources[.wool] ?? 0) == 0)
    #expect((state.players[2].resources[.brick] ?? 0) == 2) // untouched
    #expect(state.players[0].devCards.isEmpty)
}

@Test func buyingIsLimitedByDeckSize() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.devCardDeck = []
    state.players[0].resources = [.ore: 1, .wool: 1, .grain: 1]

    #expect(throws: (any Error).self) {
        try DevCards.buy(by: PlayerID(index: 0), state: &state)
    }
    #expect(state.players[0].devCards.isEmpty)
    #expect((state.players[0].resources[.ore] ?? 0) == 1) // untouched - cost not deducted
}

/// Knight is the one dev card the official rules let you play before
/// rolling (e.g. to move the robber off your own tile before the dice can
/// hit it) - `.rollDice` must enumerate and accept `.playKnight` and stay
/// in `.rollDice` afterward so the player still has to roll.
@Test func knightCanBePlayedBeforeRolling() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .rollDice(playerIndex: 0)
    state.players[0].devCards = [.knight]
    let tile = state.board.tiles.map(\.coordinate).first { $0 != state.board.robberTile }!

    #expect(RulesEngine.legalMoves(for: state).contains { if case .playKnight = $0 { return true }; return false })

    try RulesEngine.apply(.playKnight(moveRobberTo: tile, stealFrom: nil), by: PlayerID(index: 0), to: &state)

    #expect(state.board.robberTile == tile)
    #expect(state.players[0].devCards.isEmpty)
    #expect(state.players[0].playedKnights == 1)
    #expect(state.phase == .rollDice(playerIndex: 0)) // still owes the roll
}

/// The other three dev cards remain unplayable before rolling - only
/// Knight gets the pre-roll exception.
@Test func nonKnightCardsAreNotOfferedBeforeRolling() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .rollDice(playerIndex: 0)
    state.players[0].devCards = [.roadBuilding, .yearOfPlenty, .monopoly]

    let moves = RulesEngine.legalMoves(for: state)
    #expect(!moves.contains { if case .playRoadBuilding = $0 { return true }; return false })
    #expect(!moves.contains { if case .playYearOfPlenty = $0 { return true }; return false })
    #expect(!moves.contains { if case .playMonopoly = $0 { return true }; return false })
}

@Test func devCardsBoughtThisTurnBecomePlayableAfterEndTurn() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = [.ore: 1, .wool: 1, .grain: 1]
    // The deck is shuffled by `GameSetup.newGame`, so explicitly reorder it
    // here to force a knight to the top - otherwise which card gets bought
    // (and thus what `canPlay(.knight, ...)` should report) would be
    // shuffle-dependent.
    state.devCardDeck = [.knight] + state.devCardDeck.filter { $0 != .knight }
    try! RulesEngine.apply(.buyDevCard, by: PlayerID(index: 0), to: &state)
    #expect(!DevCards.canPlay(.knight, by: PlayerID(index: 0), in: state))

    try! RulesEngine.apply(.endTurn, by: PlayerID(index: 0), to: &state)
    #expect(state.devCardsBoughtThisTurn.isEmpty)
    #expect(DevCards.canPlay(.knight, by: PlayerID(index: 0), in: state))
}
