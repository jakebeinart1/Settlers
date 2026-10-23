import Foundation
import Testing
import CatanEngine
@testable import Settlers

/// The Auto Robber setting places the human's post-seven robber through the
/// real checkpoint/session path, and does not file it as a human decision.
@MainActor
@Suite(.serialized)
struct AutoRobberTests {
    private let human = PlayerID(index: 0)
    private let leader = PlayerID(index: 1)

    private func installRobberDecision(in fixture: CheckpointModelFixture) throws -> (GameViewModel, VertexID) {
        let model = fixture.makeModel()
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33, playerCount: 3)
        let corner = try #require(state.board.onBoardVertices.sorted().first {
            !$0.touchingTiles.contains(state.board.robberTile)
        })
        state.players[leader.index].settlements.insert(corner)
        state.players[leader.index].resources = [.ore: 2]
        state.bank[.ore] = 17
        state.phase = .movingRobber(playerIndex: human.index)
        model.replaceStateForTesting(state, humanSeat: human)
        return (model, corner)
    }

    @Test func placesTheHumansRobberOnAnOpponentAndSteals() async throws {
        let preferences = PacingPreferences.shared
        preferences.setAutoRobber(true)
        defer { preferences.setAutoRobber(false) }
        let fixture = try CheckpointModelFixture()
        let (model, corner) = try installRobberDecision(in: fixture)

        await model.runBotTurnIfNeeded()

        #expect(model.state.phase == .mainTurn(playerIndex: human.index))
        #expect(corner.touchingTiles.contains(model.state.board.robberTile), "the only opponent's tile")
        let last = try #require(model.checkpointDocument?.activeMatch?.moves.last)
        #expect(last.move == .moveRobber(model.state.board.robberTile, stealFrom: leader))
        #expect(!last.isHumanDecision, "an automatic move must not train the human's ghost")
    }

    @Test func leavesTheRobberToTheHumanWhenOff() async throws {
        let fixture = try CheckpointModelFixture()
        let (model, _) = try installRobberDecision(in: fixture)

        await model.runBotTurnIfNeeded()

        #expect(model.state.phase == .movingRobber(playerIndex: human.index))
    }
}
