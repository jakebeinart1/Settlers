import CatanEngine
import Testing
@testable import CatanAI

/// Synthetic controls for the offline formula, not sampled strategic evidence.
@Suite struct JointTradeResponsePolicyTests {
    struct WorkedExample: Sendable {
        let before: [Resource: Int]
        let give: [Resource: Int]
        let want: [Resource: Int]
        let devDelta: Double
        let totalDelta: Double
        let accepts: Bool
    }

    // Independent worked totals from scripts/tests/test_trade_accounting.py.
    private static let examples = [
        WorkedExample(before: [.ore: 1, .grain: 1], give: [.wool: 1], want: [.ore: 1],
                      devDelta: 0, totalDelta: 0.25, accepts: false),
        WorkedExample(before: [.ore: 2, .grain: 1], give: [.wool: 1], want: [.ore: 1],
                      devDelta: 1.5, totalDelta: 19.0 / 12, accepts: true),
        WorkedExample(before: [.ore: 1, .grain: 1, .wool: 1], give: [.lumber: 1], want: [.ore: 1],
                      devDelta: -1.5, totalDelta: -5.0 / 12, accepts: false)
    ]
    private static let tolerance = 1e-12

    @Test(arguments: examples)
    func matchesOfflineWorkedExamples(example: WorkedExample) throws {
        let observation = try fixture(before: example.before, give: example.give, want: example.want)
        let after = try acceptedState(observation)
        let devBefore = TradeHeuristics.jointTargetPotential(
            holding: example.before, cost: Building.devCardCost, weight: BotWeights.default.tradeTargetDevCardWeight)
        let devAfter = TradeHeuristics.jointTargetPotential(
            holding: after.players[0].resources, cost: Building.devCardCost, weight: BotWeights.default.tradeTargetDevCardWeight)
        #expect(abs(devAfter - devBefore - example.devDelta) < Self.tolerance)
        #expect(abs(delta(observation, after: after) - example.totalDelta) < Self.tolerance)
        let original = observation
        var rng = RandomSource(seed: 17)
        let move = JointTradeResponsePolicy().decide(observation, rng: &rng)
        #expect(move == response(observation, accept: example.accepts))
        #expect(rng == RandomSource(seed: 17))
        #expect(observation == original)
        #expect(JointTradeResponsePolicy().id == "experimental-joint-balanced-v1")
    }

    @Test(arguments: [1, 2, 3])
    func bundleAndQuantityUseFinalInventory(quantity: Int) throws {
        let observation = try fixture(before: [.ore: 2, .grain: 1], give: [.wool: quantity], want: [.ore: 1])
        let after = try acceptedState(observation)
        #expect(after.players[0].resources[.wool] == quantity)
        #expect(abs(delta(observation, after: after) - 19.0 / 12) < Self.tolerance)
        var rng = RandomSource(seed: 19)
        #expect(JointTradeResponsePolicy().decide(observation, rng: &rng) == response(observation, accept: true))
        #expect(rng == RandomSource(seed: 19))
        if quantity == 1 { try expectOfflineBundleOrder() }
    }

    private func expectOfflineBundleOrder() throws {
        let observation = try fixture(before: [.ore: 2, .grain: 1, .brick: 2],
                                      give: [.wool: 2, .lumber: 1], want: [.ore: 1, .brick: 1])
        let after = try acceptedState(observation)
        let weights = BotWeights.default
        // Python sorts target names: city, devCard, road, settlement.
        let targets = [(Building.cityCost, weights.tradeTargetCityWeight),
                       (Building.devCardCost, weights.tradeTargetDevCardWeight),
                       (Building.roadCost, weights.tradeTargetRoadWeight),
                       (Building.settlementCost, weights.tradeTargetSettlementWeight)]
        let terms = targets.map { cost, weight in
            TradeHeuristics.jointTargetPotential(holding: after.players[0].resources, cost: cost, weight: weight)
                - TradeHeuristics.jointTargetPotential(holding: observation.state.players[0].resources, cost: cost, weight: weight)
        }
        #expect(delta(observation, after: after) == terms.reduce(0.0, +))
        let reverse = TradeHeuristics.jointInventoryDelta(
            before: after.players[0].resources, after: observation.state.players[0].resources, personality: .balanced)
        #expect(reverse == -delta(observation, after: after))
    }

