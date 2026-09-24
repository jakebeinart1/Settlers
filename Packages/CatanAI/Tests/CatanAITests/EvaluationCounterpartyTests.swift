import Testing
import CatanEngine
@testable import CatanAI

/// Jake's rule for trading: a trade has to "benefit the bot more than the other
/// players". That can only be judged if the model of a trade includes what the
/// other side receives - and it did not. Opponents are scored from the ledger,
/// and the projection only refreshed this seat's own hand in it, so every
/// counterparty came out of every trade exactly as it went in.
@Suite struct EvaluationCounterpartyTests {

    /// Seat 1 leads the table by two cities. Seat 2 trails. Both would receive
    /// the same ore and grain from this seat.
    private func table(seed: UInt64 = 91) -> (GameState, PublicLedger) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        for vertex in state.players[1].settlements.sorted() {
            state.players[1].settlements.remove(vertex)
            state.players[1].cities.insert(vertex)
        }
        state.players[0].resources = [.ore: 3, .grain: 2, .wool: 1]
        var ledger = PublicLedger.fromPositionAlone(state, observer: state.players[0].id)
        ledger.reconcileObserverHand(from: state)
        return (state, ledger)
    }

    /// The same cards are worth handing to a seat that cannot win and costly to
    /// hand to the seat most likely to - Jake's "three wood for one, when you
    /// know that person will not win". Before this fix the two scored the same,
    /// because neither seat's modelled hand changed.
    @Test func handingTheLeaderWhatItNeedsCostsMoreThanHandingItToATrailingSeat() throws {
        let (state, ledger) = table()
        let me = state.players[0].id
        let offer = TradeOffer(from: me, give: [.ore: 2, .grain: 1], want: [.wool: 1])
        let policy = EvaluationPolicy()
        let evaluator = PositionEvaluator(seat: me, weights: policy.weights(for: state))

        let toLeader = try #require(policy.settledScore(
            offer, payer: state.players[1].id, state: state, ledger: ledger, evaluator: evaluator
        ))
        let toTrailer = try #require(policy.settledScore(
            offer, payer: state.players[2].id, state: state, ledger: ledger, evaluator: evaluator
        ))
        #expect(
            toLeader < toTrailer,
            "the leader receiving ore and grain must cost this seat more than a trailing seat receiving them"
        )
    }

    /// Whether a seat is asked to pay is decided from what is public. A payer
    /// whose real hand is short must still be projected, or its hidden cards
    /// would decide which proposals this seat makes.
    @Test func aPayersRealHandDoesNotDecideWhetherATradeIsProjected() {
        let (opening, ledger) = table(seed: 92)
        var state = opening
        let me = state.players[0].id
        let payer = state.players[2].id
        state.players[2].resources = [:]
        let offer = TradeOffer(from: me, give: [.ore: 1], want: [.wool: 1])
        let policy = EvaluationPolicy()
        let evaluator = PositionEvaluator(seat: me, weights: policy.weights(for: state))

        #expect(policy.settledScore(offer, payer: payer, state: state, ledger: ledger, evaluator: evaluator) != nil)
    }
}
