import Foundation
import Testing
@testable import CatanEngine

/// Save acknowledgement compares decoded checkpoints with the in-memory
/// candidate. Zero-valued ledger entries must not disappear during encoding.
@Suite struct PublicLedgerCheckpointTests {
    @Test(arguments: [0, 2])
    func positionOnlyZeroHoldingsSurviveCheckpointRoundTrip(oreCount: Int) throws {
        var state = newGame()
        let observer = state.players[0].id
        state.players[0].resources = [.ore: oreCount, .wool: 0]
        let ledger = PublicLedger.fromPositionAlone(state, observer: observer)

        #expect(ledger.belief(of: observer).known.values.allSatisfy { $0 > 0 })
        #expect(ledger.belief(of: observer).maxTotal == oreCount)
        #expect(ledger.belief(of: observer).known[.ore, default: 0] == oreCount)
        let restored = try JSONDecoder().decode(PublicLedger.self, from: JSONEncoder().encode(ledger))
        #expect(restored == ledger)
        try expectCheckpointRoundTrip(GameSession(state: state, policies: [:], policySeed: 3))
    }

    @Test(arguments: [false, true])
    func monopolySurvivesCheckpointRoundTrip(external: Bool) throws {
        var state = newGame()
        let actor = state.players[0].id
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].devCards = [.monopoly]
        state.players[1].resources = [.wool: 2, .ore: 1]
        state.bank[.wool, default: 0] -= 2
        state.bank[.ore, default: 0] -= 1
        var session = GameSession(state: state, policies: [:], policySeed: 3)
        try expectCheckpointRoundTrip(session)

        if external {
            _ = try session.applyExternal(.playMonopoly(.wool), by: actor)
        } else {
            _ = try session.commit(seat: actor, move: .playMonopoly(.wool))
        }

        #expect(session.state.players[0].resources[.wool] == 2)
        #expect(session.state.players[1].resources[.wool, default: 0] == 0)
        try expectCheckpointRoundTrip(session)
    }

    private func newGame() -> GameState {
        GameSetup.newGame(board: BoardGenerator.randomized(seed: 3), seed: 3)
    }

    private func expectCheckpointRoundTrip(_ session: GameSession) throws {
        let checkpoint = session.checkpoint
        try checkpoint.validate()
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: data)
        #expect(decoded == checkpoint, "save read-back must equal the committed candidate")
        let resumed = try GameSession(checkpoint: decoded, policies: [:])
        #expect(resumed.checkpoint == checkpoint)
    }
}
