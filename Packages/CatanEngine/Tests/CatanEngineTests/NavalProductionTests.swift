import Testing
@testable import CatanEngine

struct NavalProductionTests {
    @Test func citiesChooseTwoUnitsClockwiseAfterFixedProduction() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let tile = try #require(state.board.tiles.first { $0.kind == .resourceChoice })
        let corners = state.board.corners(of: tile.coordinate)
        state.players[0].cities.insert(corners[0])
        state.players[2].settlements.insert(corners[3])
        let roll = try #require(tile.numberToken)
        let fixed = MainPhase.payouts(for: roll, in: state)
        let before = state.players.map(\.resources)
        try NavalTestSupport.roll(roll, player: 3, state: &state)
        #expect(state.phase == .choosingResource(playerIndex: 0))
        for index in state.players.indices {
            for resource in Resource.allCases { #expect(state.players[index].resources[resource, default: 0] == before[index][resource, default: 0] + (fixed[index]?[resource] ?? 0)) }
        }
        let pending = state
        #expect(throws: MoveError.self) { try RulesEngine.apply(.endTurn, by: state.players[0].id, to: &state) }
        #expect(state == pending)
        try RulesEngine.apply(.chooseResource(.ore), by: state.players[0].id, to: &state)
        #expect(state.phase == .choosingResource(playerIndex: 0))
        try RulesEngine.apply(.chooseResource(.lumber), by: state.players[0].id, to: &state)
        #expect(state.phase == .choosingResource(playerIndex: 2))
        try RulesEngine.apply(.chooseResource(.brick), by: state.players[2].id, to: &state)
        #expect(state.phase == .mainTurn(playerIndex: 3))
        #expect(state.naval?.pendingResourceChoices.isEmpty == true)
    }

    @Test func unavailableChoicesAreRejectedAndEmptyBankExpiresObligations() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let tile = try #require(state.board.tiles.first { $0.kind == .resourceChoice })
        state.players[0].cities.insert(state.board.corners(of: tile.coordinate)[0])
        state.bank = [.ore: 1]
        try NavalTestSupport.roll(try #require(tile.numberToken), player: 0, state: &state)
        #expect(RulesEngine.legalMoves(for: state) == [.chooseResource(.ore)])
        let unchanged = state
        #expect(throws: MoveError.self) { try RulesEngine.apply(.chooseResource(.brick), by: state.players[0].id, to: &state) }
        #expect(state == unchanged)
        try RulesEngine.apply(.chooseResource(.ore), by: state.players[0].id, to: &state)
        #expect(state.phase == .mainTurn(playerIndex: 0))
        #expect(state.naval?.pendingResourceChoices.isEmpty == true)
    }

    @Test func robberBlocksFlexibleProductionAndNeverTargetsFogOrShips() throws {
        var state = try NavalTestSupport.ready()
        let hiddenLand = try #require(state.board.tiles.first { $0.kind.isLand && !Naval.isRevealed($0.coordinate, in: state) })
        state.phase = .movingRobber(playerIndex: 0)
        #expect(!RulesEngine.legalMoves(for: state).contains { move in
            if case .moveRobber(let hex, _) = move { return hex == hiddenLand.coordinate }
            return false
        })
        let unchanged = state
        #expect(throws: MoveError.self) { try RulesEngine.apply(.moveRobber(hiddenLand.coordinate, stealFrom: nil), by: state.players[0].id, to: &state) }
        #expect(state == unchanged)
        state.naval?.revealed = Set(state.board.tiles.map(\.coordinate))
        let tile = try #require(state.board.tiles.first { $0.kind == .resourceChoice })
        state.players[0].cities.insert(state.board.corners(of: tile.coordinate)[0])
        state.board.robberTile = tile.coordinate
        try NavalTestSupport.roll(try #require(tile.numberToken), player: 0, state: &state)
        #expect(state.phase == .mainTurn(playerIndex: 0))
    }
}
