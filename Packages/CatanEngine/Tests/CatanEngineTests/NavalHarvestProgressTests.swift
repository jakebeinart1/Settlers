import Foundation
import Testing
@testable import CatanEngine

struct NavalHarvestProgressTests {
    @Test(arguments: ["settlement", "city", "twoSettlements", "mixed"])
    func producingBuildingsRemainDistinct(kind: String) throws {
        let settlements = kind == "city" ? 0 : kind == "twoSettlements" ? 2 : 1
        let cities = kind == "city" || kind == "mixed" ? 1 : 0
        let state = try harvest(settlements: settlements, cities: cities)
        let progress = try #require(Naval.harvestProgress(for: state.players[0].id, in: state))
        #expect(progress.settlements == settlements)
        #expect(progress.cities == cities)
        #expect(progress.total == settlements + 2 * cities)
        #expect(progress.remaining == progress.total)
        #expect(progress.collected == 0)
        #expect(Naval.harvestProgress(for: state.players[1].id, in: state) == nil)
    }

    @Test func partialCityHarvestKeepsItsOriginalYieldAcrossColdCheckpoint() throws {
        var state = try harvest(settlements: 0, cities: 1)
        try RulesEngine.apply(.chooseResource(.ore), by: state.players[0].id, to: &state)
        let checkpoint = GameSession(state: state, policies: [:], policySeed: 1).checkpoint
        try checkpoint.validate()
        let restored = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(checkpoint))
        try restored.validate()
        let progress = try #require(Naval.harvestProgress(for: state.players[0].id, in: restored.state))
        #expect(progress.cities == 1)
        #expect(progress.settlements == 0)
        #expect(progress.total == 2)
        #expect(progress.collected == 1)
        #expect(progress.remaining == 1)
    }

    @Test func rejectedChoiceCannotAdvanceProgressAndBankExhaustionRetiresIt() throws {
        var state = try harvest(settlements: 0, cities: 1)
        state.bank = [.ore: 1]
        let before = Naval.harvestProgress(for: state.players[0].id, in: state)
        #expect(throws: MoveError.self) {
            try RulesEngine.apply(.chooseResource(.brick), by: state.players[0].id, to: &state)
        }
        #expect(Naval.harvestProgress(for: state.players[0].id, in: state) == before)
        try RulesEngine.apply(.chooseResource(.ore), by: state.players[0].id, to: &state)
        #expect(Naval.harvestProgress(for: state.players[0].id, in: state) == nil)
        #expect(state.naval?.pendingResourceChoices.isEmpty == true)
    }

    @Test func robberBlockedHarvestNeverExposesProgress() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let tile = try #require(state.board.tiles.first { $0.kind == .resourceChoice })
        state.players[0].cities.insert(state.board.corners(of: tile.coordinate)[0])
        state.board.robberTile = tile.coordinate
        try NavalTestSupport.roll(try #require(tile.numberToken), player: 0, state: &state)
        #expect(Naval.harvestProgress(for: state.players[0].id, in: state) == nil)
    }

    private func harvest(settlements: Int, cities: Int) throws -> GameState {
        var state = try NavalTestSupport.ready(fog: false)
        let tile = try #require(state.board.tiles.first { $0.kind == .resourceChoice })
        let corners = state.board.corners(of: tile.coordinate)
        if settlements > 0 { state.players[0].settlements.insert(corners[0]) }
        if settlements > 1 { state.players[0].settlements.insert(corners[3]) }
        if cities > 0 { state.players[0].cities.insert(corners[3]) }
        try NavalTestSupport.roll(try #require(tile.numberToken), player: 0, state: &state)
        return state
    }
}
