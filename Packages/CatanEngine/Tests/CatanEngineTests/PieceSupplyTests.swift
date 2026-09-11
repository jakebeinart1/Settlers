import Testing
@testable import CatanEngine

/// Guards the per-player piece supply, which the engine did not model at all.
/// A 30-game sweep against the previous build found 17 games exceeding the
/// real limits, peaking at 23 roads (limit 15) and 9 settlements (limit 5) -
/// so roughly half of all games were running a ruleset that is not Catan, and
/// every tuned constant in the bot was fitted against that.

/// Plays a full random-legal game and returns the largest piece counts any
/// player reached.
private func peakPieceCounts(boardSeed: UInt64, driverSeed: UInt64) -> (roads: Int, settlements: Int, cities: Int) {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: boardSeed), seed: boardSeed)
    var driver = RandomSource(seed: driverSeed)
    var peak = (roads: 0, settlements: 0, cities: 0)

    for _ in 0..<4000 {
        if case .gameOver = state.phase { break }

        guard let actor = actingPlayer(state),
              let move = RulesEngine.legalMoves(for: state).randomElement(using: &driver) else { break }
        do { try RulesEngine.apply(move, by: actor, to: &state) } catch { break }

        for player in state.players {
            peak.roads = max(peak.roads, player.roads.count)
            peak.settlements = max(peak.settlements, player.settlements.count)
            peak.cities = max(peak.cities, player.cities.count)
        }
    }
    return peak
}

@Test func noPlayerEverExceedsTheirPieceSupply() {
    let rules = Ruleset.forMode(.classic)
    for seed: UInt64 in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] {
        let peak = peakPieceCounts(boardSeed: seed, driverSeed: seed &* 13)
        #expect(peak.roads <= rules.maxRoadsPerPlayer,
                "seed \(seed): a player held \(peak.roads) roads, limit \(rules.maxRoadsPerPlayer)")
        #expect(peak.settlements <= rules.pieceLimit(for: .settlement),
                "seed \(seed): a player held \(peak.settlements) settlements, limit \(rules.pieceLimit(for: .settlement))")
        #expect(peak.cities <= rules.pieceLimit(for: .city),
                "seed \(seed): a player held \(peak.cities) cities, limit \(rules.pieceLimit(for: .city))")
    }
}

@Test func aPlayerAtTheRoadLimitHasNoLegalRoadToBuild() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    let player = state.players[0].id

    // Hand the player the whole road supply plus resources for one more.
    let maxRoads = Ruleset.forMode(.classic).maxRoadsPerPlayer
    state.players[0].roads = Set(state.board.onBoardEdges.sorted().prefix(maxRoads))
    state.players[0].resources = [.brick: 5, .lumber: 5]
    state.phase = .mainTurn(playerIndex: 0)

    #expect(state.players[0].roads.count == maxRoads)
    let anyRoadIsLegal = state.board.onBoardEdges.contains { Building.canBuildRoad($0, for: player, in: state) }
    #expect(!anyRoadIsLegal, "a player who has placed all 15 roads must not be offered another")
    let roadMoves = RulesEngine.legalMoves(for: state).filter {
        if case .buildRoad = $0 { return true } else { return false }
    }
    #expect(roadMoves.isEmpty)
}

@Test func endTurnClearsPendingTradeOffers() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = [.ore: 3]

    let offer = TradeOffer(from: state.players[0].id, give: [.ore: 1], want: [.wool: 1])
    try Trading.proposeTrade(offer, state: &state)
    #expect(state.pendingTradeOffers.count == 1)

    try RulesEngine.apply(.endTurn, by: state.players[0].id, to: &state)
    // Nothing but an explicit response used to remove an offer, so unanswered
    // offers survived every turn - a 93-deep backlog was observed in one game,
    // letting an offer be accepted turns after it was made.
    #expect(state.pendingTradeOffers.isEmpty, "an unanswered offer must not outlive the turn that made it")
}
