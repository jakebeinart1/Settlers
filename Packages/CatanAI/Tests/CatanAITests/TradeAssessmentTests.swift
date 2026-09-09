import Foundation
import Testing
import CatanEngine
import CatanAI

@Suite struct TradeAssessmentTests {
    @Test func reportsWorkedResourceArithmetic() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
        state.players[0].resources = [.brick: 1, .grain: 1, .wool: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.ore: 1])

        let result = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: state.players[0].id, state: state, personality: .balanced
        ))

        // Lumber completes settlement + road; ore contributes 1.25 city + 1.5 dev card.
        #expect(result.offer == offer)
        #expect(result.receiver == state.players[0].id)
        #expect(result.gainValue == 4)
        #expect(result.costValue == 2.75)
        #expect(result.netGain == 1.25)
        #expect(result.baseThreshold == 0.4)
        #expect(result.threatShift == 0)
        #expect(result.standingShift == 0)
        #expect(result.suspicionShift == 0)
        #expect(result.unlockShift == 0)
        #expect(result.threshold == 0.4)
        #expect(result.accepted)
        #expect(result.accepted == TradeHeuristics.evaluate(
            offer: offer, receiver: result.receiver, state: state, personality: .balanced
        ))
    }

    @Test func mainTurnTraceAppendsActualEvaluationsIncludingFallbackPass() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 1, .grain: 1, .wool: 1]
        state.players[1].resources = [.lumber: 1]
        let good = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.wool: 1])
        let bad = TradeOffer.enumerated(from: state.players[2].id, give: [.ore: 1], want: [.lumber: 1])
        let own = TradeOffer.enumerated(from: state.players[0].id, give: [.brick: 1], want: [.lumber: 1])
        state.pendingTradeOffers = [good, bad, own]
        let prior = try #require(TradeHeuristics.assessment(
            offer: own, receiver: state.players[1].id, state: state, personality: .balanced
        ))
        var assessments = [prior]
        var plainRNG = RandomSource(seed: 29)
        var tracedRNG = plainRNG
        let legal = RulesEngine.legalMoves(for: state)
        let bot = Bot(personality: .balanced)
        let plain = bot.decide(for: state, player: state.players[0].id, legalMoves: legal, rng: &plainRNG)
        let traced = bot.decide(
            for: state, player: state.players[0].id, legalMoves: legal, rng: &tracedRNG, assessments: &assessments
        )
        #expect(traced == plain)
        #expect(traced == .respondToTrade(offerID: good.id, accept: true))
        #expect(tracedRNG == plainRNG)
        #expect(assessments.first == prior)
        #expect(assessments.dropFirst().map(\.offer) == [good, bad, good, bad])
        #expect(assessments.dropFirst().map(\.accepted) == [true, false, true, false])
    }

    @Test func reportsAllThresholdShiftsAndCostOnlyUnlock() throws {
        var state = tradeState()
        state.players[1].resources = [.lumber: 1, .ore: 2, .grain: 2]
        state.players[1].devCards = [.knight]
        state.tradesAcceptedThisTurn[state.players[1].id] = 2
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.ore: 1])
        let result = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: state.players[0].id, state: state, personality: .balanced
        ))
        // No settlements exist to upgrade: only the city's resource cost becomes affordable.
        #expect(state.players[1].settlements.isEmpty)
        #expect(result.gainValue == 4)
        #expect(result.costValue == 2.75)
        #expect(result.netGain == 1.25)
        #expect(result.baseThreshold == 0.4)
        #expect(result.threatShift == 1)
        #expect(result.standingShift == -0.2)
        #expect(result.suspicionShift == 0.7)
        #expect(result.unlockShift == 0.6)
        #expect(result.threshold == 2.5)
        #expect(!result.accepted)
        #expect(!TradeHeuristics.evaluate(
            offer: offer, receiver: result.receiver, state: state, personality: .balanced
        ))
        #expect(try JSONDecoder().decode(TradeAssessment.self, from: JSONEncoder().encode(result)) == result)
    }

    @Test func exactThresholdTieRejectsButNextLowerThresholdAccepts() throws {
        let state = tradeState()
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.ore: 1])
        let tie = 1.25
        for threshold in [tie.nextDown, tie, tie.nextUp] {
            var weights = BotWeights.default
            weights.acceptThresholdFloor = threshold
            weights.acceptThresholdBase = threshold
            weights.acceptThresholdWillingnessScale = 0
            let result = try #require(TradeHeuristics.assessment(
                offer: offer, receiver: state.players[0].id, state: state, personality: .balanced, weights: weights
            ))
            #expect(result.netGain == 1.25)
            #expect(result.threshold == threshold)
            #expect(result.accepted == (threshold == tie.nextDown))
            #expect(TradeHeuristics.evaluate(
                offer: offer, receiver: result.receiver, state: state, personality: .balanced, weights: weights
            ) == result.accepted)
        }
    }

    @Test func negativeShiftClampsThresholdWithoutAcceptingBreakEven() throws {
        var state = tradeState()
        state.players[2].devCards = [.knight]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.lumber: 1])
        var weights = BotWeights.default
        weights.acceptStandingShiftScale = 10
        let result = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: state.players[0].id, state: state, personality: .balanced, weights: weights
        ))
        #expect(result.standingShift == -8)
        #expect(result.threshold == 0)
        #expect(result.netGain == 0)
        #expect(!result.accepted)
    }

    @Test func missingReceiverHasNoArithmeticAndEvaluatesFalse() {
        let state = tradeState()
        let missing = PlayerID(index: 99)
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.wool: 1])
        #expect(TradeHeuristics.assessment(
            offer: offer, receiver: missing, state: state, personality: .balanced
        ) == nil)
        #expect(!TradeHeuristics.evaluate(offer: offer, receiver: missing, state: state, personality: .balanced))
        let reject = GameMove.respondToTrade(offerID: offer.id, accept: false)
        var pending = state
        pending.pendingTradeOffers = [offer]
        let trace = pairedDecision(
            state: pending, player: missing, legal: [.respondToTrade(offerID: offer.id, accept: true), reject]
        )
        #expect(trace.move == reject)
        #expect(trace.assessments.isEmpty)
    }

    @Test func scopedTradeStopsAfterFirstAcceptanceAcrossPersonalities() {
        for personality in [BotPersonality.balanced, .aggressive, .cautious] {
            var state = tradeState()
            let bad = TradeOffer.enumerated(from: state.players[1].id, give: [.ore: 1], want: [.lumber: 1])
            let good = TradeOffer.enumerated(from: state.players[2].id, give: [.lumber: 1], want: [.wool: 1])
            let unvisited = TradeOffer.enumerated(from: state.players[3].id, give: [.lumber: 2], want: [.wool: 1])
            state.pendingTradeOffers = [bad, good, unvisited]
            // Responder is out of turn; its mask is the whole available action space.
            state.phase = .mainTurn(playerIndex: 1)
            let legal = state.pendingTradeOffers.flatMap { offer in
                [GameMove.respondToTrade(offerID: offer.id, accept: true), .respondToTrade(offerID: offer.id, accept: false)]
            }
            let trace = pairedDecision(state: state, legal: legal, personality: personality)
            #expect(trace.move == .respondToTrade(offerID: good.id, accept: true))
            #expect(trace.assessments.map(\.offer) == [bad, good])
            #expect(trace.assessments.map(\.accepted) == [false, true])
            #expect(trace.rng == RandomSource(seed: 29))
        }
    }

    @Test func scopedRejectionOnlyAndAbsentOfferDoNotInventAssessments() {
        var state = tradeState()
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.wool: 1])
        let reject = GameMove.respondToTrade(offerID: offer.id, accept: false)
        state.pendingTradeOffers = [offer]
        let masked = pairedDecision(state: state, legal: [reject])
        #expect(masked.move == reject)
        #expect(masked.assessments.isEmpty)
        state.pendingTradeOffers = []
        let absent = pairedDecision(state: state, legal: [.respondToTrade(offerID: offer.id, accept: true), reject])
        #expect(absent.move == reject)
        #expect(absent.assessments.isEmpty)
    }

    @Test func scopedRejectionRecordsTheActualFailedAssessment() {
        var state = tradeState()
        let bad = TradeOffer.enumerated(from: state.players[1].id, give: [.ore: 1], want: [.lumber: 1])
        state.pendingTradeOffers = [bad]
        let reject = GameMove.respondToTrade(offerID: bad.id, accept: false)
        let trace = pairedDecision(state: state, legal: [.respondToTrade(offerID: bad.id, accept: true), reject])
        #expect(trace.move == reject)
        #expect(trace.assessments.map(\.offer) == [bad])
        #expect(trace.assessments.map(\.accepted) == [false])
    }

    @Test func buildPathPreservesRNGConsumptionAndOmitsUnvisitedFallback() {
        var state = tradeState()
        state.players[0].resources = [.ore: 1, .grain: 1, .wool: 1]
        state.players[1].resources = [.lumber: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.wool: 1])
        state.pendingTradeOffers = [offer]
        let trace = pairedDecision(state: state, legal: RulesEngine.legalMoves(for: state))
        #expect(trace.assessments.map(\.offer) == [offer])
        #expect(trace.rng != RandomSource(seed: 29), "fixture must exercise build-selection randomness")
    }

    @Test func nonTradePhaseLeavesTraceEmpty() {
        var state = tradeState()
        state.phase = .rollDice(playerIndex: 0)
        let trace = pairedDecision(state: state, legal: [.rollDice])
        #expect(trace.move == .rollDice)
        #expect(trace.assessments.isEmpty)
        #expect(trace.rng == RandomSource(seed: 29))
    }

    private func tradeState() -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 1, .grain: 1, .wool: 1]
        return state
    }

    private func pairedDecision(
        state: GameState, player: PlayerID = PlayerID(index: 0), legal: [GameMove],
        personality: BotPersonality = .balanced
    ) -> (move: GameMove, assessments: [TradeAssessment], rng: RandomSource) {
        let bot = Bot(personality: personality)
        var plainRNG = RandomSource(seed: 29)
        var tracedRNG = plainRNG
        var assessments: [TradeAssessment] = []
        let plain = bot.decide(for: state, player: player, legalMoves: legal, rng: &plainRNG)
        let traced = bot.decide(for: state, player: player, legalMoves: legal, rng: &tracedRNG, assessments: &assessments)
        #expect(traced == plain)
        #expect(tracedRNG == plainRNG)
        #expect(legal.contains(traced))
        #expect(assessments.allSatisfy { $0.receiver == player })
        return (traced, assessments, tracedRNG)
    }
}
