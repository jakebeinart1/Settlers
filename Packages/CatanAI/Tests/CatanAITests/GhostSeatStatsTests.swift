import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostSeatStatsTests {

    private func played(seed: UInt64 = 71) throws -> (GameState, [LoggedMove], GameState) {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = EvaluationPolicy() }
        var session = GameSession(state: initial, policies: policies, policySeed: seed)
        var moves: [LoggedMove] = []
        while let step = try session.step() { moves.append(LoggedMove(player: step.actor, move: step.move)) }
        return (initial, moves, session.state)
    }

    /// Checked against the final board, a second source the counters never read.
    @Test func countsAgreeWithTheFinalBoard() throws {
        let (initial, moves, final) = try played()
        let stats = try SeatStats.compute(initial: initial, moves: moves)
        #expect(stats.count == final.players.count)
        for (seat, player) in zip(stats, final.players) {
            #expect(seat.citiesBuilt == player.cities.count)
            #expect(player.settlements.count + player.cities.count == 2 + seat.settlementsBuilt)
            #expect(seat.finalVP == min(final.victoryPoints(for: player.id), final.victoryPointTarget))
            #expect(seat.robberHitsLeader <= seat.robberMoves)
            #expect(seat.turns > 0)
        }
        #expect(stats.filter(\.won).count == 1)
        #expect(stats.map(\.tradesCompleted).reduce(0, +) % 2 == 0, "a completed trade counts once for each side")
        #expect(stats.map(\.productionCards).reduce(0, +) > 0)
    }

    @Test func robbingTheLeaderIsCounted() throws {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 72), seed: 72)
        playOpeningPlacements(in: &state, seed: 72)
        let leader = state.players[2].id
        state.players[2].cities.formUnion(state.players[2].settlements)
        state.players[2].resources = [.ore: 2]
        state.phase = .movingRobber(playerIndex: 0)
        let target = state.board.tiles.first { tile in
            tile.coordinate != state.board.robberTile
                && state.board.corners(of: tile.coordinate).contains { state.players[2].settlements.contains($0) }
        }
        let hex = try #require(target).coordinate
        let stats = try SeatStats.compute(initial: state, moves: [LoggedMove(player: state.players[0].id,
                                                                            move: .moveRobber(hex, stealFrom: leader))])
        #expect(stats[0].robberMoves == 1)
        #expect(stats[0].robberHitsLeader == 1)
    }

    /// The radar's six measures, averaged per game.
    @Test func radarMeasuresAverageAcrossGames() {
        var a = SeatStats(seat: 0, target: 10)
        a.turns = 20; a.productionCards = 40; a.settlementsBuilt = 2; a.citiesBuilt = 1
        a.tradesCompleted = 3; a.devCardsPlayed = 2; a.largestArmy = true
        a.robberMoves = 2; a.robberHitsLeader = 1; a.finalVP = 10; a.won = true
        var b = SeatStats(seat: 1, target: 10)
        b.turns = 20; b.productionCards = 20; b.finalVP = 5
        let radar = RadarMeasures(games: [a, b])
        #expect(radar.production == 1.5)          // (2.0 + 1.0) / 2 cards per turn
        #expect(radar.expansion == 1.5)           // (3 + 0) / 2
        #expect(radar.trading == 1.5)
        #expect(radar.development == 2.0)         // (2 + 2 for Largest Army + 0) / 2
        #expect(radar.robber == 0.5)              // 1 hit of 2 robber moves
        #expect(radar.finishing == 0.75)          // (1.0 + 0.5) / 2
    }
}
