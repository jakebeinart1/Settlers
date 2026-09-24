import Testing
import CatanEngine
@testable import CatanAI

/// A Conquest game past setup, seat 0 to act, with seats 0 and 1 settled on one 6.
private func sharedSix(seed: UInt64 = 1) throws -> (GameState, HexCoordinate) {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed, variant: .conquest)
    state.phase = .mainTurn(playerIndex: 0)
    let six = try #require(state.board.tiles.first { $0.numberToken == 6 && $0.coordinate != state.board.robberTile })
    let corners = HexGeometry.corners(of: six.coordinate)
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
    let withNine = try #require(policy.projectedArmyCard(state: state, ledger: ledger, evaluator: evaluator))
    state.armyDeck[0] = 1
    let withOne = try #require(policy.projectedArmyCard(state: state, ledger: ledger, evaluator: evaluator))
    #expect(withNine == withOne)
}

@Test func conquestWeightsPriceArmiesAndStandardWeightsDoNot() {
    #expect(EvaluationWeights.forMode(.classic).armyStrength == 0)
    #expect(EvaluationWeights.conquest(.classic).armyStrength > 0)
}
