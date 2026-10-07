import Foundation
import Testing
@testable import CatanEngine

struct TradeCompetitionTests {
    @Test(arguments: [3, 4])
    func twoAcceptingRecipientsHaveEqualOddsInEveryHumanChair(playerCount: Int) throws {
        for humanIndex in 0..<playerCount {
            let human = PlayerID(index: humanIndex)
            let proposer = PlayerID(index: (humanIndex + 1) % playerCount)
            let rival = PlayerID(index: (humanIndex + 2) % playerCount)
            let state = position(playerCount: playerCount, proposer: proposer)
            var wins: [PlayerID: Int] = [:]
            let samples = 256
            for seed in 0..<samples {
                var (session, offer) = try proposal(state, human: human, acceptedSeats: [rival], seed: UInt64(seed))
                let step = try session.acceptTrade(offerID: offer.id, by: human)
                wins[step.actor, default: 0] += 1
                #expect(step.actor == human || step.actor == rival)
            }
            // Fixed seeds make this a stable distribution check, not a flake
            // driven by system randomness. First-seat priority fails at 100%.
            #expect(Set(wins.keys) == [human, rival])
            #expect((samples * 2 / 5...samples * 3 / 5).contains(wins[human, default: 0]))
        }
    }

    @Test func threeAcceptingRecipientsAllParticipateWithoutChangingEngineRandomness() throws {
        let human = PlayerID(index: 0), proposer = PlayerID(index: 1)
        let rivals = Set([PlayerID(index: 2), PlayerID(index: 3)])
        let state = position(playerCount: 4, proposer: proposer)
        var wins: [PlayerID: Int] = [:]
        for seed in 0..<256 {
            var (session, offer) = try proposal(state, human: human, acceptedSeats: rivals, seed: UInt64(seed))
            let before = session.state
            let step = try session.acceptTrade(offerID: offer.id, by: human)
            wins[step.actor, default: 0] += 1
            try requireExchange(step, offer: offer, before: before, after: session.state)
        }
        #expect(Set(wins.keys) == rivals.union([human]))
        #expect(wins.values.allSatisfy { (60...110).contains($0) })
    }

    @Test func fundedRejectionAndUnfundedWillingnessNeverReduceTheHumansChance() throws {
        let human = PlayerID(index: 0), proposer = PlayerID(index: 1)
        var state = position(playerCount: 4, proposer: proposer)
        let unfunded = PlayerID(index: 3)
        state.players[unfunded.index].resources = [:]
        restoreBank(in: &state)
        let declining = TradeCompetitionPolicy(accepts: false)
        let willing = TradeCompetitionPolicy(accepts: true)
        let policies: [PlayerID: any Policy] = [proposer: declining, PlayerID(index: 2): declining, unfunded: willing]
        var session = GameSession(state: state, policies: policies, policySeed: 9)
        let offer = exchange(from: proposer)
        _ = try session.commit(seat: proposer, move: .proposeTrade(offer))
        let before = session.checkpoint
        let step = try session.acceptTrade(offerID: offer.id, by: human)
        #expect(step.actor == human)
        #expect(session.policyRNG == before.policyRNG, "a sole accepter requires no lottery")
        #expect(session.lastPolicyDecisions.count == 2)
        #expect(willing.observations.first?.legalMoves == [.respondToTrade(offerID: offer.id, accept: false)])
        try requireExchange(step, offer: offer, before: before.state, after: session.state)
    }

