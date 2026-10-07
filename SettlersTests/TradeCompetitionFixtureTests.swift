import Foundation
import Testing
import CatanEngine
@testable import Settlers

/// The rare-state fixture has no pending trade or fabricated acceptance. Its
/// one QA proposer traverses the production mask/session/store; every recipient
/// retains its configured policy, including after a cold checkpoint restore.
@MainActor
@Suite(.serialized)
struct TradeCompetitionFixtureTests {
    nonisolated struct Configuration: Sendable {
        let winner: TradeCompetitionQAWinner
        let difficulty: BotDifficulty
        let mode: GameMode
    }

    nonisolated private static let configurations = [TradeCompetitionQAWinner.human, .rival].flatMap { winner in
        [BotDifficulty.classic, .expert].flatMap { difficulty in
            [GameMode.classic, .naval].map { Configuration(winner: winner, difficulty: difficulty, mode: $0) }
        }
    }

    @Test(arguments: configurations)
    func realProposalAndColdAcceptancePreserveTheChosenCompetition(configuration: Configuration) throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var setup = fixture.setup
        setup.mode = configuration.mode
        setup.difficulty = configuration.difficulty
        setup.victoryPointTarget = Ruleset.forMode(configuration.mode).defaultVictoryPointTarget
        setup.randomizedBoard = configuration.mode == .naval
        model.startNewGame(setup: setup)
        model.isBlockingSurfaceOpen = true
        model.qaPrepareBotTradeAfterPause(competitionWinner: configuration.winner)
        #expect(model.state.pendingTradeOffers.isEmpty)
        #expect(model.checkpointDocument?.activeMatch?.moves.isEmpty == true)
        let initialSupply = supply(model.state)
        let human = model.humanPlayer
        var candidate = model.session
        let next = candidate.decideNext()
        let choice = try #require(next)
        guard case .proposeTrade(let offer) = choice.move else { Issue.record("QA must propose through the runner"); return }
        #expect(offer.give == [.brick: 4])
        #expect(offer.want == [.grain: 1])
        let step = try candidate.commit(seat: choice.seat, move: choice.move)
        try model.qaCommitStep(step, candidate: candidate)
        let rival = try #require(model.state.players.first { $0.id != human && $0.id != offer.from }?.id)
        let resumed = fixture.makeModel()
        resumed.isBlockingSurfaceOpen = true
        #expect(resumed.savedGameAvailability.canResume)
        #expect(resumed.session.checkpoint == candidate.checkpoint)
        #expect(resumed.checkpointDocument?.activeMatch?.moves.count == 1)
        let humanHand = resumed.state.players[human.index].resources
        try resumed.respondToIncomingTrade(offer, accept: true, explicit: true)
        let expected = configuration.winner == .human ? human : rival
        #expect(resumed.checkpointDocument?.activeMatch?.moves.last?.actor == expected)
        #expect(resumed.checkpointDocument?.activeMatch?.moves.last?.isHumanDecision == (expected == human))
        #expect(resumed.session.lastPolicyDecisions.contains {
            $0.seat == rival && $0.move == .respondToTrade(offerID: offer.id, accept: true)
        })
        #expect(supply(resumed.state) == initialSupply)
        #expect(resumed.state.pendingTradeOffers.isEmpty)
        if configuration.winner == .rival { #expect(resumed.state.players[human.index].resources == humanHand) }
    }

    private func supply(_ state: GameState) -> [Resource: Int] {
        Dictionary(uniqueKeysWithValues: Resource.allCases.map { resource in
            (resource, state.bank[resource, default: 0]
                + state.players.reduce(0) { $0 + $1.resources[resource, default: 0] })
        })
    }
}
