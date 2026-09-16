import Testing
import CatanEngine
@testable import CatanAI

/// The trade behaviour the differential objective is supposed to produce.
///
/// These are the worked examples from the design, turned into assertions. They
/// are about *direction*, not about exact numbers: the point is that a trade
/// is judged by what it does to both clocks rather than by what the cards are
/// nominally worth.
@Suite struct PlannerTradeTests {

    /// A position where seat 0 is one ore short of a city and holds surplus
    /// grain, and seat 1 is a long way from anything.
    private func position(seed: UInt64 = 61) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    /// Jake's example: three ore for one lumber, where the ore completes a city
    /// and the lumber buys the proposer part of one road. Lopsided in our
    /// favour, and the planner should take it even though it helps the other
    /// seat too.
    @Test func aSeatBelievedToHoldNothingIsNeverAskedToPay() {
        var state = position(seed: 63)
        let me = state.players[0].id
        for index in state.players.indices where state.players[index].id != me {
            state.players[index].resources = [:]
        }
        let ledger = PublicLedger.fromPositionAlone(state, observer: me)
        let evaluator = PlannerTradeEvaluator(seat: me)
        let offer = TradeOffer(from: me, give: [.wool: 1], want: [.ore: 2])

        #expect(
            evaluator.plausiblePayers(of: offer, state: state, ledger: ledger).isEmpty,
            "no seat holds two ore, so nobody can be a payer"
        )
    }

    /// Belief, not truth: a seat that really does hold the cards but whose
    /// hand the ledger has never seen is still considered a possible payer,
    /// because an uncertain hand might contain anything.
    @Test func anUnseenHandIsTreatedAsPossiblyHoldingAnything() {
        var state = position(seed: 64)
        let me = state.players[0].id
        let them = state.players[1].id
        state.players[1].resources = [.ore: 5]

        var ledger = PublicLedger(observer: me)
        ledger.reconcileHandSizes(from: state)
        let belief = ledger.belief(of: them)

        #expect(belief.knownTotal == 0, "nothing about the composition has been observed")
        #expect(belief.maxTotal == 5, "but the size is public")
        #expect(
            belief.believedHolding(of: .ore) > 0,
            "an uncertain hand is spread across the resources, not assumed empty"
        )
    }
}
