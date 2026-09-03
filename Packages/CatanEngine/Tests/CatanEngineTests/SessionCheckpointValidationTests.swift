import Foundation
import Testing
import CatanEngine

private struct ValidationCheckpointPolicy: Policy {
    let id = "checkpoint-validation-first-legal"

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves[0]
    }
}

@Suite struct SessionCheckpointValidationTests {
    private let gameSeed: UInt64 = 971
    private let policySeed: UInt64 = 817

    @Test func legitimateDecodedSnapshotsResume() throws {
        for queuedTrade in [false, true] {
            let original = try fixture(queuedTrade: queuedTrade)
            let checkpoint = try decoded(original)
            var resumed = try GameSession(checkpoint: checkpoint, policies: original.policies)
            #expect(resumed.checkpoint == original.checkpoint)
            if queuedTrade {
                let sampled = resumed.decideNextDetailed()
                let decision = try #require(sampled)
                #expect(decision.seat == PlayerID(index: 1))
                _ = try resumed.commit(seat: decision.seat, move: decision.move)
                #expect(resumed.state.pendingTradeOffers.isEmpty)
            }
        }
    }

    @Test(arguments: [-1, GameSetup.standardPlayerCount])
    func rejectsInvalidCurrentTurnSeat(index: Int) throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: ["currentTurnSeat", "index"], with: index)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test(arguments: [-1, GameSetup.standardPlayerCount])
    func rejectsInvalidQueuedResponseActor(index: Int) throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: ["queuedTradeResponse", "seat", "index"], with: index)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsQueuedResponseFromProposer() throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: ["queuedTradeResponse", "seat", "index"], with: 0)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsQueuedResponseWithoutActorPolicy() throws {
        var original = try fixture(queuedTrade: true)
        // Keep the serialized roster and supplied policies identical: this is
        // a queued-actor violation, not the existing policy-ID mismatch check.
        original.policies.removeValue(forKey: PlayerID(index: 1))
        let checkpoint = try decoded(original)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsQueuedResponseWithoutPendingOffer() throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: ["state", "pendingTradeOffers"], with: [])
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsQueuedResponseToUnknownOffer() throws {
        let original = try fixture(queuedTrade: true)
        let absentID = "00000000-0000-0000-0000-000000000001"
        #expect(!original.state.pendingTradeOffers.contains { $0.id.uuidString == absentID })
        let checkpoint = try decoded(original,
                                     replacing: ["queuedTradeResponse", "move", "respondToTrade", "offerID"],
                                     with: absentID)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsQueuedNonResponseMove() throws {
        let original = try fixture(queuedTrade: true)
        let move = try JSONSerialization.jsonObject(with: JSONEncoder().encode(GameMove.endTurn))
        let checkpoint = try decoded(original, replacing: ["queuedTradeResponse", "move"], with: move)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test(arguments: ["setupForward", "setupBackward", "rollDice", "mainTurn", "movingRobber"],
          [-1, GameSetup.standardPlayerCount])
    func rejectsInvalidPhasePlayerIndex(phase: String, index: Int) throws {
        let original = try fixture()
        let checkpoint = try decoded(original, replacing: ["state", "phase"],
                                     with: [phase: ["playerIndex": index]])
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test(arguments: ["actionsThisTurn", "policyEvaluationCount"])
    func rejectsNegativeCounters(field: String) throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: [field], with: -1)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test(arguments: ["actionsThisTurn", "policyEvaluationCount"])
    func rejectsCountersThatCannotAdvanceWithoutOverflow(field: String) throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: [field], with: Int.max)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test(arguments: [GameSession.maxActionsPerTurn + 1, 1_000_000])
    func rejectsActionsBeyondTurnBackstop(actions: Int) throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: ["actionsThisTurn"], with: actions)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsActionsWithoutACurrentTurnSeat() throws {
        let original = try fixture(queuedTrade: true)
        var checkpoint = try decoded(original, replacing: ["currentTurnSeat"])
        checkpoint = try decoded(checkpoint, replacing: ["actionsThisTurn"], with: 1)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsCurrentTurnSeatWithoutActions() throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: ["actionsThisTurn"], with: 0)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func acceptsCheckpointAtTurnBackstop() throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(
            original, replacing: ["actionsThisTurn"], with: GameSession.maxActionsPerTurn
        )

        _ = try GameSession(checkpoint: checkpoint, policies: original.policies)
    }

    @Test(arguments: [-1, 1, 2])
    func rejectsQueuedEvaluationOutsideRecordedRange(index: Int) throws {
        let original = try fixture(queuedTrade: true)
        #expect(original.policyEvaluationCount == 1)
        let checkpoint = try decoded(original, replacing: ["queuedTradeResponse", "evaluationIndex"], with: index)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsZeroEvaluationsWithQueuedDecision() throws {
        let original = try fixture(queuedTrade: true)
        let checkpoint = try decoded(original, replacing: ["policyEvaluationCount"], with: 0)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test(arguments: [-1, 0, 2])
    func rejectsUnsupportedCheckpointVersion(version: Int) throws {
        let original = try fixture()
        let checkpoint = try decoded(original, replacing: ["version"], with: version)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test(arguments: [-1, GameState.currentSchemaVersion + 1])
    func rejectsUnsupportedStateSchema(version: Int) throws {
        let original = try fixture()
        let checkpoint = try decoded(original, replacing: ["state", "schemaVersion"], with: version)
        expectRejected(checkpoint, policies: original.policies)
    }

    @Test func rejectsChangedPolicyRosterAfterDecoding() throws {
        let original = try fixture()
        let checkpoint = try decoded(original)
        expectRejected(checkpoint, policies: [:])
    }

    private func fixture(queuedTrade: Bool = false) throws -> GameSession {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: gameSeed)
        if queuedTrade {
            state.phase = .mainTurn(playerIndex: 0)
            state.players[0].resources = [.brick: 1]
            state.players[1].resources = [.grain: 1]
            state.bank[.brick, default: 0] -= 1
            state.bank[.grain, default: 0] -= 1
        }
        let policies = Dictionary(uniqueKeysWithValues: state.players.map {
            ($0.id, ValidationCheckpointPolicy() as any Policy)
        })
        var session = GameSession(state: state, policies: policies, policySeed: policySeed)
        if queuedTrade {
            let offer = TradeOffer(from: state.players[0].id, give: [.brick: 1], want: [.grain: 1])
            _ = try session.commit(seat: state.players[0].id, move: .proposeTrade(offer))
        }
        return session
    }

    /// Mutate the wire representation, keeping decode errors outside the
    /// rejection assertion so they cannot masquerade as initializer validation.
    private func decoded(_ session: GameSession, replacing path: [String] = [],
                         with value: Any = NSNull()) throws -> GameSession.Checkpoint {
        let data = try JSONEncoder().encode(session.checkpoint)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        if !path.isEmpty { try replace(in: &object, path: path[...], with: value) }
        let mutated = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(GameSession.Checkpoint.self, from: mutated)
    }

    private func decoded(_ checkpoint: GameSession.Checkpoint, replacing path: [String],
                         with value: Any) throws -> GameSession.Checkpoint {
        let data = try JSONEncoder().encode(checkpoint)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try replace(in: &object, path: path[...], with: value)
        let mutated = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(GameSession.Checkpoint.self, from: mutated)
    }

    private func replace(in object: inout [String: Any], path: ArraySlice<String>, with value: Any) throws {
        let key = try #require(path.first)
        _ = try #require(object[key])
        if path.count == 1 {
            object[key] = value
            return
        }
        var child = try #require(object[key] as? [String: Any])
        try replace(in: &child, path: path.dropFirst(), with: value)
        object[key] = child
    }

    private func expectRejected(_ checkpoint: GameSession.Checkpoint,
                                policies: [PlayerID: any Policy],
                                sourceLocation: SourceLocation = #_sourceLocation) {
        // Do not call nextActor/step on malformed state: rejection must happen
        // before an unchecked index or overflowing increment can trap.
        #expect(throws: GameSession.CheckpointError.self, sourceLocation: sourceLocation) {
            _ = try GameSession(checkpoint: checkpoint, policies: policies)
        }
    }
}
