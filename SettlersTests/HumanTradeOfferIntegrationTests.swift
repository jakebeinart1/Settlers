import Foundation
import Testing
import CatanEngine
@testable import Settlers

/// Real checkpoint/session/offer wiring. Only the filesystem interruption is
/// substituted. Positions are deliberately small boundary fixtures, not claims
/// that an entire match or the trade card UI has been played successfully.
@MainActor
@Suite(.serialized)
struct HumanTradeOfferIntegrationTests {
    private let human = PlayerID(index: 0)
    private let bot = PlayerID(index: 1)

    private func offer(give: [Resource: Int] = [.ore: 1], want: [Resource: Int] = [.lumber: 1],
                       from: PlayerID = PlayerID(index: 1)) -> TradeOffer {
        TradeOffer.enumerated(from: from, give: give, want: want)
    }

    private func installPosition(in fixture: CheckpointModelFixture, bankPort: Bool = false,
                                 atCommitStage: @escaping (MatchCheckpointStore.CommitStage) throws -> Void = { _ in }) throws -> GameViewModel {
        let model = fixture.makeModel(atCommitStage: atCommitStage)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 33, playerCount: 3)
        state.phase = .mainTurn(playerIndex: bot.index)
        state.players[0].resources = bankPort ? [.lumber: 4, .brick: 2] : [.lumber: 3, .brick: 3]
        state.players[1].resources = [.ore: 2, .wool: 2]
        state.players[2].resources = [.grain: 2, .wool: 2]
        for resource in Resource.allCases {
            state.bank[resource] = 19 - state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
        }
        if bankPort {
            let port = try #require(state.board.ports.first { $0.kind == .resource(.lumber) })
            state.players[0].settlements.insert(port.vertexA)
        }
        model.replaceStateForTesting(state, humanSeat: human)
        return model
    }

    private func commit(_ move: GameMove, by actor: PlayerID, to model: GameViewModel) throws {
        var candidate = model.session
        let step = try candidate.commit(seat: actor, move: move)
        try model.commitStep(step, candidate: candidate)
    }

    private func nextBotMainTurn(_ model: GameViewModel) throws {
        let nextBot = PlayerID(index: 2)
        try commit(.endTurn, by: bot, to: model)
        try commit(.rollDice, by: nextBot, to: model)
        if case .movingRobber = model.state.phase {
            let move = try #require(RulesEngine.legalMoves(for: model.state, seat: nextBot).first)
            try commit(move, by: nextBot, to: model)
        }
        #expect(model.state.phase == .mainTurn(playerIndex: nextBot.index))
    }

    @Test func pendingProposalResumesAndPresentationIsDurableAndIdempotent() throws {
        let fixture = try CheckpointModelFixture()
        let original = try installPosition(in: fixture)
        let proposal = offer()
        try commit(.proposeTrade(proposal), by: bot, to: original)
        #expect(original.rawIncomingOffer == proposal)
        #expect(original.openIncomingOffer == nil, "eligibility alone is not a durable presentation")
        let resumed = fixture.makeModel()
        defer { resumed.isBlockingSurfaceOpen = true }
        #expect(resumed.savedGameAvailability.canResume)
        #expect(resumed.rawIncomingOffer == proposal)
        let stateBefore = resumed.state
        let cursorBefore = resumed.session.checkpoint
        let revision = try #require(resumed.checkpointDocument?.revision)
        try resumed.reconcileHumanTradeOffers()
        #expect(resumed.openIncomingOffer == proposal)
        #expect(resumed.state == stateBefore)
        #expect(resumed.session.checkpoint == cursorBefore)
        #expect(resumed.checkpointDocument?.revision == revision + 1)
        let persisted = try #require(try resumed.checkpointStore.load())
        #expect(persisted.humanTradePolicies?[human.index]?.isPresented(
            offer: proposal, context: resumed.tradeOfferContext(proposal)) == true)
        let reopened = fixture.makeModel()
        #expect(reopened.openIncomingOffer == proposal)
        #expect(reopened.humanTradePolicy(for: human) == resumed.humanTradePolicy(for: human))
        try reopened.reconcileHumanTradeOffers()
        #expect(reopened.checkpointDocument == persisted, "resume must not spend another interruption")
    }

    @Test func quantityAwareBankSuppressionCommitsARealEngineResponse() throws {
        let fixture = try CheckpointModelFixture()
        let model = try installPosition(in: fixture, bankPort: true)
        let proposal = offer(give: [.ore: 2], want: [.lumber: 4])
        try commit(.proposeTrade(proposal), by: bot, to: model)
        let holdings = model.state.players.map(\.resources)
        try model.reconcileHumanTradeOffers()
        #expect(model.state.pendingTradeOffers.isEmpty)
        #expect(model.rawIncomingOffer == nil)
        #expect(model.openIncomingOffer == nil)
        #expect(model.state.players.map(\.resources) == holdings)
        #expect(model.state.declinedTradeOffersThisTurn[bot] == [proposal])
        #expect(model.checkpointDocument?.activeMatch?.moves.last?.move ==
            .respondToTrade(offerID: proposal.id, accept: false))
        #expect(model.checkpointDocument?.humanTradePolicies == nil, "automatic suppression is not a human preference")
        let reloaded = fixture.makeModel()
        #expect(reloaded.savedGameAvailability.canResume)
        #expect(reloaded.state == model.state)
        #expect(reloaded.session.nextActor() == .seat(bot), "no hidden offer may retain the human wait")
    }

    @Test(arguments: [false, true])
    func explicitRejectionButNotExpirySuppressesTheClassAcrossResourcesAndBots(explicit: Bool) throws {
        let fixture = try CheckpointModelFixture()
        let model = try installPosition(in: fixture)
        let refused = offer(want: [.lumber: 3])
        try commit(.proposeTrade(refused), by: bot, to: model)
        try model.reconcileHumanTradeOffers()
        #expect(model.openIncomingOffer == refused)
        // Prevent the response's scheduled runner racing the controlled next turn.
        model.isBlockingSurfaceOpen = true
        try model.respondToIncomingTrade(refused, accept: false, explicit: explicit)
        #expect(model.state.pendingTradeOffers.isEmpty)
        try nextBotMainTurn(model)
        let next = offer(give: [.grain: 1], want: [.brick: 3], from: PlayerID(index: 2))
        try commit(.proposeTrade(next), by: next.from, to: model)
        let reopened = fixture.makeModel()
        defer { reopened.isBlockingSurfaceOpen = true }
        let policy = reopened.humanTradePolicy(for: human)
        let context = reopened.tradeOfferContext(next)
        if explicit {
            #expect(policy.decision(for: next, in: reopened.state, context: context) ==
                .reject(move: .respondToTrade(offerID: next.id, accept: false), reason: .rejectedExchangeClass))
        } else {
            #expect(policy.decision(for: next, in: reopened.state, context: context) == .present)
        }
        try reopened.reconcileHumanTradeOffers()
        #expect(reopened.state.pendingTradeOffers.isEmpty == explicit)
        #expect(reopened.openIncomingOffer == (explicit ? nil : next))
    }

    @Test(arguments: ["presentation", "bankSuppression", "explicitRejection"])
    func beforeReplaceFailurePreservesLiveOfferSessionAndPolicy(operation: String) throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = try installPosition(in: fixture, bankPort: operation == "bankSuppression", atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        let proposal = operation == "bankSuppression" ? offer(give: [.ore: 2], want: [.lumber: 4]) : offer(want: [.lumber: 3])
        try commit(.proposeTrade(proposal), by: bot, to: model)
        if operation == "explicitRejection" { try model.reconcileHumanTradeOffers() }
        let before = model.state
        let cursor = model.session.checkpoint
        let document = model.checkpointDocument
        let policy = model.humanTradePolicy(for: human)
        let bytes = try Data(contentsOf: model.checkpointStore.fileURL)
        refuseWrite = true
        #expect(throws: MatchPersistenceFailure.self) {
            if operation == "explicitRejection" {
                try model.respondToIncomingTrade(proposal, accept: false, explicit: true)
            } else {
                try model.reconcileHumanTradeOffers()
            }
        }
        #expect(model.persistenceBlocked)
        #expect(model.persistenceErrorMessage != nil)
        #expect(model.state == before)
        #expect(model.session.checkpoint == cursor)
        #expect(model.checkpointDocument == document)
        #expect(model.humanTradePolicy(for: human) == policy)
        #expect(model.rawIncomingOffer == proposal)
        #expect(try Data(contentsOf: model.checkpointStore.fileURL) == bytes)
        let reloaded = fixture.makeModel()
        #expect(reloaded.state == before)
        #expect(reloaded.humanTradePolicy(for: human) == policy)
        if operation == "explicitRejection" { #expect(model.openIncomingOffer == proposal) }
        model.isBlockingSurfaceOpen = true
    }

    @Test func oldJSONWithoutOptionalPolicyMetadataRemainsResumable() throws {
        let fixture = try CheckpointModelFixture()
        let model = try installPosition(in: fixture)
        let proposal = offer()
        try commit(.proposeTrade(proposal), by: bot, to: model)
        try model.reconcileHumanTradeOffers()
        let url = model.checkpointStore.fileURL
        var wire = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let removed = wire.removeValue(forKey: "humanTradePolicies")
        #expect(removed != nil)
        let legacyBytes = try JSONSerialization.data(withJSONObject: wire)
        try legacyBytes.write(to: url, options: .atomic)
        let resumed = fixture.makeModel()
        #expect(resumed.savedGameAvailability.canResume)
        #expect(resumed.checkpointDocument?.humanTradePolicies == nil)
        #expect(resumed.state == model.state)
        #expect(resumed.rawIncomingOffer == proposal)
        try resumed.reconcileHumanTradeOffers()
        #expect(resumed.openIncomingOffer == proposal)
        #expect(resumed.state.pendingTradeOffers == [proposal])
    }

    @Test func legacyNotIncomingOfferKeepsExistingPresentationAndResponseHandling() throws {
        let fixture = try CheckpointModelFixture()
        let model = try installPosition(in: fixture)
        var legacy = model.state
        legacy.phase = .mainTurn(playerIndex: 2)
        let staleTurnOffer = offer()
        legacy.pendingTradeOffers = [staleTurnOffer]
        model.replaceStateForTesting(legacy, humanSeat: human)
        let policy = model.humanTradePolicy(for: human)
        #expect(policy.decision(for: staleTurnOffer, in: legacy, context: model.tradeOfferContext(staleTurnOffer)) == .notIncoming)
        try model.reconcileHumanTradeOffers()
        #expect(model.openIncomingOffer == staleTurnOffer, ".notIncoming is not hide-only suppression")
        model.isBlockingSurfaceOpen = true
        try model.respondToIncomingTrade(staleTurnOffer, accept: false, explicit: false)
        #expect(model.state.pendingTradeOffers.isEmpty)
    }

    @Test(arguments: [false, true])
    func initialStateOfferWithoutProposalHistoryCanBePresentedOrReallySuppressed(bankDominated: Bool) throws {
        let fixture = try CheckpointModelFixture()
        let model = try installPosition(in: fixture, bankPort: bankDominated)
        let proposal = bankDominated ? offer(give: [.ore: 2], want: [.lumber: 4]) : offer()
        var inherited = model.state
        inherited.pendingTradeOffers = [proposal]
        model.replaceStateForTesting(inherited, humanSeat: human)
        #expect(model.checkpointDocument?.activeMatch?.moves.isEmpty == true)
        #expect(model.tradeOfferContext(proposal).proposalSequence == -1)
        let resumed = fixture.makeModel()
        #expect(resumed.savedGameAvailability.canResume)
        try resumed.reconcileHumanTradeOffers()
        if bankDominated {
            #expect(resumed.state.pendingTradeOffers.isEmpty)
            #expect(resumed.checkpointDocument?.activeMatch?.moves.last?.move ==
                .respondToTrade(offerID: proposal.id, accept: false))
            #expect(resumed.checkpointDocument?.humanTradePolicies == nil)
        } else {
            #expect(resumed.openIncomingOffer == proposal)
            #expect(resumed.checkpointDocument?.activeMatch?.moves.isEmpty == true)
            #expect(resumed.humanTradePolicy(for: human).isPresented(offer: proposal, context: resumed.tradeOfferContext(proposal)))
        }
        let reopened = fixture.makeModel()
        #expect(reopened.savedGameAvailability.canResume)
        #expect(reopened.state == resumed.state)
        #expect(reopened.humanTradePolicy(for: human) == resumed.humanTradePolicy(for: human))
        #expect(reopened.openIncomingOffer == (bankDominated ? nil : proposal))
    }

    @Test(arguments: ["negativeCount", "invalidLimit", "futureOccurrence"])
    func damagedPolicyMetadataBlocksColdLoadWithoutReplacingItsBytes(damage: String) throws {
        let fixture = try CheckpointModelFixture()
        let model = try installPosition(in: fixture)
        let proposal = offer()
        try commit(.proposeTrade(proposal), by: bot, to: model)
        try model.reconcileHumanTradeOffers()
        let url = model.checkpointStore.fileURL
        var wire = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var policies = try #require(wire["humanTradePolicies"] as? [String: Any])
        var policy = try #require(policies[String(human.index)] as? [String: Any])
        if damage == "negativeCount" {
            policy["roundPresentationCount"] = -1
        } else if damage == "invalidLimit" {
            policy["limits"] = ["perTurn": 0, "perRound": 3]
        } else {
            var occurrences = try #require(policy["presentations"] as? [[String: Any]])
            occurrences[0]["proposalSequence"] = 999
            policy["presentations"] = occurrences
        }
        policies[String(human.index)] = policy
        wire["humanTradePolicies"] = policies
        let damagedBytes = try JSONSerialization.data(withJSONObject: wire)
        try damagedBytes.write(to: url, options: .atomic)
        let resumed = fixture.makeModel()
        #expect(!resumed.savedGameAvailability.canResume)
        #expect(resumed.persistenceBlocked)
        #expect(try Data(contentsOf: url) == damagedBytes)
    }
}
