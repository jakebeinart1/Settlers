import Testing
@testable import CatanEngine

/// Pins what `RulesEngine.apply` reports.
///
/// These events are now the only channel by which anything outside the engine
/// learns what a move did - the UI drives its roll highlight from `.rolled`,
/// and a recorded game's readable history would come from here. Before this,
/// the same information was a prose sentence in `GameState.log` that the UI
/// substring-matched, so rewording it silently broke a visual effect and no
/// test noticed. The point of this suite is that a reword cannot happen at all
/// now, and that the *payloads* - the ones carrying facts the resulting state
/// does not preserve - are correct.

private func mainTurnState(seed: UInt64 = 1) -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
    state.phase = .mainTurn(playerIndex: 0)
    return state
}

@Test func rollingReportsTheTotalThatWasActuallyRolled() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5)
    state.phase = .rollDice(playerIndex: 0)
    let player = state.players[0].id

    let events = try RulesEngine.apply(.rollDice, by: player, to: &state)

    guard case .rolled(let who, let total)? = events.first(where: {
        if case .rolled = $0 { return true } else { return false }
    }) else {
        Issue.record("a roll must report a .rolled event")
        return
    }
    #expect(who == player)
    #expect((2...12).contains(total))
    // The event and the state must agree; the UI reads the total from the
    // event now rather than reaching back into `lastDiceRoll`.
    #expect(total == state.lastDiceRoll)
}

@Test func buildingReportsWhatWasBuilt() throws {
    var state = mainTurnState()
    let player = state.players[0].id
    state.players[0].resources = [.ore: 3, .grain: 2]

    // Placed directly rather than through `canBuildSettlement`: outside setup
    // that also requires a connecting road, and this test is about the event a
    // city upgrade emits, not about placement legality.
    let vertex = try #require(state.board.onBoardVertices.sorted().first)
    state.players[0].settlements.insert(vertex)

    let events = try RulesEngine.apply(.buildCity(vertex), by: player, to: &state)

    #expect(events.contains(.builtCity(player)))
    #expect(state.players[0].cities.contains(vertex))
    #expect(!state.players[0].settlements.contains(vertex), "a city replaces its settlement")
}

@Test func monopolyReportsHowManyCardsItSweptUp() throws {
    var state = mainTurnState()
    let player = state.players[0].id
    state.players[0].devCards = [.monopoly]
    state.players[1].resources = [.wool: 3]
    state.players[2].resources = [.wool: 2, .brick: 5]
    state.players[3].resources = [:]

    let events = try RulesEngine.apply(.playMonopoly(.wool), by: player, to: &state)

    // The count is the interesting part of a monopoly and is NOT recoverable
    // from the resulting state - the player's wool total mixes it with
    // whatever they already held.
    #expect(events.contains(.playedMonopoly(player, resource: .wool, gained: 5)))
    #expect(state.players[0].resources[.wool] == 5)
}

@Test func aRobberStealReportsWhichCardWasTaken() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 11)
    let thief = state.players[0].id
    let victim = state.players[1].id

    // Put the victim on a tile the robber is not already on, holding exactly
    // one card, so the stolen resource is knowable.
    let target = try #require(state.board.tiles.map(\.coordinate).first { $0 != state.board.robberTile })
    let corner = try #require(HexGeometry.corners(of: target).first)
    state.players[1].settlements.insert(corner)
    state.players[1].resources = [.ore: 1]
    state.phase = .movingRobber(playerIndex: 0)

    let events = try RulesEngine.apply(.moveRobber(target, stealFrom: victim), by: thief, to: &state)

    // Only the engine ever knew which card the robber drew. If it does not
    // say, a recorded game cannot report it and a replay cannot check it.
    #expect(events.contains(.movedRobber(thief, from: victim, stealing: .ore)))
    #expect(state.players[0].resources[.ore] == 1)
    #expect((state.players[1].resources[.ore] ?? 0) == 0)
}

@Test func movingTheRobberWithNobodyToRobReportsNoSteal() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 12)
    let thief = state.players[0].id
    let target = try #require(state.board.tiles.map(\.coordinate).first { $0 != state.board.robberTile })
    state.phase = .movingRobber(playerIndex: 0)

    let events = try RulesEngine.apply(.moveRobber(target, stealFrom: nil), by: thief, to: &state)

    #expect(events.contains(.movedRobber(thief, from: nil, stealing: nil)))
}

@Test func endingATurnReportsIt() throws {
    var state = mainTurnState()
    let player = state.players[0].id
    let events = try RulesEngine.apply(.endTurn, by: player, to: &state)
    #expect(events.contains(.endedTurn(player)))
}

@Test func aWinningMoveReportsTheWinExactlyOnce() throws {
    var state = mainTurnState()
    let player = state.players[0].id
    let vertices = state.board.onBoardVertices.sorted()

    // Three cities (6) plus three settlements (3) is nine points; upgrading
    // one settlement makes it four cities and two settlements, which is ten.
    //
    // Deliberately NOT four cities plus a settlement: that is already at the
    // four-city supply limit, so the upgrade is rejected as illegal - which is
    // the piece-limit rule working, and worth writing down because the obvious
    // fixture trips it.
    state.players[0].cities = Set(vertices.prefix(3))
    let settlements = Array(vertices.dropFirst(20).prefix(3))
    state.players[0].settlements = Set(settlements)
    let toUpgrade = try #require(settlements.first)
    state.players[0].resources = [.ore: 3, .grain: 2]
    #expect(state.victoryPoints(for: player) == 9, "position should be one point short")

    let events = try RulesEngine.apply(.buildCity(toUpgrade), by: player, to: &state)

    guard case .gameOver(let winner) = state.phase else {
        Issue.record("reaching ten points must end the game")
        return
    }
    #expect(winner == player)
    let wins = events.filter { if case .gameWon = $0 { return true } else { return false } }
    #expect(wins == [.gameWon(player)], "the win must be reported exactly once, not per exit path")
}

@Test func setupPlacementsReportThemselves() throws {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 2)
    let player = state.players[0].id

    let vertex = try #require(RulesEngine.legalMoves(for: state).compactMap {
        if case .placeInitialSettlement(let v) = $0 { return v } else { return nil }
    }.first)
    let settlementEvents = try RulesEngine.apply(.placeInitialSettlement(vertex), by: player, to: &state)
    #expect(settlementEvents == [.placedInitialSettlement(player)])

    let edge = try #require(RulesEngine.legalMoves(for: state).compactMap {
        if case .placeInitialRoad(let e) = $0 { return e } else { return nil }
    }.first)
    let roadEvents = try RulesEngine.apply(.placeInitialRoad(edge), by: player, to: &state)
    #expect(roadEvents == [.placedInitialRoad(player)])
}
