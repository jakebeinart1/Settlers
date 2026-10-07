import Foundation
import Testing
@testable import CatanEngine

struct NavalProductionValidationTests {
    @Test(arguments: ["maximum", "overYield", "wrongRoll", "captureFlag", "missingLater", "reordered", "partialLater", "emptyBank", "wrongPhaseSeat"])
    func impossibleChoiceObligationsAreRejected(corruption: String) throws {
        var state = try choiceState()
        #expect(Naval.validationProblem(in: state) == nil)
        switch corruption {
        case "maximum": state.naval?.pendingResourceChoices[0].remaining = Int.max
        case "overYield": state.naval?.pendingResourceChoices[0].remaining = 3
        case "wrongRoll": state.lastDiceRoll = 11
        case "captureFlag": state.naval?.capturePending = true
        case "missingLater": state.naval?.pendingResourceChoices.removeLast()
        case "reordered": state.naval?.pendingResourceChoices.swapAt(1, 2)
        case "partialLater": state.naval?.pendingResourceChoices[1].remaining = 1
        case "emptyBank": state.bank = [:]
        default: state.phase = .choosingResource(playerIndex: 1)
        }
        let checkpoint = GameSession(state: state, policies: [:], policySeed: 1).checkpoint
        #expect(throws: GameSession.CheckpointError.self) { try checkpoint.validate() }
    }

    @Test func everyPartialChoiceAndClockwiseSuffixSurvivesColdCheckpoint() throws {
        var state = try choiceState()
        let seats = [0, 0, 1, 1, 2]
        for index in seats {
            let checkpoint = GameSession(state: state, policies: [:], policySeed: 1).checkpoint
            try checkpoint.validate()
            let restored = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(checkpoint))
            try restored.validate()
            #expect(restored == checkpoint)
            try RulesEngine.apply(.chooseResource(.ore), by: state.players[index].id, to: &state)
        }
        #expect(state.phase == .mainTurn(playerIndex: 3))
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test func captureRequiresElevenButAResolvedElevenHasNoPendingCapture() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let launch = try #require(Naval.launchSites(for: state.players[0].id, in: state).first)
        NavalTestSupport.addShip(at: launch, player: 1, in: &state)
        try NavalTestSupport.roll(11, player: 0, state: &state)
        #expect(state.phase == .capturingShip(playerIndex: 0))
        #expect(Naval.validationProblem(in: state) == nil)
        var corrupt = state
        corrupt.lastDiceRoll = 4
        #expect(Naval.validationProblem(in: corrupt) != nil)
        corrupt = state
        corrupt.naval?.capturePending = false
        #expect(Naval.validationProblem(in: corrupt) != nil)
        try RulesEngine.apply(.skipShipCapture, by: state.players[0].id, to: &state)
        #expect(state.lastDiceRoll == 11)
        #expect(Naval.validationProblem(in: state) == nil)
    }

    private func choiceState() throws -> GameState {
        var state = try NavalTestSupport.ready(fog: false)
        let tile = try #require(state.board.tiles.first { $0.kind == .resourceChoice })
        let corners = state.board.corners(of: tile.coordinate)
        state.players[0].cities.insert(corners[0])
        state.players[1].cities.insert(corners[2])
        state.players[2].settlements.insert(corners[4])
        try NavalTestSupport.roll(try #require(tile.numberToken), player: 3, state: &state)
        #expect(state.naval?.pendingResourceChoices == [NavalResourceChoice(playerIndex: 0, remaining: 2),
                                                      NavalResourceChoice(playerIndex: 1, remaining: 2),
                                                      NavalResourceChoice(playerIndex: 2, remaining: 1)])
        return state
    }
}