    @Test(arguments: [-1, 0, 1])
    func strictNativeThresholdBoundaryIsUnchanged(offset: Int) throws {
        let observation = try fixture(before: [.ore: 2, .grain: 1], give: [.wool: 1], want: [.ore: 1])
        let after = try acceptedState(observation)
        var weights = BotWeights.default
        weights.acceptThresholdFloor = delta(observation, after: after) + Double(offset) * Self.tolerance
        let offer = try #require(observation.state.pendingTradeOffers.first)
        let baseline = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: observation.seat, state: observation.state, personality: .balanced, weights: weights))
        #expect(baseline.threshold == weights.acceptThresholdFloor)
        var rng = RandomSource(seed: 23)
        let move = JointTradeResponsePolicy(weights: weights).decide(observation, rng: &rng)
        #expect(move == response(observation, accept: offset < 0))
        #expect(rng == RandomSource(seed: 23))
        if offset == 0 { try expectNativeThresholdShifts() }
    }

    private func expectNativeThresholdShifts() throws {
        let original = try fixture(before: [.ore: 2, .grain: 1], give: [.wool: 1], want: [.ore: 1])
        var state = original.state
        state.players[1].resources = [.ore: 2, .grain: 2, .wool: 1]
        state.tradesAcceptedThisTurn[state.players[1].id] = 3
        let observation = GameObservation(seat: original.seat, state: state, legalMoves: original.legalMoves)
        let offer = try #require(state.pendingTradeOffers.first)
        let baseline = try #require(TradeHeuristics.assessment(
            offer: offer, receiver: observation.seat, state: state, personality: .balanced))
        #expect(baseline.suspicionShift > 0 && baseline.unlockShift > 0)
        let after = try acceptedState(observation)
        #expect(delta(observation, after: after) < baseline.threshold)
        var rng = RandomSource(seed: 29)
        #expect(JointTradeResponsePolicy().decide(observation, rng: &rng) == response(observation, accept: false))
        #expect(rng == RandomSource(seed: 29))
    }

    @Test(arguments: [0, 1, 2])
    func availabilityControlsNeverInventAcceptanceOrBuilds(depletedSeat: Int) throws {
        if depletedSeat == 2 {
            try expectEmptyDeckControl()
            return
        }
        let original = try fixture(before: [.ore: 2, .grain: 1], give: [.wool: 1], want: [.ore: 1])
        var state = original.state
        state.players[depletedSeat].resources = [:]
        let observation = GameObservation(seat: original.seat, state: state,
                                          legalMoves: [response(original, accept: false)])
        let offer = try #require(state.pendingTradeOffers.first)
        #expect(!Trading.bothSidesCanHonour(offer, responder: observation.seat, state: state))
        var candidateRNG = RandomSource(seed: 31)
        var plainRNG = candidateRNG
        let chosen = JointTradeResponsePolicy().decide(observation, rng: &candidateRNG)
        #expect(chosen == plainPolicy().decide(observation, rng: &plainRNG))
        #expect(chosen == response(original, accept: false))
        #expect(candidateRNG == plainRNG && candidateRNG == RandomSource(seed: 31))
    }

    private func expectEmptyDeckControl() throws {
        let original = try fixture(before: [.ore: 2, .grain: 1], give: [.wool: 1], want: [.ore: 1])
        var state = original.state
        state.devCardDeck = []
        let observation = GameObservation(seat: original.seat, state: state, legalMoves: original.legalMoves)
        let context = try TradeReviewContext.make(observation: observation,
                                                  offerID: #require(state.pendingTradeOffers.first).id)
        let after = try #require(context.afterAcceptance)
        #expect(!after[0].mainTurnOptionsOnFrozenBoard.developmentCard)
        var rng = RandomSource(seed: 37)
        // The requested experimental formula is resource-only, even with an empty deck.
        #expect(JointTradeResponsePolicy().decide(observation, rng: &rng) == response(observation, accept: true))
        #expect(rng == RandomSource(seed: 37))
    }

    @Test(arguments: [0, 1, 2, 3, 4], [UInt64(41), 43])
    func otherPhasesPreservePlainPolicyAndRNG(phaseIndex: Int, seed: UInt64) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        let seat = state.players[0].id
        let phases: [GamePhase] = [.setupForward(playerIndex: 0), .rollDice(playerIndex: 0),
                                   .mainTurn(playerIndex: 0), .discarding(pending: [seat]), .movingRobber(playerIndex: 0)]
        state.phase = phases[phaseIndex]
        if phaseIndex == 2 || phaseIndex == 3 {
            state.players[0].resources = [.ore: 3, .grain: 2, .wool: 1, .brick: 1, .lumber: 1]
            state.players[0].settlements = [try #require(state.board.onBoardVertices.sorted().first)]
        }
        let observation = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        var candidateRNG = RandomSource(seed: seed)
        var plainRNG = candidateRNG
        let expected = plainPolicy().decide(observation, rng: &plainRNG)
        #expect(JointTradeResponsePolicy().decide(observation, rng: &candidateRNG) == expected)
        #expect(candidateRNG == plainRNG)
        if phaseIndex == 2 { #expect(plainRNG != RandomSource(seed: seed)) }
    }

    @Test(arguments: [false, true])
    func mixedAndAcceptOnlyMasksUseUnchangedFallback(acceptOnly: Bool) throws {
        let original = try fixture(before: [.ore: 1, .grain: 1], give: [.wool: 1], want: [.ore: 1])
        let moves = acceptOnly ? [response(original, accept: true)] : original.legalMoves + [.endTurn]
        let observation = GameObservation(seat: original.seat, state: original.state, legalMoves: moves)
        var candidateRNG = RandomSource(seed: 47)
        var plainRNG = candidateRNG
        #expect(JointTradeResponsePolicy().decide(observation, rng: &candidateRNG)
                == plainPolicy().decide(observation, rng: &plainRNG))
        #expect(candidateRNG == plainRNG)
    }

    private func fixture(before: [Resource: Int], give: [Resource: Int], want: [Resource: Int]) throws -> GameObservation {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .mainTurn(playerIndex: 1)
        state.players[0].resources = before
        state.players[1].resources = give
        let offer = TradeOffer.enumerated(from: state.players[1].id, give: give, want: want)
        try RulesEngine.apply(.proposeTrade(offer), by: state.players[1].id, to: &state)
        try #require(Trading.bothSidesCanHonour(offer, responder: state.players[0].id, state: state))
        return GameObservation(seat: state.players[0].id, state: state, legalMoves: [
            .respondToTrade(offerID: offer.id, accept: true), .respondToTrade(offerID: offer.id, accept: false)
        ])
    }

    private func acceptedState(_ observation: GameObservation) throws -> GameState {
        var after = observation.state
        try RulesEngine.apply(response(observation, accept: true), by: observation.seat, to: &after)
        return after
    }

    private func response(_ observation: GameObservation, accept: Bool) -> GameMove {
        .respondToTrade(offerID: observation.state.pendingTradeOffers[0].id, accept: accept)
    }

    private func delta(_ observation: GameObservation, after: GameState) -> Double {
        TradeHeuristics.jointInventoryDelta(before: observation.state.players[0].resources,
                                           after: after.players[0].resources, personality: .balanced)
    }

    private func plainPolicy() -> HeuristicPolicy {
        HeuristicPolicy(personality: .balanced, id: "heuristic-balanced")
    }
}