    @Test func alreadyQueuedReplyIsReusedAndReportedOnce() throws {
        let human = PlayerID(index: 0), proposer = PlayerID(index: 1), rival = PlayerID(index: 2)
        let policy = TradeCompetitionPolicy(accepts: true, consumesRandomness: true)
        let policies: [PlayerID: any Policy] = [proposer: policy, rival: policy]
        var original = GameSession(state: position(playerCount: 3, proposer: proposer), policies: policies, policySeed: 7)
        let offer = exchange(from: proposer)
        _ = try original.commit(seat: proposer, move: .proposeTrade(offer))
        let saved = original.checkpoint
        let accept = GameMove.respondToTrade(offerID: offer.id, accept: true)
        let cached = GameSession.Decision(evaluationIndex: 0, seat: rival, move: accept,
                                         observation: GameObservation(seat: rival, state: saved.state,
                                                                      legalMoves: [accept, .respondToTrade(offerID: offer.id, accept: false)]))
        let checkpoint = GameSession.Checkpoint(version: saved.version, state: saved.state,
            policyIDs: saved.policyIDs, policyRNG: saved.policyRNG, policyEvaluationCount: 1,
            queuedTradeResponse: cached, currentTurnSeat: saved.currentTurnSeat,
            actionsThisTurn: saved.actionsThisTurn, ledgers: saved.ledgers)
        var session = try GameSession(checkpoint: checkpoint, policies: policies)
        _ = try session.acceptTrade(offerID: offer.id, by: human)
        #expect(policy.observations.isEmpty, "a stored decision must not be sampled again")
        #expect(session.policyEvaluationCount == 1)
        #expect(session.lastPolicyDecisions == [cached])
        #expect(session.checkpoint.queuedTradeResponse == nil)
        _ = try session.applyExternal(.endTurn, by: proposer)
        #expect(session.lastPolicyDecisions.isEmpty)
    }

