import Testing
import CatanEngine
@testable import CatanAI

/// A Conquest game past setup, seat 0 to act, with seats 0 and 1 settled on one 6.
private func sharedSix(seed: UInt64 = 1) throws -> (GameState, HexCoordinate) {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed, variant: .conquest)
    state.phase = .mainTurn(playerIndex: 0)
    let six = try #require(state.board.tiles.first { $0.numberToken == 6 && $0.coordinate != state.board.robberTile })
    let corners = state.board.corners(of: six.coordinate)
    state.players[0].settlements.insert(corners[0])
    state.players[1].settlements.insert(corners[3])
    return (state, six.coordinate)
}

@Test func productionCountsTheTakeover() throws {
    var (state, six) = try sharedSix()
    let me = state.players[0].id
    let tribal = ProductionModel.rate(for: me, in: state).total
    state.garrisons[six] = Garrison(owner: state.players[1].id, strength: 3)
    let silenced = ProductionModel.rate(for: me, in: state).total
    state.garrisons[six] = Garrison(owner: me, strength: 3)
    let held = ProductionModel.rate(for: me, in: state).total
    #expect(silenced < tribal, "a rival's garrison cuts my income")
    #expect(held > tribal, "my own garrison adds the +1")
}

@Test func expertSpendsItsFreeCardTakingAHex() throws {
    var (state, _) = try sharedSix()
    let me = state.players[0].id
    state.armyHands = [me: [9]]
    let legal = RulesEngine.legalMoves(for: state, seat: me)
    var rng = RandomSource(seed: 1)
    let move = EvaluationPolicy().decide(GameObservation(seat: me, state: state, legalMoves: legal), rng: &rng)
    guard case .deployArmy(let hex, let strengths) = move else {
        Issue.record("expected a capture, got \(move)"); return
    }
    #expect(Conquest.outcome(of: strengths.reduce(0, +), against: state.garrisons[hex], by: me)?.owner == me)
}

@Test func buyingIsPricedWithoutPeekingAtTheDeck() throws {
    var (state, _) = try sharedSix()
    let me = state.players[0].id
    state.players[0].resources = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]
    let policy = EvaluationPolicy()
    let ledger = PublicLedger.fromPositionAlone(state, observer: me)
    let evaluator = PositionEvaluator(seat: me, weights: policy.weights(for: state))
    state.armyDeck[0] = 9
    let withNine = try #require(policy.projectedArmyCard(ConquestHeuristics.buyMove(state: state, player: me)!, state: state, ledger: ledger, evaluator: evaluator))
    state.armyDeck[0] = 1
    let withOne = try #require(policy.projectedArmyCard(ConquestHeuristics.buyMove(state: state, player: me)!, state: state, ledger: ledger, evaluator: evaluator))
    #expect(withNine == withOne)
}

@Test func conquestWeightsPriceArmiesAndStandardWeightsDoNot() {
    #expect(EvaluationWeights.forMode(.classic).armyStrength == 0)
    #expect(EvaluationWeights.conquest(.classic).armyStrength > 0)
}

/// My standing in `state` under `weights`.
private func standing(_ state: GameState, _ weights: EvaluationWeights) -> Double {
    let me = state.players[0].id
    return PositionEvaluator(seat: me, weights: weights).standing(
        of: me, in: state, ledger: PublicLedger.fromPositionAlone(state, observer: me), board: BoardIndex(state: state))
}

@Test func aHandThatCanTakeAPrimeHexIsWorthMoreThanItsCards() throws {
    var (weak, six) = try sharedSix()
    weak.garrisons[six] = Garrison(owner: nil, strength: 5)
    weak.armyHands = [weak.players[0].id: [4]]
    var strong = weak
    strong.armyHands = [strong.players[0].id: [4, 2]]           // 6 beats the tribe's 5
    var off = EvaluationWeights.conquest(.classic); off.captureThreat = 0
    var on = off; on.captureThreat = 1
    #expect(standing(strong, on) - standing(weak, on) > standing(strong, off) - standing(weak, off))
}

@Test func aThinGarrisonNextToAnArmedRivalCostsSomething() throws {
    var thin = try sharedSix().0
    let six = try sharedSix().1
    thin.garrisons[six] = Garrison(owner: thin.players[0].id, strength: 1)
    thin.armyHands = [thin.players[1].id: [1, 1, 1]]            // seat 1 touches the 6
    var thick = thin
    thick.garrisons[six] = Garrison(owner: thin.players[0].id, strength: 20)
    var off = EvaluationWeights.conquest(.classic); off.garrisonExposure = 0
    var on = off; on.garrisonExposure = -1
    #expect(standing(thick, on) - standing(thin, on) > standing(thick, off) - standing(thin, off))
}

@Test func buyingValuesTheCaptureTheNewCardCouldEnable() throws {
    var (state, _) = try sharedSix()
    let me = state.players[0].id
    for hex in state.garrisons.keys { state.garrisons[hex] = Garrison(owner: nil, strength: 5) }
    state.armyHands = [me: [3]]                       // 3 alone beats nothing; 3 + a 3 or 4 beats a 5
    state.players[0].resources = [.ore: 3]
    let buy = ConquestHeuristics.buyMove(state: state, player: me)!
    func projected(_ capture: Double) -> Double {
        var weights = EvaluationWeights.conquest(.classic)
        weights.captureThreat = capture
        let policy = EvaluationPolicy(id: "t", weights: weights)
        return policy.projectedArmyCard(buy, state: state, ledger: PublicLedger.fromPositionAlone(state, observer: me),
                                        evaluator: PositionEvaluator(seat: me, weights: weights))!
    }
    #expect(projected(1) > projected(0), "a buy that may complete a capture must be worth more")
}
