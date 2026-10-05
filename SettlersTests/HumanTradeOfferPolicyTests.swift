import Foundation
import Testing
import CatanEngine
@testable import Settlers

/// These exercise policy decisions and real engine responses, without launching
/// a view model, scheduling its bot runner, or depending on a whole played game.
struct HumanTradeOfferPolicyTests {
    private let human = PlayerID(index: 0)
    private let bot = PlayerID(index: 1)

    private struct EndingPolicy: Policy {
        let id = "human-offer-progress-test"

        func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove { .endTurn }
    }

    private func offer(give: [Resource: Int] = [.wool: 1], want: [Resource: Int] = [.lumber: 1],
                       from: PlayerID = PlayerID(index: 1)) -> TradeOffer {
        TradeOffer.enumerated(from: from, give: give, want: want)
    }

    private func context(turn: Int = 1, sequence: Int = 10, players: Int = 4) -> HumanTradeOfferPolicy.Context {
        .init(completedTurns: turn, proposalSequence: sequence, playerCount: players)
    }

    private func position(_ offer: TradeOffer, players: Int = 4) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5, playerCount: players)
        state.phase = .mainTurn(playerIndex: offer.from.index)
        state.players[human.index].resources = offer.want
        state.players[offer.from.index].resources = offer.give
        state.pendingTradeOffers = [offer]
        return state
    }

    private func ownPort(_ kind: PortKind, for seat: PlayerID, in state: inout GameState) throws {
        let port = try #require(state.board.ports.first { $0.kind == kind })
        state.players[seat.index].settlements.insert(port.vertexA)
    }

    private func rejectionStep(_ offer: TradeOffer) throws -> GameSession.Step {
        var session = GameSession(state: position(offer), policies: [:], policySeed: 5)
        return try session.applyExternal(.respondToTrade(offerID: offer.id, accept: false), by: human)
    }

    @Test(arguments: [2, 3, 4])
    func equalBankExchangeReturnsARealRejection(rate: Int) throws {
        let proposal = offer(want: [.lumber: rate])
        var state = position(proposal)
        if rate == 2 { try ownPort(.resource(.lumber), for: human, in: &state) }
        if rate == 3 { try ownPort(.generic, for: human, in: &state) }
        let policy = HumanTradeOfferPolicy(human: human)
        let decision = policy.decision(for: proposal, in: state, context: context())
        guard case .reject(let move, let reason) = decision else {
            Issue.record("a bank-equivalent interruption must return a rejection action")
            return
        }
        #expect(reason == .bankEquivalentOrBetter)
        let resourcesBefore = state.players.map(\.resources)
        var session = GameSession(state: state, policies: [:], policySeed: 5)
        let step = try session.applyExternal(move, by: human)
        #expect(session.state.pendingTradeOffers.isEmpty)
        #expect(session.state.players.map(\.resources) == resourcesBefore)
        #expect(step.events.contains(.rejectedTrade(human, from: bot)))
        #expect(session.state.declinedTradeOffersThisTurn[bot]?.count == 1)
    }

    @Test func comparisonUsesHumansExportPortAndBankStock() throws {
        let proposal = offer(want: [.lumber: 2])
        var state = position(proposal)
        let policy = HumanTradeOfferPolicy(human: human)
        try ownPort(.resource(.lumber), for: bot, in: &state)
        try ownPort(.resource(.wool), for: human, in: &state)
        #expect(policy.decision(for: proposal, in: state, context: context()) == .present)
        state.players[bot.index].settlements = []
        try ownPort(.resource(.lumber), for: human, in: &state)
        state.bank[.wool] = 0
        #expect(policy.decision(for: proposal, in: state, context: context()) == .present)
    }

    @Test(arguments: [0, 1, 2, 3])
    func bankComparisonWorksForEveryHumanSeat(index: Int) throws {
        let receiver = PlayerID(index: index)
        let proposer = PlayerID(index: (index + 1) % 4)
        let proposal = offer(want: [.lumber: 2], from: proposer)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5)
        state.phase = .mainTurn(playerIndex: proposer.index)
        state.players[receiver.index].resources = proposal.want
        state.players[proposer.index].resources = proposal.give
        state.pendingTradeOffers = [proposal]
        try ownPort(.resource(.lumber), for: receiver, in: &state)
        let policy = HumanTradeOfferPolicy(human: receiver)
        #expect(policy.decision(for: proposal, in: state, context: context()) ==
            .reject(move: .respondToTrade(offerID: proposal.id, accept: false), reason: .bankEquivalentOrBetter))
    }

    @Test func integerBankCostCanStrictlyImproveAnUnevenOffer() throws {
        let proposal = offer(give: [.wool: 2], want: [.lumber: 5])
        var state = position(proposal)
        try ownPort(.resource(.lumber), for: human, in: &state)
        let policy = HumanTradeOfferPolicy(human: human)
        #expect(policy.decision(for: proposal, in: state, context: context()) ==
            .reject(move: .respondToTrade(offerID: proposal.id, accept: false), reason: .bankEquivalentOrBetter))
        state.bank[.wool] = 1
        #expect(policy.decision(for: proposal, in: state, context: context()) == .present)
    }

    @Test func betterDomesticExchangeAndBundlesRemainEligible() throws {
        let proposals = [offer(), offer(give: [.wool: 1, .grain: 1], want: [.lumber: 4]),
                         offer(give: [.wool: 1], want: [.lumber: 1, .brick: 1])]
        let policy = HumanTradeOfferPolicy(human: human)
        for proposal in proposals {
            var state = position(proposal)
            try ownPort(.resource(.lumber), for: human, in: &state)
            #expect(policy.decision(for: proposal, in: state, context: context()) == .present)
        }
    }

    @Test func humanRejectionSuppressesEqualAndWorseClassesAcrossResourcesAndBots() throws {
        let refused = offer(give: [.ore: 1], want: [.lumber: 3])
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordHumanRejection(of: refused, committed: try rejectionStep(refused), context: context())
        for quantity in [3, 4] {
            let next = offer(give: [.grain: 1], want: [.brick: quantity], from: PlayerID(index: 2))
            var state = position(next)
            // The missing bank resource isolates refusal history from bank dominance.
            state.bank[.grain] = 0
            #expect(policy.decision(for: next, in: state, context: context(turn: 2, sequence: 20)) ==
                .reject(move: .respondToTrade(offerID: next.id, accept: false), reason: .rejectedExchangeClass))
        }
        let improved = offer(give: [.grain: 1], want: [.brick: 2], from: PlayerID(index: 2))
        #expect(policy.decision(for: improved, in: position(improved), context: context(turn: 2)) == .present)
    }

    @Test func rejectionClassesIncludeBundlesAndEquivalentRatios() throws {
        let refused = offer(give: [.ore: 1], want: [.lumber: 2, .brick: 1])
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordHumanRejection(of: refused, committed: try rejectionStep(refused), context: context())
        let next = offer(give: [.wool: 2], want: [.grain: 6])
        var state = position(next)
        state.bank[.wool] = 0
        #expect(policy.decision(for: next, in: state, context: context()) ==
            .reject(move: .respondToTrade(offerID: next.id, accept: false), reason: .rejectedExchangeClass))
    }

    @Test func automaticDeclinesDoNotCreateHumanPreferencesAndEvaluationDoesNotSpend() throws {
        let proposal = offer(want: [.lumber: 3])
        let policy = HumanTradeOfferPolicy(human: human)
        let state = position(proposal)
        #expect(policy.decision(for: proposal, in: state, context: context()) == .present)
        _ = try rejectionStep(proposal) // No explicit human-rejection accounting.
        for _ in 0..<5 {
            #expect(policy.decision(for: proposal, in: state, context: context(sequence: 20)) == .present)
        }
    }

    @Test func fairOffersConsumeTurnBudgetButAnOpenCardDoesNotRejectItself() {
        let proposal = offer()
        let state = position(proposal)
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordPresentation(of: proposal, in: state, context: context())
        policy.recordPresentation(of: proposal, in: state, context: context())
        #expect(policy.decision(for: proposal, in: state, context: context()) == .present)
        // Same deterministic UUID, a genuinely new proposal occurrence.
        #expect(policy.decision(for: proposal, in: state, context: context(sequence: 11)) ==
            .reject(move: .respondToTrade(offerID: proposal.id, accept: false), reason: .turnBudget))
        #expect(policy.decision(for: proposal, in: state, context: context(turn: 5, sequence: 11)) == .present)
    }

    @Test(arguments: [3, 4])
    func defaultRoundBudgetLeavesOneSlotForEveryOpponent(players: Int) {
        var policy = HumanTradeOfferPolicy(human: human)
        for index in 1..<players {
            let proposal = offer(from: PlayerID(index: index))
            let state = position(proposal, players: players)
            let window = context(turn: index, sequence: index, players: players)
            #expect(policy.decision(for: proposal, in: state, context: window) == .present)
            policy.recordPresentation(of: proposal, in: state, context: window)
        }
        let proposal = offer()
        #expect(policy.decision(for: proposal, in: position(proposal, players: players),
                                context: context(turn: players + 1, players: players)) == .present)
    }

    @Test func roundBudgetIsIndependentOfTurnBudget() {
        var policy = HumanTradeOfferPolicy(human: human, limits: .init(perTurn: 1, perRound: 2))
        for index in 1...2 {
            let proposal = offer(from: PlayerID(index: index))
            let state = position(proposal)
            policy.recordPresentation(of: proposal, in: state, context: context(turn: index, sequence: index))
        }
        let proposal = offer(from: PlayerID(index: 3))
        #expect(policy.decision(for: proposal, in: position(proposal), context: context(turn: 3)) ==
            .reject(move: .respondToTrade(offerID: proposal.id, accept: false), reason: .roundBudget))
    }

    @Test func suppressedFairOfferResolvesInTheEngineAndBotCanEndItsTurn() throws {
        let proposal = offer()
        let state = position(proposal)
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordPresentation(of: proposal, in: state, context: context())
        let decision = policy.decision(for: proposal, in: state, context: context(sequence: 11))
        guard case .reject(let move, .turnBudget) = decision else {
            Issue.record("the second fair proposal must be resolved, not hidden")
            return
        }
        var session = GameSession(state: state, policies: [bot: EndingPolicy()], policySeed: 5)
        #expect(session.state.pendingTradeOffers.count == 1)
        _ = try session.applyExternal(move, by: human)
        #expect(session.state.pendingTradeOffers.isEmpty)
        guard case .seat(let nextActor) = session.nextActor() else {
            Issue.record("resolving the suppressed offer must return control to a bot")
            return
        }
        #expect(nextActor == bot)
        let decisionToCommit = session.decideNext()
        let next = try #require(decisionToCommit)
        #expect(next.1 == .endTurn)
        _ = try session.commit(seat: next.0, move: next.1)
        #expect(session.state.phase == .rollDice(playerIndex: 2))
    }

    @Test func unpublishedCandidateDoesNotSpendAnInterruption() {
        let proposal = offer()
        let state = position(proposal)
        let committed = HumanTradeOfferPolicy(human: human)
        var candidate = committed
        candidate.recordPresentation(of: proposal, in: state, context: context())
        // Simulate the surrounding checkpoint write failing: do not publish candidate.
        #expect(committed.decision(for: proposal, in: state, context: context(sequence: 11)) == .present)
        #expect(candidate.decision(for: proposal, in: state, context: context(sequence: 11)) ==
            .reject(move: .respondToTrade(offerID: proposal.id, accept: false), reason: .turnBudget))
    }

    @Test func fairRejectionDoesNotSuppressBetterRatiosAndRoundResetsPreference() throws {
        let fair = offer()
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordHumanRejection(of: fair, committed: try rejectionStep(fair), context: context())
        let lopsided = offer(want: [.lumber: 3])
        #expect(policy.decision(for: lopsided, in: position(lopsided), context: context()) == .present)
        policy.recordHumanRejection(of: lopsided, committed: try rejectionStep(lopsided), context: context())
        #expect(policy.decision(for: lopsided, in: position(lopsided), context: context(turn: 5)) == .present)
    }

    @Test func persistedPolicyPreservesBudgetsPreferencesAndOpenOccurrence() throws {
        let proposal = offer()
        let refused = offer(give: [.ore: 1], want: [.brick: 3])
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordPresentation(of: proposal, in: position(proposal), context: context())
        policy.recordHumanRejection(of: refused, committed: try rejectionStep(refused), context: context())
        let restored = try JSONDecoder().decode(HumanTradeOfferPolicy.self, from: JSONEncoder().encode(policy))
        #expect(restored == policy)
        #expect(restored.decision(for: proposal, in: position(proposal), context: context()) == .present)
        #expect(restored.decision(for: proposal, in: position(proposal), context: context(sequence: 11)) ==
            .reject(move: .respondToTrade(offerID: proposal.id, accept: false), reason: .turnBudget))
        #expect(restored.decision(for: refused, in: position(refused), context: context()) ==
            .reject(move: .respondToTrade(offerID: refused.id, accept: false), reason: .rejectedExchangeClass))
    }

    @Test func staleUnaffordableAndHumanProposalsAreNotIncoming() {
        let proposal = offer()
        let policy = HumanTradeOfferPolicy(human: human)
        var state = position(proposal)
        state.players[human.index].resources = [:]
        #expect(policy.decision(for: proposal, in: state, context: context()) == .notIncoming)
        state = position(proposal)
        state.players[bot.index].resources = [:]
        #expect(policy.decision(for: proposal, in: state, context: context()) == .notIncoming)
        state = position(proposal)
        state.pendingTradeOffers = []
        #expect(policy.decision(for: proposal, in: state, context: context()) == .notIncoming)
        let own = offer(from: human)
        #expect(policy.decision(for: own, in: position(own), context: context()) == .notIncoming)
    }

    private func presentedPolicy(_ proposal: TradeOffer) -> HumanTradeOfferPolicy {
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordPresentation(of: proposal, in: position(proposal), context: context(turn: 0, sequence: 0))
        return policy
    }

    /// Damage the actual Codable wire shape, bypassing trusted init contracts.
    private func damaged(_ policy: HumanTradeOfferPolicy,
                         edit: (inout [String: Any]) -> Void) throws -> HumanTradeOfferPolicy {
        let encoded = try JSONEncoder().encode(policy)
        var fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        edit(&fields)
        return try JSONDecoder().decode(HumanTradeOfferPolicy.self,
                                       from: JSONSerialization.data(withJSONObject: fields))
    }

    @Test func presentedQueryRequiresTheRecordedOccurrenceAndDoesNotReserve() throws {
        let proposal = offer()
        let window = context(turn: 0, sequence: 0)
        let fresh = HumanTradeOfferPolicy(human: human)
        #expect(!fresh.isPresented(offer: proposal, context: window))
        let policy = presentedPolicy(proposal)
        let restored = try JSONDecoder().decode(HumanTradeOfferPolicy.self, from: JSONEncoder().encode(policy))
        #expect(restored.isPresented(offer: proposal, context: window))
        #expect(!restored.isPresented(offer: proposal, context: context(turn: 0, sequence: 1)))
        #expect(!restored.isPresented(offer: proposal, context: context(turn: 1, sequence: 0)))
        #expect(!restored.isPresented(offer: offer(want: [.brick: 1]), context: window))
        #expect(restored == policy)
        try restored.validate()
        try restored.validate(for: position(proposal), expectedHuman: human, committedMoves: [.proposeTrade(proposal)])
    }

    @Test(arguments: ["completedTurns", "round", "roundPresentationCount"])
    func negativeDecodedCountersThrowInsteadOfTrapping(field: String) throws {
        let invalid = try damaged(presentedPolicy(offer())) { $0[field] = -1 }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidCounters) { try invalid.validate() }
    }

    @Test(arguments: ["perTurn", "perRound"])
    func decodedNonpositiveLimitsThrow(field: String) throws {
        for amount in [0, -1] {
            let invalid = try damaged(presentedPolicy(offer())) { fields in
                var limits = fields["limits"] as? [String: Any] ?? [:]
                limits[field] = amount
                fields["limits"] = limits
            }
            #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidLimits) { try invalid.validate() }
        }
    }

    @Test(arguments: [-1, 4])
    func decodedSeatOutsideSupportedTablesThrows(index: Int) throws {
        let invalid = try damaged(presentedPolicy(offer())) { $0["human"] = ["index": index] }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidSeat) { try invalid.validate() }
    }

    @Test func checkpointRosterMustMatchThePolicyHuman() throws {
        let proposal = offer()
        let policy = presentedPolicy(proposal)
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidSeat) {
            try policy.validate(for: position(proposal), expectedHuman: bot, committedMoves: [.proposeTrade(proposal)])
        }
        let invalid = try damaged(policy) { $0["human"] = ["index": 3] }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidSeat) {
            try invalid.validate(for: position(proposal, players: 3), expectedHuman: PlayerID(index: 3),
                                 committedMoves: [.proposeTrade(proposal)])
        }
    }

    @Test func decodedOccurrencesMustBeNonnegativeUniqueAndChronological() throws {
        let policy = presentedPolicy(offer())
        let negative = try damaged(policy) { fields in
            var entries = fields["presentations"] as? [[String: Any]] ?? []
            entries[0]["proposalSequence"] = -2
            fields["presentations"] = entries
        }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) { try negative.validate() }
        for reversed in [false, true] {
            let invalid = try damaged(policy) { fields in
                var entries = fields["presentations"] as? [[String: Any]] ?? []
                var second = entries[0]
                if reversed { entries[0]["proposalSequence"] = 1 }
                second["offerID"] = UUID().uuidString
                entries.append(second)
                fields["presentations"] = entries
                fields["roundPresentationCount"] = 2
                fields["limits"] = ["perTurn": 2, "perRound": 3]
            }
            #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) { try invalid.validate() }
        }
    }

    @Test func checkpointHistoryRejectsInventedFutureOrWrongTurnOccurrences() throws {
        let proposal = offer()
        let policy = presentedPolicy(proposal)
        let histories: [[GameMove]] = [[], [.endTurn], [.proposeTrade(offer(want: [.brick: 1]))]]
        for moves in histories {
            #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) {
                try policy.validate(for: position(proposal), expectedHuman: human, committedMoves: moves)
            }
        }
        let wrongTurn = try damaged(policy) { fields in
            var entries = fields["presentations"] as? [[String: Any]] ?? []
            entries[0]["proposalSequence"] = 1
            fields["presentations"] = entries
        }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) {
            try wrongTurn.validate(for: position(proposal), expectedHuman: human,
                                   committedMoves: [.endTurn, .proposeTrade(proposal)])
        }
    }

    @Test func inconsistentOrFutureCountersThrowButOlderAccountingIsValid() throws {
        let proposal = offer()
        let policy = presentedPolicy(proposal)
        let invalidEdits: [(inout [String: Any]) -> Void] = [
            { $0["roundPresentationCount"] = 0 },
            { $0["roundPresentationCount"] = 4 },
            { $0["round"] = 1 },
            { _ = $0.removeValue(forKey: "completedTurns") }
        ]
        for edit in invalidEdits {
            let invalid = try damaged(policy, edit: edit)
            #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidCounters) { try invalid.validate() }
        }
        let future = try damaged(HumanTradeOfferPolicy(human: human)) {
            $0["completedTurns"] = 4
            $0["round"] = 1
        }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidCounters) {
            try future.validate(for: position(proposal), expectedHuman: human, committedMoves: [.proposeTrade(proposal)])
        }
        try policy.validate(for: position(proposal), expectedHuman: human,
                            committedMoves: [.proposeTrade(proposal), .endTurn])
        let inflated = try damaged(policy) { $0["roundPresentationCount"] = 2 }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidCounters) {
            try inflated.validate(for: position(proposal), expectedHuman: human, committedMoves: [.proposeTrade(proposal)])
        }
    }

    @Test func damagedRejectionQuantitiesThrow() throws {
        for quantities in [["given": -3, "received": 1], ["given": 3, "received": 0], ["given": 1, "received": 3]] {
            let invalid = try damaged(presentedPolicy(offer())) { $0["rejectedExchange"] = quantities }
            #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidRejectionClass) { try invalid.validate() }
        }
    }

    @Test func inheritedOccurrenceRequiresAnInitialStateWitnessAndIsDistinctFromIndexZero() throws {
        let proposal = offer()
        let state = position(proposal)
        let inherited = context(turn: 0, sequence: -1)
        var policy = HumanTradeOfferPolicy(human: human)
        policy.recordPresentation(of: proposal, in: state, context: inherited)
        try policy.validate()
        try policy.validate(for: state, expectedHuman: human, committedMoves: [], initialOffers: [proposal])
        #expect(policy.isPresented(offer: proposal, context: inherited))
        #expect(!policy.isPresented(offer: proposal, context: context(turn: 0, sequence: 0)))
        #expect(policy.decision(for: proposal, in: state, context: context(turn: 0, sequence: 0)) ==
            .reject(move: .respondToTrade(offerID: proposal.id, accept: false), reason: .turnBudget))
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) {
            try policy.validate(for: state, expectedHuman: human, committedMoves: [])
        }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) {
            try policy.validate(for: state, expectedHuman: human, committedMoves: [.proposeTrade(proposal)],
                                initialOffers: [offer(want: [.brick: 1])])
        }
        let restored = try JSONDecoder().decode(HumanTradeOfferPolicy.self, from: JSONEncoder().encode(policy))
        try restored.validate(for: state, expectedHuman: human, committedMoves: [], initialOffers: [proposal])
        #expect(restored.isPresented(offer: proposal, context: inherited))
    }

    @Test func multipleInheritedOffersMayShareTheSentinelButNotTheirIdentity() throws {
        let proposals = [offer(), offer(give: [.grain: 1])]
        var policy = HumanTradeOfferPolicy(human: human, limits: .init(perTurn: 2, perRound: 3))
        for proposal in proposals {
            policy.recordPresentation(of: proposal, in: position(proposal), context: context(turn: 0, sequence: -1))
        }
        try policy.validate(for: position(proposals[1]), expectedHuman: human, committedMoves: [], initialOffers: proposals)
        let duplicated = try damaged(policy) { fields in
            var entries = fields["presentations"] as? [[String: Any]] ?? []
            entries[1] = entries[0]
            fields["presentations"] = entries
        }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) { try duplicated.validate() }
        let wrongTurn = try damaged(policy) { $0["completedTurns"] = 1 }
        #expect(throws: HumanTradeOfferPolicy.ValidationError.invalidOccurrence) { try wrongTurn.validate() }
    }
}
