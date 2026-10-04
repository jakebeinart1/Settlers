import Testing
import Foundation
import CatanAI
@testable import CatanEngine
@testable import Settlers

@MainActor @Suite(.serialized)
struct ExpertArchiveRevisionTests {
    @Test(arguments: [ExpertRevision.legacy, .cityProductionV1])
    func archiveKeepsPolicyProvenanceAndRecordedReplay(revision: ExpertRevision) throws {
        let fixture = try CheckpointModelFixture()
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 741)
        let setup = MatchSetup(seats: state.players.map { player in
            let civilization = Civilization.allCases[player.id.index]
            return MatchSetup.Seat(index: player.id.index, isHuman: player.id.index == 0,
                name: player.id.index == 0 ? "Alex" : "", civilization: civilization,
                opponentProfile: player.id.index == 0 ? nil : .forCivilization(civilization))
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false,
            difficulty: .expert, expertRevision: revision)
        var match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        let move = try #require(RulesEngine.legalMoves(for: state, seat: state.players[0].id).first)
        try match.apply(move, by: state.players[0].id)
        let url = try fixture.logStore.export(checkpoint: match)
        let detail = try fixture.logStore.detail(for: url)
        #expect(detail.roster.expertRevision == revision)
        var replay = detail.initialState
        for event in detail.events { try RulesEngine.apply(event.move, by: event.player, to: &replay) }
        #expect(replay == match.state)
    }

    @Test func oldArchiveRosterAndClassicDifficultyHaveNoExpertRevision() throws {
        let old = GameLogStore.SeatRoster.legacy(humanSeat: PlayerID(index: 0))
        let data = try JSONEncoder().encode(old)
        let wire = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(wire["expertRevision"] == nil)
        #expect(try JSONDecoder().decode(GameLogStore.SeatRoster.self, from: data).expertRevision == nil)
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 741)
        let setup = MatchSetup(seats: state.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: true, name: "P\(player.id.index)",
                civilization: Civilization.allCases[player.id.index])
        }, victoryPointTarget: 10, randomizedBoard: false, randomizeSeatOrder: false, difficulty: .classic)
        let fixture = try CheckpointModelFixture()
        let match = MatchCheckpoint(id: UUID(), initialState: state, setup: setup)
        let url = try fixture.logStore.export(checkpoint: match)
        #expect(try fixture.logStore.detail(for: url).roster.expertRevision == nil)
    }
}
