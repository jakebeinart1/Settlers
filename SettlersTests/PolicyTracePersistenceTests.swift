import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct PolicyTracePersistenceTests {
    @Test func actualNeuralMovesSurviveCheckpointResumeAndExport() async throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var setup = fixture.setup
        setup.seats[0].isHuman = false
        setup.seats[0].name = ""
        setup.seats[1].isHuman = true
        setup.seats[1].name = "Alex"
        model.startNewGame(setup: setup)
        await model.runBotTurnIfNeeded()

        let match = try #require(model.checkpointDocument?.activeMatch)
        #expect(match.moves.count == 2, "the bot must actually place its settlement and road")
        for record in match.moves {
            let trace = try #require(record.policyTrace)
            #expect(trace.policyID.hasPrefix("upstream-r2-hybrid-"))
            #expect(trace.selection.source == "neural")
            #expect(trace.selection.fallbackReason == nil)
            #expect(trace.selection.move == record.move)
        }
        let resumed = fixture.makeModel()
        #expect(resumed.checkpointDocument?.activeMatch?.moves == match.moves)
        #expect(resumed.session.checkpoint == model.session.checkpoint)
        let summary = try #require(fixture.logStore.summaries().first)
        let detail = try fixture.logStore.detail(for: summary)
        #expect(detail.events.map(\.policyTrace) == match.moves.map(\.policyTrace))
    }

    @Test func oldRecordedMoveDoesNotInventNeuralProvenance() throws {
        let record = MatchCheckpoint.RecordedMove(actor: PlayerID(index: 0), move: .rollDice,
                                                  timestamp: Date(timeIntervalSince1970: 0))
        let wire = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        #expect(object["policyTrace"] == nil)
        #expect(try JSONDecoder().decode(MatchCheckpoint.RecordedMove.self, from: wire).policyTrace == nil)
    }

    @Test func humanOfferRejectedByEveryBotPersistsTheActualHeuristicRoute() throws {
        let fixture = try CheckpointModelFixture()
        let model = tradeModel(fixture: fixture, accepts: false)
        let before = model.session.checkpoint
        let offer = TradeOffer(from: model.humanPlayer, give: [.grain: 4], want: [.brick: 1])
        try model.apply(.proposeTrade(offer))

        #expect(model.pendingTradeConfirmation == nil)
        let outcome = try #require(model.lastTradeOutcome)
        #expect(outcome.decisions.count == 2)
        #expect(outcome.decisions.allSatisfy { !$0.accepted })
        #expect(model.state.pendingTradeOffers.isEmpty)
        try expectDurableTradeTrace(model: model, fixture: fixture, offer: offer, accepted: false, before: before)
    }

    @Test func acceptedHumanOfferConfirmedAfterReloadPersistsAcceptanceWithoutAdvancingRNG() throws {
        let fixture = try CheckpointModelFixture()
        let model = tradeModel(fixture: fixture)
        let before = model.session.checkpoint
        let offer = TradeOffer(from: model.humanPlayer, give: [.grain: 4], want: [.brick: 1])
        try model.apply(.proposeTrade(offer))
        let pending = try #require(model.pendingTradeConfirmation)
        #expect(pending.decisions.contains { $0.bot == pending.selectedBot && $0.accepted })

        let resumed = fixture.makeModel()
        resumed.isBlockingSurfaceOpen = true
        #expect(resumed.pendingTradeConfirmation?.selectedBot == pending.selectedBot)
        #expect(resumed.confirmPendingTrade() == .succeeded)
        #expect(resumed.state.players[0].resources[.brick] == 1)
        #expect(resumed.state.pendingTradeOffers.isEmpty)
        try expectDurableTradeTrace(model: resumed, fixture: fixture, offer: offer, accepted: true, before: before)
    }

    @Test func humanCancellationAfterReloadDoesNotBecomeAnAIRejection() throws {
        let fixture = try CheckpointModelFixture()
        let model = tradeModel(fixture: fixture)
        let before = model.session.checkpoint
        let offer = TradeOffer(from: model.humanPlayer, give: [.grain: 4], want: [.brick: 1])
        try model.apply(.proposeTrade(offer))
        _ = try #require(model.pendingTradeConfirmation)

        let resumed = fixture.makeModel()
        resumed.isBlockingSurfaceOpen = true
        _ = try #require(resumed.pendingTradeConfirmation)
        resumed.declinePendingTrade()
        #expect(resumed.state.pendingTradeOffers.isEmpty)
        #expect(resumed.state.players.map(\.resources) == before.state.players.map(\.resources))
        try expectDurableTradeTrace(model: resumed, fixture: fixture, offer: offer, accepted: true,
                                   before: before, sessionOverride: "humanCancelledTrade")
    }

    @Test func resourcesSpentAfterAcceptanceRecordCleanupRatherThanAIRejection() throws {
        let fixture = try CheckpointModelFixture()
        let model = tradeModel(fixture: fixture)
        let before = model.session.checkpoint
        let offer = TradeOffer(from: model.humanPlayer, give: [.grain: 4], want: [.brick: 1])
        try model.apply(.proposeTrade(offer))
        _ = try #require(model.pendingTradeConfirmation)
        try model.apply(.bankTrade(give: [.grain: 4], get: [.ore: 1]))
        #expect(model.checkpointDocument?.activeMatch?.moves.last?.policyTrace == nil)

        #expect(model.confirmPendingTrade() == .resourcesNoLongerAvailable)
        #expect(model.state.pendingTradeOffers.isEmpty)
        #expect(model.state.players[0].resources[.grain] == 2)
        #expect(model.state.players[0].resources[.ore] == 1)
        try expectDurableTradeTrace(model: model, fixture: fixture, offer: offer, accepted: true,
                                   before: before, sessionOverride: "resourcesNoLongerAvailable")
    }

    @Test func traceDecodingPreservesOldNumericIndicesAndOmitsExternalIndices() throws {
        let trace = PolicyTrace(evaluationIndex: 7, policyID: "recorded-policy",
                                selection: PolicySelection(move: .endTurn, source: "policy"))
        let wire = try JSONEncoder().encode(trace)
        #expect(try JSONDecoder().decode(PolicyTrace.self, from: wire) == trace)
        var object = try #require(JSONSerialization.jsonObject(with: wire) as? [String: Any])
        object.removeValue(forKey: "evaluationIndex")
        let external = try JSONDecoder().decode(PolicyTrace.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(external.evaluationIndex == nil)
        let externalWire = try JSONEncoder().encode(external)
        let encoded = try #require(JSONSerialization.jsonObject(with: externalWire) as? [String: Any])
        #expect(encoded["evaluationIndex"] == nil)
    }

    private func tradeModel(fixture: CheckpointModelFixture, accepts: Bool = true) -> GameViewModel {
        let model = fixture.makeModel()
        var position = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33, playerCount: 3)
        position.phase = .mainTurn(playerIndex: 0)
        position.players[0].resources = [.grain: 6]
        position.players[1].resources = accepts ? [.brick: 2] : [.grain: 2, .brick: 2]
        position.players[2].resources = accepts ? [:] : [.grain: 2, .brick: 2]
        for resource in Resource.allCases {
            position.bank[resource] = 19 - position.players.reduce(0) { $0 + ($1.resources[resource] ?? 0) }
        }
        model.replaceStateForTesting(position, humanSeat: PlayerID(index: 0))
        model.isBlockingSurfaceOpen = true
        return model
    }

    private func expectDurableTradeTrace(
        model: GameViewModel, fixture: CheckpointModelFixture, offer: TradeOffer,
        accepted: Bool, before: GameSession.Checkpoint, sessionOverride: String? = nil
    ) throws {
        let match = try #require(model.checkpointDocument?.activeMatch)
        let record = try #require(match.moves.last)
        let trace = try #require(record.policyTrace)
        let profile = try #require(model.opponentProfile(for: record.actor))
        #expect(trace.evaluationIndex == nil)
        #expect(trace.policyID == "app-trade-heuristic-\(profile.strategy.rawValue)")
        #expect(trace.selection.source == "app_trade_heuristic")
        #expect(trace.selection.fallbackReason == "player_trade_negotiation")
        #expect(trace.selection.move == .respondToTrade(offerID: offer.id, accept: accepted))
        #expect(trace.sessionOverride == sessionOverride)
        #expect(record.move == .respondToTrade(offerID: offer.id, accept: accepted && sessionOverride == nil))
        #expect(match.moves.first?.policyTrace == nil, "Human proposals must not inherit a bot trace")
        #expect(model.session.policyRNG == before.policyRNG)
        #expect(model.session.policyEvaluationCount == before.policyEvaluationCount)
        #expect(model.state.rng == before.state.rng)
        #expect(model.opponentProfiles.values.allSatisfy { $0.policy == .neuralR2 })
        let resumed = fixture.makeModel()
        #expect(resumed.savedGameAvailability.canResume)
        #expect(resumed.checkpointDocument?.activeMatch?.moves == match.moves)
        #expect(resumed.session.checkpoint == model.session.checkpoint)
        #expect(resumed.opponentProfiles == model.opponentProfiles)
        let summary = try #require(fixture.logStore.summaries().first)
        let detail = try fixture.logStore.detail(for: summary)
        #expect(detail.events.map(\.policyTrace) == match.moves.map(\.policyTrace))
    }
}