    @Test func coldPendingCheckpointResolvesIdenticallyAndOrdinaryResponseReplaysExactly() throws {
        let human = PlayerID(index: 0), proposer = PlayerID(index: 1), rival = PlayerID(index: 2)
        var (original, offer) = try proposal(position(playerCount: 3, proposer: proposer), human: human,
                                            acceptedSeats: [rival], seed: 91)
        let bytes = try JSONEncoder().encode(original.checkpoint)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: bytes)
        var resumed = try GameSession(checkpoint: decoded, policies: original.policies)
        let expected = try original.acceptTrade(offerID: offer.id, by: human)
        let actual = try resumed.acceptTrade(offerID: offer.id, by: human)
        #expect(actual.actor == expected.actor)
        #expect(actual.move == expected.move)
        #expect(resumed.checkpoint == original.checkpoint)
        var replay = decoded.state
        let events = try RulesEngine.replay(actual.move, by: actual.actor,
                                            rulesVersion: RulesEngine.currentRulesVersion, to: &replay)
        #expect(replay == resumed.state)
        #expect(events == actual.events)
        try resumed.checkpoint.validate()
    }

    @Test func competitorsReceiveMaskedNavalObservations() throws {
        let human = PlayerID(index: 0), proposer = PlayerID(index: 1), rival = PlayerID(index: 2)
        var state = try NavalTestSupport.ready(playerCount: 3)
        state.phase = .mainTurn(playerIndex: proposer.index)
        for index in state.players.indices { state.players[index].resources = index == proposer.index ? [.brick: 2] : [.grain: 2] }
        restoreBank(in: &state)
        let policy = TradeCompetitionPolicy(accepts: true)
        var session = GameSession(state: state, policies: [proposer: policy, rival: policy], policySeed: 7)
        let offer = exchange(from: proposer)
        _ = try session.commit(seat: proposer, move: .proposeTrade(offer))
        _ = try session.acceptTrade(offerID: offer.id, by: human)
        let observed = try #require(policy.observations.first)
        #expect(observed.seat == rival)
        #expect(observed.state.players[rival.index].resources == [.grain: 2])
        #expect(observed.state.players[human.index].resources.isEmpty)
        #expect(observed.state.players[proposer.index].resources.isEmpty)
        #expect(observed.state == Naval.observationState(session.lastPolicyDecisions[0].observation.state, for: rival))
    }

    @Test func humanProposalsAndOrdinaryAutomatedQueueKeepTheirSelectedRecipient() throws {
        let human = PlayerID(index: 0), proposer = PlayerID(index: 1)
        var state = position(playerCount: 3, proposer: human)
        let policy = TradeCompetitionPolicy(accepts: true)
        var session = GameSession(state: state, policies: [proposer: policy, PlayerID(index: 2): policy], policySeed: 7)
        let humanOffer = exchange(from: human)
        _ = try session.applyExternal(.proposeTrade(humanOffer), by: human)
        let queued = try #require(session.checkpoint.queuedTradeResponse)
        #expect(queued.seat == proposer)
        let cursor = session.policyRNG
        let step = try session.acceptTrade(offerID: humanOffer.id, by: proposer)
        #expect(step.actor == proposer)
        #expect(session.policyRNG == cursor)
        state = position(playerCount: 3, proposer: proposer)
        let allPolicies = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, policy as any Policy) })
        var automated = GameSession(state: state, policies: allPolicies, policySeed: 7)
        let botOffer = exchange(from: proposer)
        _ = try automated.commit(seat: proposer, move: .proposeTrade(botOffer))
        #expect(automated.checkpoint.queuedTradeResponse?.seat == human, "the existing all-bot first reply is unchanged")
    }

    private func position(playerCount: Int, proposer: PlayerID) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 41, playerCount: playerCount)
        state.phase = .mainTurn(playerIndex: proposer.index)
        for index in state.players.indices { state.players[index].resources = index == proposer.index ? [.brick: 2] : [.grain: 2] }
        restoreBank(in: &state)
        return state
    }

    private func proposal(_ state: GameState, human: PlayerID, acceptedSeats: Set<PlayerID>,
                          seed: UInt64) throws -> (GameSession, TradeOffer) {
        let proposer = state.players[state.phase.awaitingSeatIndex!].id
        let policies = Dictionary(uniqueKeysWithValues: state.players.filter { $0.id != human }.map {
            ($0.id, TradeCompetitionPolicy(accepts: acceptedSeats.contains($0.id)) as any Policy)
        })
        var session = GameSession(state: state, policies: policies, policySeed: seed)
        let offer = exchange(from: proposer)
        _ = try session.commit(seat: proposer, move: .proposeTrade(offer))
        return (session, offer)
    }

    private func exchange(from proposer: PlayerID) -> TradeOffer {
        TradeOffer.enumerated(from: proposer, give: [.brick: 1], want: [.grain: 1])
    }

    private func restoreBank(in state: inout GameState) {
        for resource in Resource.allCases {
            state.bank[resource] = state.rules.bankPerResource - state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
        }
    }

    private func requireExchange(_ step: GameSession.Step, offer: TradeOffer, before: GameState, after: GameState) throws {
        #expect(step.move == .respondToTrade(offerID: offer.id, accept: true))
        #expect(step.events == [.acceptedTrade(step.actor, from: offer.from, gave: offer.want, got: offer.give)])
        #expect(after.pendingTradeOffers.isEmpty)
        #expect(after.tradesAcceptedThisTurn[offer.from] == 1)
        #expect(after.bank == before.bank)
        #expect(after.rng == before.rng)
        for player in before.players {
            var expected = player.resources
            if player.id == offer.from { expected[.brick, default: 0] -= 1; expected[.grain, default: 0] += 1 }
            if player.id == step.actor { expected[.grain, default: 0] -= 1; expected[.brick, default: 0] += 1 }
            #expect(after.players[player.id.index].resources == expected)
        }
    }
}

private final class TradeCompetitionPolicy: Policy, @unchecked Sendable {
    let id = "trade-competition-fixture"
    private let accepts: Bool
    private let consumesRandomness: Bool
    private let lock = NSLock()
    private var recordedObservations: [GameObservation] = []

    init(accepts: Bool, consumesRandomness: Bool = false) {
        self.accepts = accepts
        self.consumesRandomness = consumesRandomness
    }

    var observations: [GameObservation] {
        lock.lock()
        defer { lock.unlock() }
        return recordedObservations
    }

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        lock.lock()
        recordedObservations.append(observation)
        lock.unlock()
        if consumesRandomness { _ = rng.next() }
        return accepts ? observation.legalMoves[0] : observation.legalMoves.last!
    }
}
