import Testing
import CatanEngine
@testable import CatanAI

/// Jake: "They need to still be gaining something, not taking a loss."
///
/// Measured over 40 games, 100 of the 336 offers the Expert bot accepted
/// scored exactly the same as refusing. A tie went to the engine's move order,
/// accept is listed first, so the bot gave rivals trades that were worth
/// nothing to itself. These pin the rule that replaced that: an acceptance has
/// to beat refusing by more than `EvaluationWeights.tradeMargin`, strictly.
@Suite struct EvaluationTradeGainTests {

    /// Seat 0 holds two grain and no ore; seat 1 offers three ore for a single
    /// lumber - exactly a city's worth of ore for a card seat 0 has spare.
    private func offerOfACity(seed: UInt64 = 81) -> (GameState, PlayerID, TradeOffer) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        let me = state.players[0].id
        let them = state.players[1].id
        state.players[0].resources = [.grain: 2, .lumber: 2]
        state.players[1].resources = [.ore: 3]
        let offer = TradeOffer(from: them, give: [.ore: 3], want: [.lumber: 1])
        state.pendingTradeOffers = [offer]
        state.phase = .mainTurn(playerIndex: 1)
        return (state, me, offer)
    }

    private func answer(
        _ offer: TradeOffer, by me: PlayerID, in state: GameState, weights: EvaluationWeights
    ) throws -> Bool {
        let candidates: [GameMove] = [
            .respondToTrade(offerID: offer.id, accept: true),
            .respondToTrade(offerID: offer.id, accept: false),
        ]
        var ledger = PublicLedger.fromPositionAlone(state, observer: me)
        ledger.reconcileObserverHand(from: state)
        let chosen = EvaluationPolicy(weights: weights).best(among: candidates, state: state, ledger: ledger)
        guard case .respondToTrade(_, let accept) = chosen else {
            Issue.record("expected a response, got \(chosen)")
            return false
        }
        return accept
    }

    /// The margin must not make the bot refuse trades that plainly help it -
    /// the measured cost of a floor was 57.5% to 27.1%, so over-refusing is
    /// the expensive direction to get wrong.
    @Test func aTradeThatCompletesACityIsAccepted() throws {
        let (state, me, offer) = offerOfACity()
        #expect(try answer(offer, by: me, in: state, weights: .default), "refused three ore for one lumber")
    }

    /// And the same trade is refused once the required gain exceeds what it
    /// offers. This is the path a tie takes at a margin of zero: the
    /// acceptance does not strictly beat refusing, so refusing wins.
    @Test func anAcceptanceThatDoesNotClearTheMarginIsRefused() throws {
        let (state, me, offer) = offerOfACity(seed: 82)
        var demanding = EvaluationWeights.default
        demanding.tradeMargin = 1_000
        #expect(!(try answer(offer, by: me, in: state, weights: demanding)))
    }
}
