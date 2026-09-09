import CatanAI
import CatanEngine
import Testing

@Suite struct TradeReviewContextTests {
    @Test(arguments: [1, 2])
    func woolForOreCompletesPurchaseOnlyWhenPaymentLeavesOre(oreHeld: Int) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.ore: oreHeld, .grain: 1]
        state.players[1].resources = [.wool: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.wool: 1], want: [.ore: 1])
        state.pendingTradeOffers = [offer]
        let observation = GameObservation(seat: state.players[0].id, state: state,
                                          legalMoves: [.respondToTrade(offerID: offer.id, accept: true)])
        let context = try TradeReviewContext.make(observation: observation, offerID: offer.id)
        let after = try #require(context.afterAcceptance)
        let score = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: observation.seat, state: state,
            personality: .balanced, includeContributions: true))
        let gain = try #require(score.resourceContributions?.first { $0.direction == .gain })
        // The same completion component is awarded for both inventories.
        // Native purchase availability distinguishes sole from surplus ore.
        #expect(gain.targets.first { $0.targetName == "devCard" }?.contribution == 1.5)
        #expect(!context.before[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(after[0].mainTurnOptionsOnFrozenBoard.developmentCard == (oreHeld == 2))
    }

    @Test func productionReflectsNativeBankShortageWithoutChangingState() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 9)
        state.phase = .mainTurn(playerIndex: 1)
        let vertex = try #require(state.board.onBoardVertices.sorted().first)
        state.players[0].settlements = [vertex]
        state.players[0].resources = [.ore: 1]
        state.players[1].resources = [.wool: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.wool: 1], want: [.ore: 1])
        state.pendingTradeOffers = [offer]
        let mask: [GameMove] = [.respondToTrade(offerID: offer.id, accept: true)]
        let funded = try TradeReviewContext.make(
            observation: GameObservation(seat: state.players[0].id, state: state, legalMoves: mask), offerID: offer.id)
        #expect(funded.before[0].expectedCardsPerRoll.values.reduce(0, +) > 0)
        state.bank = [:]
        let depleted = try TradeReviewContext.make(
            observation: GameObservation(seat: state.players[0].id, state: state, legalMoves: mask), offerID: offer.id)
        #expect(depleted.before[0].expectedCardsPerRoll.values.allSatisfy { $0 == 0 })
        #expect(state.bank.isEmpty)
    }

    @Test func givingAwayOwnedOreCanDestroyExistingDevCardOption() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 9)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.ore: 1, .grain: 1, .wool: 1]
        state.players[1].resources = [.lumber: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.lumber: 1], want: [.ore: 1])
        state.pendingTradeOffers = [offer]
        let context = try TradeReviewContext.make(observation: GameObservation(
            seat: state.players[0].id, state: state, legalMoves: [.respondToTrade(offerID: offer.id, accept: true)]),
            offerID: offer.id)
        #expect(context.before[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        let after = try #require(context.afterAcceptance)
        #expect(!after[0].mainTurnOptionsOnFrozenBoard.developmentCard)
    }

    @Test func atomicPaymentDoesNotInventDevelopmentCardAffordability() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.ore: 1, .grain: 1]
        state.players[1].resources = [.wool: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.wool: 1], want: [.ore: 1])
        state.pendingTradeOffers = [offer]
        let original = state
        let accept = GameMove.respondToTrade(offerID: offer.id, accept: true)
        let observation = GameObservation(seat: state.players[0].id, state: state, legalMoves: [accept])
        let context = try TradeReviewContext.make(observation: observation, offerID: offer.id)
        let after = try #require(context.afterAcceptance)
        #expect(context.nativeAcceptanceError == nil)
        #expect(after[0].hand["ore"] == 0)
        #expect(after[0].hand["wool"] == 1)
        #expect(!after[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        #expect(!after[0].mainTurnNow)
        #expect(after[1].mainTurnNow)
        #expect(state == original)
        let scored = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: observation.seat, state: state,
            personality: .balanced, includeContributions: true))
        let gain = try #require(scored.resourceContributions?.first { $0.direction == .gain })
        // Characterization, not an endorsement: the original-hand valuation
        // credits dev-card completion even though the payment removes ore.
        #expect(gain.targets.first { $0.targetName == "devCard" }?.otherDeficits == 0)
        #expect(gain.targets.first { $0.targetName == "devCard" }?.contribution == 1.5)
    }

    @Test func affordableCityWithNoSettlementIsNotBuildable() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = [.ore: 2, .grain: 2, .wool: 1]
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.ore: 1], want: [.wool: 1])
        state.pendingTradeOffers = [offer]
        let observation = GameObservation(seat: state.players[0].id, state: state,
                                          legalMoves: [.respondToTrade(offerID: offer.id, accept: true)])
        let context = try TradeReviewContext.make(observation: observation, offerID: offer.id)
        let after = try #require(context.afterAcceptance)
        #expect(after[0].hand["ore"] == 3)
        #expect(after[0].mainTurnOptionsOnFrozenBoard.cities == 0)
    }

    @Test func unaffordableAcceptanceHasNoFabricatedAfterState() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[1].resources = [.ore: 1]
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: [.ore: 1], want: [.wool: 1])
        state.pendingTradeOffers = [offer]
        let observation = GameObservation(seat: state.players[0].id, state: state,
                                          legalMoves: [.respondToTrade(offerID: offer.id, accept: false)])
        let context = try TradeReviewContext.make(observation: observation, offerID: offer.id)
        #expect(!context.acceptInRecordedMask)
        #expect(context.nativeAcceptanceError == "insufficientResources")
        #expect(context.afterAcceptance == nil)
    }
}
