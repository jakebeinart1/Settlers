import Testing
import CatanEngine
@testable import CatanAI

/// Jake, after losing to three Expert bots that between them made two bank
/// trades in twenty turns: "the other opponents make no bank trades. That's
/// bad. I make a lot of bank trades because I use the ports to my advantage."
///
/// The cause was that `TradeValuation.bestPurchaseGain` - which exists
/// precisely because a trade scored on the position immediately after it
/// cannot see the building it pays for - was wired to proposals and not to the
/// bank. A 4:1 was therefore priced at one ply: three cards gone now, the city
/// a move away and invisible, a flat loss at any positive `handCard`.
///
/// One Expert seat in that game held a 3:1 port, finished on three spare ore
/// and no wheat, and never used it once.
@Suite struct EvaluationBankTradeTests {

    /// Seat 0 on its own turn, one grain short of a city, holding four spare
    /// lumber. The 4:1 is the whole distance between a hand that buys nothing
    /// and a hand that buys a city.
    private func oneGrainShortOfACity(seed: UInt64 = 81) -> (GameState, PlayerID, [GameMove]) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.players[0].resources = [.ore: 3, .grain: 1, .lumber: 4]
        state.phase = .mainTurn(playerIndex: 0)
        let candidates: [GameMove] = [
            .endTurn,
            .bankTrade(give: [.lumber: 4], get: [.grain: 1]),
        ]
        return (state, state.players[0].id, candidates)
    }

    private func choice(_ state: GameState, _ me: PlayerID, _ candidates: [GameMove]) -> GameMove {
        var ledger = PublicLedger.fromPositionAlone(state, observer: me)
        ledger.reconcileObserverHand(from: state)
        return EvaluationPolicy().best(among: candidates, state: state, ledger: ledger)
    }

    @Test func aBankTradeThatUnlocksACityIsTaken() {
        let (state, me, candidates) = oneGrainShortOfACity()
        guard case .bankTrade = choice(state, me, candidates) else {
            Issue.record("ended the turn holding four spare lumber one grain short of a city")
            return
        }
    }

    /// The other direction, which is what stops this becoming "always trade":
    /// the same four lumber with the city already affordable buys nothing the
    /// seat does not already have, so handing three cards to the bank is a
    /// loss and the trade must be refused.
    @Test func aBankTradeThatUnlocksNothingIsRefused() {
        var (state, me, candidates) = oneGrainShortOfACity()
        state.players[0].resources = [.ore: 3, .grain: 2, .lumber: 4]
        if case .bankTrade = choice(state, me, candidates) {
            Issue.record("paid the bank three cards for a purchase it could already afford")
        }
    }
}
