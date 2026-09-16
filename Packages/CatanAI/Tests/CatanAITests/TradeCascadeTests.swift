import Testing
import CatanEngine
@testable import CatanAI

/// Jake's trade cascade: an offer the table would take, then more desperate,
/// then more desperate still while it still leaves the bot ahead - and nothing
/// once it would not. Plus asks for what the turn needs, pure-value trades,
/// and lopsided bundles.
@Suite struct TradeCascadeTests {

    /// Jake's worked example hand: three ore, one wheat, two brick, two wood -
    /// one wheat short of a city.
    private func jakesHand(seed: UInt64 = 101) -> (GameState, PlayerID, PublicLedger) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        let me = state.players[0].id
        state.players[0].resources = [.ore: 3, .grain: 1, .brick: 2, .lumber: 2]
        for index in 1..<state.players.count {
            state.players[index].resources = [.grain: 2, .wool: 2, .brick: 1]
        }
        var ledger = PublicLedger.fromPositionAlone(state, observer: me)
        ledger.reconcileObserverHand(from: state)
        return (state, me, ledger)
    }

    private func evaluator(for seat: PlayerID, in state: GameState) -> PositionEvaluator {
        PositionEvaluator(seat: seat, weights: EvaluationPolicy().weights(for: state.mode))
    }

    /// The cheap path must be the real path. If this drifts, every trade the
    /// cascade chooses is chosen on arithmetic the rest of the policy does not
    /// share.
    @Test func pricingTwoHandsEqualsScoringTheSettledPosition() throws {
        let (state, me, ledger) = jakesHand()
        let policy = EvaluationPolicy()
        let evaluator = evaluator(for: me, in: state)
        let valuation = TradeValuation(evaluator: evaluator, state: state, ledger: ledger)
        let offers = [
            TradeOffer.enumerated(from: me, give: [.brick: 2, .lumber: 2], want: [.grain: 1]),
            TradeOffer.enumerated(from: me, give: [.ore: 1], want: [.wool: 1]),
            TradeOffer.enumerated(from: me, give: [.brick: 1, .lumber: 1, .ore: 1], want: [.grain: 2]),
        ]
        for offer in offers {
            for payer in state.players.map(\.id) where payer != me {
                let full = try #require(policy.settledScore(
                    offer, payer: payer, state: state, ledger: ledger, evaluator: evaluator
                ))
                let fast = valuation.value(of: offer, payer: payer).score
                #expect(abs(full - fast) < 1e-9, "\(offer.give)->\(offer.want) to \(payer): \(full) vs \(fast)")
            }
        }
    }

    /// "Know what to request from the table to help it on the turn": the city
    /// is one wheat short, so one wheat is asked for, and the bundle Jake
    /// described - two brick and two wood - is among the gives, while the ore
    /// the city needs is never offered for it.
    @Test func composedOffersIncludeJakesBundle() {
        let (state, _, _) = jakesHand()
        let offers = TradeComposer.offers(from: state.players[0])
        #expect(offers.contains { $0.give == [.brick: 2, .lumber: 2] && $0.want == [.grain: 1] })
        #expect(offers.contains { $0.want == [.wool: 2] }, "two-card asks must be composable")
    }

    /// The composer deliberately also offers cards a purchase is holding back,
    /// and scoring decides. Restricting the composer instead cost 14 points:
    /// it offered 0.82 trades a turn where the policy it replaces offered 2.30.
    /// What must not happen is *choosing* such an offer, which
    /// `oneWheatShortOfACityAsksForTheWheat` pins on the decision itself.
    @Test func theComposerOffersReservedCardsAndLetsScoringDecide() {
        let (state, _, _) = jakesHand()
        let offers = TradeComposer.offers(from: state.players[0])
        #expect(offers.contains { $0.want == [.grain: 1] && ($0.give[.ore] ?? 0) > 0 })
    }

    /// The bar a proposal must clear: the position now, plus the best purchase
    /// already open without trading.
    private func baseline(_ state: GameState, _ me: PlayerID, _ ledger: PublicLedger) -> Double {
        let valuation = TradeValuation(evaluator: evaluator(for: me, in: state), state: state, ledger: ledger)
        return valuation.standingStill + valuation.bestPurchaseGain(with: state.players[0].resources)
    }

    /// Every proposal leaves the bot better off than not trading.
    @Test func theCascadeNeverProposesATradeThatDoesNotHelpTheBot() throws {
        let (state, me, ledger) = jakesHand()
        let policy = EvaluationPolicy()
        let legal = RulesEngine.legalMoves(for: state, seat: me)
        let proposal = try #require(policy.cascadeProposal(
            state: state, ledger: ledger, evaluator: evaluator(for: me, in: state), legal: legal
        ))
        #expect(proposal.score > baseline(state, me, ledger))
    }

    /// Jake's example, end to end: one wheat short of a city, the first thing
    /// the cascade asks the table for is that wheat - and it gives up nothing
    /// the city needs to get it.
    @Test func oneWheatShortOfACityAsksForTheWheat() throws {
        let (state, me, ledger) = jakesHand()
        let legal = RulesEngine.legalMoves(for: state, seat: me)
        let proposal = try #require(EvaluationPolicy().cascadeProposal(
            state: state, ledger: ledger, evaluator: evaluator(for: me, in: state), legal: legal
        ))
        #expect(proposal.offer.want == [.grain: 1], "asked for \(proposal.offer.want) instead of the city's wheat")
        #expect((proposal.offer.give[.ore] ?? 0) == 0, "offered the city's own ore")
    }

    /// The ladder, which is `TradeModel.current`: each refusal makes the next
    /// offer more appealing to the table, never less, and the bot stays ahead
    /// the whole way down.
    ///
    /// The shipping default is `worthIt`, which deliberately does *not* force
    /// this - measured, the ladder costs about two points against the shipping
    /// bots and fourteen against them when the offer set is narrow. The ladder
    /// is kept because it is the honest comparison arm for that claim, so it
    /// keeps its test.
    @Test func eachRefusalEscalatesTheNextOfferUnderTheLadder() throws {
        var (state, me, ledger) = jakesHand(seed: 102)
        let policy = EvaluationPolicy(tradeModel: .current)
        let evaluator = evaluator(for: me, in: state)
        var appeals: [Double] = []

        for _ in 0..<RulesEngine.maxTradeProposalsPerTurn {
            let legal = RulesEngine.legalMoves(for: state, seat: me)
            guard let proposal = policy.cascadeProposal(state: state, ledger: ledger, evaluator: evaluator, legal: legal)
            else { break }
            let valuation = TradeValuation(evaluator: evaluator, state: state, ledger: ledger)
            let payers = PlannerTradeEvaluator(seat: me).plausiblePayers(of: proposal.offer, state: state, ledger: ledger)
            let appeal = try #require(payers.map { valuation.value(of: proposal.offer, payer: $0).payerGain }.max())
            #expect(proposal.score > baseline(state, me, ledger), "a desperate step still has to help the bot")
            appeals.append(appeal)
            state.declinedTradeOffersThisTurn[me, default: []].append(proposal.offer)
            ledger.reconcileObserverHand(from: state)
        }

        try #require(appeals.count >= 2, "this hand should support at least one escalation")
        for (earlier, later) in zip(appeals, appeals.dropFirst()) {
            #expect(later > earlier, "an offer after a refusal must be more appealing, not less: \(appeals)")
        }
    }

    /// The shipping model, `worthIt`: Jake's "if it isn't worth trading don't
    /// go down the ladder". Offers are still only made when they leave the bot
    /// better off, but a refusal does not oblige it to concede more.
    @Test func worthItKeepsOfferingOnItsOwnTermsAfterARefusal() throws {
        var (state, me, ledger) = jakesHand(seed: 104)
        let policy = EvaluationPolicy()
        var proposals = 0

        for _ in 0..<RulesEngine.maxTradeProposalsPerTurn {
            let legal = RulesEngine.legalMoves(for: state, seat: me)
            guard let proposal = policy.cascadeProposal(
                state: state, ledger: ledger, evaluator: evaluator(for: me, in: state), legal: legal
            ) else { break }
            #expect(proposal.score > baseline(state, me, ledger), "every offer must still help the bot")
            proposals += 1
            state.declinedTradeOffersThisTurn[me, default: []].append(proposal.offer)
        }
        #expect(proposals >= 2, "refusals should not stop it finding another offer worth making")
    }

    /// "Might sometimes not offer a trade at all": with nothing to gain, no
    /// offer is made.
    @Test func noOfferWhenNothingWouldHelp() {
        let (state, me, ledger) = jakesHand(seed: 103)
        var demanding = EvaluationWeights.forMode(state.mode)
        demanding.tradeMargin = 1_000
        let policy = EvaluationPolicy(weights: demanding)
        let evaluator = PositionEvaluator(seat: me, weights: demanding)
        let legal = RulesEngine.legalMoves(for: state, seat: me)
        #expect(policy.cascadeProposal(state: state, ledger: ledger, evaluator: evaluator, legal: legal) == nil)
    }
}
