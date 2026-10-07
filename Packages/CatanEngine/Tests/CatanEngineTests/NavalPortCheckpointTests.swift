import Foundation
import Testing
@testable import CatanEngine

private struct HarborCheckpointPolicy: Policy {
    let id = "harbor-checkpoint-first-legal"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove { observation.legalMoves[0] }
}

struct NavalPortCheckpointTests {
    @Test(arguments: [false, true])
    func legacyQueuedReplyResumesWithChartedHarborsWithoutResampling(nearHarbor: Bool) throws {
        let original = try fixture(nearHarbor: nearHarbor)
        let old = try legacyCheckpoint(original.checkpoint)
        try old.validate()
        var resumed = try GameSession(checkpoint: old, policies: original.policies)
        let before = try #require(old.queuedTradeResponse)
        let migrated = try #require(resumed.checkpoint.queuedTradeResponse)
        #expect(before.observation.state.board.ports.count == (nearHarbor ? 1 : 0))
        #expect(migrated.observation.state.board.ports.count == 4)
        #expect(migrated.observation == GameObservation(seat: before.seat, state: old.state,
                                                      legalMoves: before.observation.legalMoves))
        #expect(migrated.move == before.move && migrated.seat == before.seat)
        #expect(migrated.evaluationIndex == before.evaluationIndex)
        #expect(resumed.checkpoint.policyRNG == old.policyRNG)
        #expect(resumed.checkpoint.policyEvaluationCount == old.policyEvaluationCount)
        #expect(resumed.checkpoint.actionsThisTurn == old.actionsThisTurn)
        #expect(resumed.checkpoint.currentTurnSeat == old.currentTurnSeat)
        #expect(resumed.checkpoint.ledgers == old.ledgers)
        #expect(resumed.state == old.state)
        let encoded = try JSONEncoder().encode(resumed.checkpoint)
        #expect(try JSONDecoder().decode(GameSession.Checkpoint.self, from: encoded) == resumed.checkpoint)
        var uninterrupted = original
        _ = try resumed.step()
        _ = try uninterrupted.step()
        #expect(resumed.checkpoint == uninterrupted.checkpoint)
    }

    @Test(arguments: ["bank", "handCounts", "devCardCounts", "devCardDeckCount", "legalMoves", "seat", "move", "evaluationIndex", "partialPorts"])
    func legacyProjectionDoesNotPermitOtherQueuedReplyCorruption(field: String) throws {
        let original = try fixture()
        let legacy = try legacyCheckpoint(original.checkpoint)
        let malformed = try altered(legacy, field: field)
        #expect(throws: GameSession.CheckpointError.self) { try malformed.validate() }
        #expect(throws: GameSession.CheckpointError.self) {
            _ = try GameSession(checkpoint: malformed, policies: original.policies)
        }
    }

    private func fixture(nearHarbor: Bool = false) throws -> GameSession {
        var state = Naval.newGame(seed: 73)
        if nearHarbor {
            let port = state.board.ports[0]
            state.naval?.revealed.formUnion(Set(port.vertexA.touchingTiles).union(port.vertexB.touchingTiles))
        }
        state.phase = .mainTurn(playerIndex: 0)
        NavalTestSupport.fund([.brick: 1], in: &state)
        NavalTestSupport.fund([.grain: 1], player: 1, in: &state)
        let policies: [PlayerID: any Policy] = [state.players[1].id: HarborCheckpointPolicy()]
        var session = GameSession(state: state, policies: policies, policySeed: 123)
        let offer = TradeOffer(from: state.players[0].id, give: [.brick: 1], want: [.grain: 1])
        _ = try session.applyExternal(.proposeTrade(offer), by: state.players[0].id)
        return session
    }

    /// Build the pre-fix wire shape explicitly, so a future decoder cannot make
    /// the regression pass by writing today's projection on both sides.
    private func legacyCheckpoint(_ checkpoint: GameSession.Checkpoint) throws -> GameSession.Checkpoint {
        var object = try wireObject(checkpoint)
        let ports = checkpoint.state.board.ports.filter { port in
            Set(port.vertexA.touchingTiles).union(port.vertexB.touchingTiles).allSatisfy { coordinate in
                Naval.isRevealed(coordinate, in: checkpoint.state)
                    || !checkpoint.state.board.tiles.contains { $0.coordinate == coordinate }
            }
        }
        try replace(in: &object, path: ["queuedTradeResponse", "observation", "state", "board", "ports"], value: encoded(ports))
        return try decode(object)
    }

    private func altered(_ checkpoint: GameSession.Checkpoint, field: String) throws -> GameSession.Checkpoint {
        var object = try wireObject(checkpoint)
        let observation = ["queuedTradeResponse", "observation"]
        switch field {
        case "bank": try replace(in: &object, path: observation + ["state", "bank"], value: encoded([Resource: Int]()))
        case "handCounts", "devCardCounts": try replace(in: &object, path: observation + [field], value: [])
        case "devCardDeckCount": try replace(in: &object, path: observation + [field], value: 0)
        case "legalMoves": try replace(in: &object, path: observation + [field], value: [])
        case "seat": try replace(in: &object, path: ["queuedTradeResponse", "seat", "index"], value: 0)
        case "move":
            try replace(in: &object, path: ["queuedTradeResponse", "move"], value: encoded(GameMove.endTurn))
        case "evaluationIndex": try replace(in: &object, path: ["queuedTradeResponse", field], value: checkpoint.policyEvaluationCount)
        case "partialPorts":
            try replace(in: &object, path: observation + ["state", "board", "ports"], value: encoded([checkpoint.state.board.ports[0]]))
        default: preconditionFailure("Unknown checkpoint mutation")
        }
        return try decode(object)
    }

    private func wireObject(_ checkpoint: GameSession.Checkpoint) throws -> [String: Any] {
        try #require(encoded(checkpoint) as? [String: Any])
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func decode(_ object: [String: Any]) throws -> GameSession.Checkpoint {
        try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func replace(in object: inout [String: Any], path: [String], value: Any) throws {
        let key = try #require(path.first)
        if path.count == 1 {
            object[key] = value
            return
        }
        var child = try #require(object[key] as? [String: Any])
        try replace(in: &child, path: Array(path.dropFirst()), value: value)
        object[key] = child
    }
}
