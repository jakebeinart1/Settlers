import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

/// The live human response path, actual seated policies and durable store.
/// Controlled seeds choose each winner; no substitute response evaluator can
/// accidentally make the app integration pass while its real bots decline.
@MainActor
@Suite(.serialized)
struct IncomingTradeCompetitionTests {
    private let human = PlayerID(index: 0)
    private let proposer = PlayerID(index: 1)
    private let rival = PlayerID(index: 2)

    @Test(arguments: [false, true])
    func actualHumanAcceptanceCommitsTheWinnerAndCorrectDecisionOrigin(humanWins: Bool) throws {
        let fixture = try CheckpointModelFixture()
        let winner = humanWins ? human : rival
        let (model, offer) = try installOffer(in: fixture, winner: winner)
        let before = model.state
        let cursor = model.session.checkpoint
        try model.respondToIncomingTrade(offer, accept: true, explicit: true)
        let recorded = try #require(model.checkpointDocument?.activeMatch?.moves.last)
        #expect(recorded.actor == winner)
        #expect(recorded.move == .respondToTrade(offerID: offer.id, accept: true))
        #expect(recorded.isHumanDecision == humanWins)
        #expect(model.state.pendingTradeOffers.isEmpty)
        #expect(model.state.rng == before.rng)
        #expect(model.session.checkpoint.policyRNG != cursor.policyRNG)
        #expect(model.session.checkpoint.policyEvaluationCount == cursor.policyEvaluationCount + 1)
        if humanWins {
            #expect(model.gameplayFeedback.current == nil, "the human already receives a detailed exchange receipt")
        } else {
            #expect(model.state.players[human.index].resources == before.players[human.index].resources)
            let notice = try #require(model.gameplayFeedback.current)
            #expect(notice.kind == .traded(proposer, rival))
            #expect(notice.title(name: { model.playerLabel(for: $0) })
                == "\(model.playerLabel(for: proposer)) traded with \(model.playerLabel(for: rival))")
        }
        let reloaded = fixture.makeModel()
        defer { reloaded.isBlockingSurfaceOpen = true }
        #expect(reloaded.savedGameAvailability.canResume)
        #expect(reloaded.state == model.state)
        #expect(reloaded.session.checkpoint == model.session.checkpoint)
        #expect(reloaded.gameplayFeedback.current == nil, "cold resume cannot replay table news")
        #expect(reloaded.checkpointDocument?.activeMatch?.moves.last?.isHumanDecision == humanWins)
    }

    @Test func failedAcceptancePreservesOfferRandomnessHistoryAndNoticeUntilSuccessfulRetry() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let (model, offer) = try installOffer(in: fixture, winner: rival, atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        let before = model.state
        let checkpoint = model.session.checkpoint
        let document = model.checkpointDocument
        let bytes = try Data(contentsOf: model.checkpointStore.fileURL)
        refuseWrite = true
        #expect(throws: MatchPersistenceFailure.self) {
            try model.respondToIncomingTrade(offer, accept: true, explicit: true)
        }
        #expect(model.persistenceBlocked)
        #expect(model.state == before)
        #expect(model.session.checkpoint == checkpoint)
        #expect(model.checkpointDocument == document)
        #expect(model.gameplayFeedback.current == nil)
        #expect(model.rawIncomingOffer == offer)
        #expect(try Data(contentsOf: model.checkpointStore.fileURL) == bytes)
        refuseWrite = false
        #expect(model.retryPersistence())
        try model.respondToIncomingTrade(offer, accept: true, explicit: true)
        #expect(model.checkpointDocument?.activeMatch?.moves.last?.actor == rival)
        #expect(model.gameplayFeedback.current?.kind == .traded(proposer, rival))
        #expect(model.gameplayFeedback.pending.isEmpty)
        #expect(model.checkpointDocument?.activeMatch?.moves.count == 2)
    }

    @Test(arguments: [false, true])
    func declineAndExpiryKeepTheExistingHumanResponseAndConsumeNoPolicyDraws(explicit: Bool) throws {
        let fixture = try CheckpointModelFixture()
        let (model, offer) = try installOffer(in: fixture, winner: rival)
        let cursor = model.session.checkpoint
        try model.respondToIncomingTrade(offer, accept: false, explicit: explicit)
        let recorded = try #require(model.checkpointDocument?.activeMatch?.moves.last)
        #expect(recorded.actor == human)
        #expect(recorded.move == .respondToTrade(offerID: offer.id, accept: false))
        #expect(recorded.isHumanDecision == explicit)
        #expect(model.session.checkpoint.policyRNG == cursor.policyRNG)
        #expect(model.session.checkpoint.policyEvaluationCount == cursor.policyEvaluationCount)
        #expect(model.state.pendingTradeOffers.isEmpty)
        #expect(model.gameplayFeedback.current == nil)
    }

    private func installOffer(in fixture: CheckpointModelFixture, winner: PlayerID,
                              atCommitStage: @escaping (MatchCheckpointStore.CommitStage) throws -> Void = { _ in }) throws
        -> (GameViewModel, TradeOffer) {
        let model = fixture.makeModel(atCommitStage: atCommitStage)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 71, playerCount: 3)
        state.phase = .mainTurn(playerIndex: proposer.index)
        state.players[human.index].resources = [.grain: 1]
        state.players[proposer.index].resources = [.brick: 4]
        state.players[rival.index].resources = [.grain: 1]
        for resource in Resource.allCases {
            state.bank[resource] = state.rules.bankPerResource - state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
        }
        model.replaceStateForTesting(state, humanSeat: human)
        let offer = TradeOffer.enumerated(from: proposer, give: [.brick: 4], want: [.grain: 1])
        try installWinningSeed(for: winner, offer: offer, model: model)
        try model.reconcileHumanTradeOffers()
        #expect(model.openIncomingOffer == offer)
        model.isBlockingSurfaceOpen = true // Keep the scheduled runner out of this controlled transaction.
        return (model, offer)
    }

    private func installWinningSeed(for winner: PlayerID, offer: TradeOffer, model: GameViewModel) throws {
        for seed in 0..<64 {
            var candidate = GameSession(state: model.state, policies: model.session.policies, policySeed: UInt64(seed))
            let step = try candidate.commit(seat: proposer, move: .proposeTrade(offer))
            var resolved = candidate
            let result = try resolved.acceptTrade(offerID: offer.id, by: human)
            guard result.actor == winner else { continue }
            try model.commitStep(step, candidate: candidate)
            return
        }
        Issue.record("Actual seated recipient never won a generous funded offer across 64 seeds")
        throw MoveError.invalidTradeTarget
    }
}
