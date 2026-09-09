import CatanAI
import CatanEngine
import Testing

/// Synthetic legal-offer fixtures, not sampled strategic evidence or strength tests.
/// These characterize original-hand scoring, including its accounting mismatch;
/// native review facts describe atomic payment on a frozen board, not a forecast.
@Suite struct TradeAccountingBoundaryTests {
    struct Payment: Sendable {
        let received: Resource
        let sold: Resource
        let retainsCost: Bool
    }

    private static let quantities = [1, 2]
    private static let devResources = Resource.allCases.filter { Building.devCardCost[$0] != nil }
    private static let irrelevantResources = Resource.allCases.filter { Building.devCardCost[$0] == nil }
    private static let neededPayments = payments(selling: devResources, retention: [false, true])
    private static let irrelevantPayments = payments(selling: irrelevantResources, retention: [false])
    private static let usefulPayments = neededPayments.filter(\.retainsCost) + irrelevantPayments

    // Six ordered distinct pairs × two retention boundaries × two quantities = 24 cases.
    @Test(arguments: neededPayments, quantities)
    func neededPaymentStillEarnsCompletionCredit(payment: Payment, quantity: Int) throws {
        let state = try fixture(payment: payment, quantity: quantity)
        let score = try assessment(in: state)
        try expectOriginalHandCredit(score, payment: payment, quantity: quantity)
        let context = try review(in: state)
        let after = try #require(context.afterAcceptance)
        let required = try #require(Building.devCardCost[payment.sold])

        #expect(!context.before[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(after[0].hand[payment.sold.rawValue] == (payment.retainsCost ? required : 0))
        #expect(after[0].mainTurnOptionsOnFrozenBoard.developmentCard == payment.retainsCost)
        // Selling the whole holding (one or two cards) removes a prerequisite;
        // selling the same quantity from surplus leaves the native cost covered.
        #expect(Building.devCardCost.allSatisfy {
            after[0].hand[$0.key.rawValue, default: 0] >= $0.value
        } == payment.retainsCost)
    }

    // Three missing resources × two irrelevant payment resources × two quantities = 12 cases.
    @Test(arguments: irrelevantPayments, quantities)
    func irrelevantPaymentReallyCompletesPurchase(payment: Payment, quantity: Int) throws {
        let state = try fixture(payment: payment, quantity: quantity)
        let score = try assessment(in: state)
        try expectOriginalHandCredit(score, payment: payment, quantity: quantity)
        let context = try review(in: state)
        let after = try #require(context.afterAcceptance)

        #expect(Building.devCardCost[payment.sold] == nil)
        #expect(after[0].hand[payment.sold.rawValue] == 0)
        #expect(!context.before[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(after[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(Building.devCardCost.allSatisfy {
            after[0].hand[$0.key.rawValue, default: 0] >= $0.value
        })
    }

    // Twelve useful payments × two quantities = 24 paired stocked/empty-deck controls.
    @Test(arguments: usefulPayments, quantities)
    func emptyDeckBlocksPurchaseButNotBaselineCredit(payment: Payment, quantity: Int) throws {
        let stocked = try fixture(payment: payment, quantity: quantity)
        var empty = stocked
        empty.devCardDeck = []
        let stockedScore = try assessment(in: stocked)
        let emptyScore = try assessment(in: empty)
        try expectOriginalHandCredit(emptyScore, payment: payment, quantity: quantity)
        let stockedContext = try review(in: stocked)
        let emptyContext = try review(in: empty)
        let stockedAfter = try #require(stockedContext.afterAcceptance)
        let emptyAfter = try #require(emptyContext.afterAcceptance)

        #expect(emptyScore == stockedScore, "Characterization: scoring does not consult deck availability")
        #expect(!stockedContext.before[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(!emptyContext.before[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(stockedAfter[0].hand == emptyAfter[0].hand)
        #expect(Building.devCardCost.allSatisfy {
            emptyAfter[0].hand[$0.key.rawValue, default: 0] >= $0.value
        })
        #expect(stockedAfter[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(!emptyAfter[0].mainTurnOptionsOnFrozenBoard.developmentCard)
    }

    private static func payments(selling resources: [Resource], retention: [Bool]) -> [Payment] {
        var result: [Payment] = []
        for received in devResources {
            for sold in resources where sold != received {
                for retainsCost in retention {
                    result.append(Payment(received: received, sold: sold, retainsCost: retainsCost))
                }
            }
        }
        return result
    }

    /// Start one native dev-card ingredient short, then allocate the exact
    /// payment plus any retained prerequisite. No game trajectory is sampled.
    private func fixture(payment: Payment, quantity: Int) throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = Building.devCardCost
        state.players[0].resources[payment.received] = 0
        let retained = payment.retainsCost ? Building.devCardCost[payment.sold, default: 0] : 0
        state.players[0].resources[payment.sold] = quantity + retained
        let receivedCount = try #require(Building.devCardCost[payment.received])
        state.players[1].resources = [payment.received: receivedCount]
        let offer = TradeOffer.enumerated(
            from: state.players[1].id, give: [payment.received: receivedCount], want: [payment.sold: quantity])
        try RulesEngine.apply(.proposeTrade(offer), by: state.players[1].id, to: &state)
        #expect(!state.devCardDeck.isEmpty)
        return state
    }

    /// Native acceptance validates the synthetic off-turn response mask and
    /// provides both hands after payment without mutating the original state.
    private func review(in state: GameState) throws -> TradeReviewContext {
        let original = state
        let offer = try #require(state.pendingTradeOffers.first)
        let receiver = state.players[0].id
        try #require(Trading.bothSidesCanHonour(offer, responder: receiver, state: state))
        let observation = GameObservation(seat: receiver, state: state, legalMoves: [
            .respondToTrade(offerID: offer.id, accept: true),
            .respondToTrade(offerID: offer.id, accept: false)
        ])
        let context = try TradeReviewContext.make(observation: observation, offerID: offer.id)
        #expect(context.acceptInRecordedMask)
        #expect(context.nativeAcceptanceError == nil)
        let after = try #require(context.afterAcceptance)
        for resource in Resource.allCases {
            let received = offer.give[resource, default: 0]
            let paid = offer.want[resource, default: 0]
            #expect(after[0].hand[resource.rawValue] == state.players[0].resources[resource, default: 0] + received - paid)
            #expect(after[1].hand[resource.rawValue] == state.players[1].resources[resource, default: 0] - received + paid)
        }
        #expect(state == original)
        return context
    }

    private func assessment(in state: GameState) throws -> TradeAssessment {
        let offer = try #require(state.pendingTradeOffers.first)
        let plain = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: state.players[0].id, state: state, personality: .balanced))
        let detailed = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: state.players[0].id, state: state,
            personality: .balanced, includeContributions: true))
        #expect(plain.resourceContributions == nil)
        #expect(scalars(plain) == scalars(detailed))
        #expect(plain.accepted == detailed.accepted)
        return detailed
    }

    private func scalars(_ score: TradeAssessment) -> [Double] {
        [score.gainValue, score.costValue, score.netGain, score.baseThreshold,
         score.threatShift, score.standingShift, score.suspicionShift, score.unlockShift, score.threshold]
    }

    private func expectOriginalHandCredit(_ score: TradeAssessment, payment: Payment, quantity: Int) throws {
        let components = try #require(score.resourceContributions)
        #expect(components.count == 2)
        let gain = try #require(components.first { $0.direction == .gain && $0.resource == payment.received })
        let cost = try #require(components.first { $0.direction == .cost && $0.resource == payment.sold })
        let gainTarget = try #require(gain.targets.first { $0.targetName == "devCard" })
        let costTarget = try #require(cost.targets.first { $0.targetName == "devCard" })
        #expect(gain.quantity == Building.devCardCost[payment.received])
        #expect(gainTarget.required == Building.devCardCost[payment.received])
        #expect(gainTarget.held == 0 && gainTarget.deficit == gainTarget.required)
        #expect(gainTarget.otherDeficits == 0)
        #expect(gainTarget.contribution == BotWeights.default.tradeTargetDevCardWeight)
        #expect(cost.quantity == quantity)
        #expect(costTarget.required == Building.devCardCost[payment.sold, default: 0])
        #expect(costTarget.held == quantity + (payment.retainsCost ? costTarget.required : 0))
        // Baseline cost values an extra card in the original hand, not the
        // prerequisite lost through payment. Do not turn this into a fix.
        #expect(costTarget.deficit == 0 && costTarget.contribution == 0)
        #expect(cost.totalValue == cost.unitValue * Double(quantity))
        #expect(score.gainValue == gain.totalValue && score.costValue == cost.totalValue)
        #expect(score.netGain == score.gainValue - score.costValue)
        #expect(score.accepted == (score.netGain > score.threshold))
    }
}
