import Foundation
import Testing
@testable import CatanEngine

struct NavalCaptureOptionTests {
    @Test func freshMatchesDisableStealingAndChoiceDoesNotAlterTheSeededWorld() throws {
        let off = Naval.newGame(seed: 73)
        let on = Naval.newGame(seed: 73, options: NavalOptions(shipStealingEnabled: true))
        #expect(off.naval?.options.shipStealingEnabled == false)
        #expect(on.naval?.options.shipStealingEnabled == true)
        #expect(off.board == on.board && off.rng == on.rng)
        let restored = try JSONDecoder().decode(GameState.self, from: JSONEncoder().encode(off))
        #expect(restored == off && restored.naval?.options.shipStealingEnabled == false)
    }

    @Test func explicitlyDisabledCaptureKeepsAnElevenAnOrdinaryProductionRoll() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let options = Data("{\"shipStealingEnabled\":false,\"fogEnabled\":false}".utf8)
        state.naval?.options = try JSONDecoder().decode(NavalOptions.self, from: options)
        let sea = try #require(state.board.tiles.last { $0.kind == .sea }?.coordinate)
        NavalTestSupport.addShip(at: sea, player: 1, in: &state)
        let before = state.players
        let events = try NavalTestSupport.roll(11, player: 0, state: &state)
        #expect(state.phase == .mainTurn(playerIndex: 0))
        #expect(state.naval?.capturePending == false)
        #expect(!RulesEngine.legalMoves(for: state).contains(.captureShip(id: 0)))
        #expect(events.contains(.rolled(PlayerID(index: 0), total: 11)))
        #expect(state.players != before, "Disabling capture must retain ordinary eleven production")
    }

    @Test func enabledCaptureTransfersControlAndSkippedCaptureKeepsTheHull() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let sea = try #require(state.board.tiles.last { $0.kind == .sea }?.coordinate)
        NavalTestSupport.addShip(at: sea, player: 1, steps: 0, in: &state)
        try NavalTestSupport.roll(11, player: 0, state: &state)
        let original = state.naval!.ships[0]
        #expect(state.phase == .capturingShip(playerIndex: 0))
        try RulesEngine.apply(.skipShipCapture, by: state.players[0].id, to: &state)
        #expect(state.naval?.ships[0] == original)
        try NavalTestSupport.roll(11, player: 0, state: &state)
        let stock = state.naval?.hullsBuilt
        try RulesEngine.apply(.captureShip(id: original.id), by: state.players[0].id, to: &state)
        #expect(state.naval?.ships[0].owner.index == 0)
        #expect(state.naval?.ships[0].coordinate == sea)
        #expect(state.naval?.hullsBuilt == stock && state.naval?.ships.count == 1)
        #expect(state.naval?.ships[0].stepsRemaining == Naval.movementPerTurn(in: state))
    }

    @Test func disabledCaptureCannotBeForgedIntoLegalMovesOrApplied() throws {
        var state = try NavalTestSupport.ready(fog: false)
        state.naval?.options.shipStealingEnabled = false
        let sea = try #require(state.board.tiles.last { $0.kind == .sea }?.coordinate)
        NavalTestSupport.addShip(at: sea, player: 1, in: &state)
        state.phase = .capturingShip(playerIndex: 0)
        state.lastDiceRoll = 11
        state.naval?.capturePending = true
        state.naval?.productionRollerIndex = 0
        let before = state
        #expect(RulesEngine.legalMoves(for: state).isEmpty)
        #expect(Naval.validationProblem(in: state) == "naval capture phase")
        #expect(throws: MoveError.self) { try RulesEngine.apply(.captureShip(id: 0), by: state.players[0].id, to: &state) }
        #expect(throws: MoveError.self) { try RulesEngine.apply(.skipShipCapture, by: state.players[0].id, to: &state) }
        #expect(state == before)
    }

    @Test(arguments: [false, true])
    func noOpposingHullLeavesNoPendingCapture(enabled: Bool) throws {
        var state = try NavalTestSupport.ready()
        state.naval?.options.shipStealingEnabled = enabled
        try NavalTestSupport.roll(11, player: 0, state: &state)
        #expect(state.phase == .mainTurn(playerIndex: 0))
        #expect(state.naval?.capturePending == false && state.naval?.productionRollerIndex == nil)
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test(arguments: [1, 2, 3, 4])
    func implicitLegacyCaptureSurvivesPendingCheckpointAndExactContinuation(version: Int) throws {
        var state = try NavalTestSupport.ready(fog: false, rulesVersion: version)
        state.naval?.options = try JSONDecoder().decode(NavalOptions.self, from: Data("{\"fogEnabled\":false}".utf8))
        let sea = try #require(state.board.tiles.last { $0.kind == .sea }?.coordinate)
        NavalTestSupport.addShip(at: sea, player: 1, in: &state)
        try NavalTestSupport.roll(11, player: 0, state: &state)
        let original = GameSession(state: state, policies: [:], policySeed: 1)
        let data = try JSONEncoder().encode(original.checkpoint)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: data)
        var restored = try GameSession(checkpoint: decoded, policies: [:])
        var expected = original
        let move = GameMove.captureShip(id: 0)
        let first = try expected.applyExternal(move, by: state.players[0].id)
        let second = try restored.applyExternal(move, by: state.players[0].id)
        #expect(first.events == second.events && expected.checkpoint == restored.checkpoint)
        #expect(restored.state.naval?.options.shipStealingEnabled == true)
    }

    @Test func legacyChoiceKeepsItsAbsenceUntilANewGameDraftIsNormalized() throws {
        var legacy = try JSONDecoder().decode(NavalOptions.self, from: Data("{}".utf8))
        #expect(legacy.shipStealingEnabled)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        #expect(encoded?["shipStealingEnabled"] == nil)
        legacy.normalizeForNewGame()
        #expect(!legacy.shipStealingEnabled)
        for enabled in [false, true] {
            var explicit = NavalOptions(shipStealingEnabled: enabled)
            explicit.normalizeForNewGame()
            let restored = try JSONDecoder().decode(NavalOptions.self, from: JSONEncoder().encode(explicit))
            #expect(restored == explicit && restored.shipStealingEnabled == enabled)
        }
    }
}
