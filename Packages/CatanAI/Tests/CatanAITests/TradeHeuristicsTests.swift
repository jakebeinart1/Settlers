import Testing
import CatanEngine
@testable import CatanAI

@Test func tradeHeuristicsAcceptsClearNetGainTowardNextBuild() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    // One lumber card short of a settlement (brick/grain/wool already held);
    // no ore at all, which is only relevant to the further-off city target.
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 1, .ore: 0]

    let offer = TradeOffer(from: PlayerID(index: 1), give: [.lumber: 1], want: [.ore: 1])
    let accept = TradeHeuristics.evaluate(offer: offer, receiver: PlayerID(index: 0), state: state, personality: .balanced)
    #expect(accept)
}

@Test func tradeHeuristicsRejectsTradeAwayFromNextBuild() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 1, .ore: 0]

    // Mirror image of the accepted offer: gives up the one card that's
    // actually blocking a settlement in exchange for a card that isn't
    // blocking anything imminent.
    let offer = TradeOffer(from: PlayerID(index: 1), give: [.ore: 1], want: [.lumber: 1])
    let accept = TradeHeuristics.evaluate(offer: offer, receiver: PlayerID(index: 0), state: state, personality: .balanced)
    #expect(!accept)
}

@Test func tradeWillingnessShiftsTheAcceptanceBar() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 1, .ore: 0]

    // An exactly break-even trade (give X for X): nobody should take it,
    // trade-willing or not - the acceptance threshold is clamped at 0
    // (see `evaluate`'s doc) precisely so a highly trade-willing
    // personality still never accepts a non-positive trade.
    let offer = TradeOffer(from: PlayerID(index: 1), give: [.lumber: 1], want: [.lumber: 1])
    #expect(!TradeHeuristics.evaluate(offer: offer, receiver: PlayerID(index: 0), state: state, personality: .aggressive))
    #expect(!TradeHeuristics.evaluate(offer: offer, receiver: PlayerID(index: 0), state: state, personality: .cautious))
}

/// Never accepts a trade that's a genuine net *loss* - regression test for
/// the bug where `threshold = 0.5 - tradeWillingness` went negative for
/// `.cautious` (tradeWillingness 0.8 -> threshold -0.3), letting it accept
/// a real loss as long as it wasn't too big a one.
@Test func neverAcceptsANetLossEvenAtHighTradeWillingness() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    // Lumber is the sole blocker of the nearest target (settlement); wool
    // is already fully covered everywhere, so giving wool away for lumber
    // is a big net gain (the control case)...
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 3, .ore: 0]
    let favorable = TradeOffer(from: PlayerID(index: 1), give: [.lumber: 1], want: [.wool: 1])
    #expect(TradeHeuristics.evaluate(offer: favorable, receiver: PlayerID(index: 0), state: state, personality: .cautious))

    // ...but reversed (giving up the lumber we actually need for wool we
    // don't) is a real loss, and should be rejected regardless of how
    // trade-willing the personality is.
    let unfavorable = TradeOffer(from: PlayerID(index: 1), give: [.wool: 1], want: [.lumber: 1])
    #expect(!TradeHeuristics.evaluate(offer: unfavorable, receiver: PlayerID(index: 0), state: state, personality: .cautious))
}

/// Regression test for the trade-loop hang flagged during Task 12/16:
/// `proposeTrades` used to hand back a functionally-identical offer (same
/// give/want, fresh `UUID`) every single call as long as the player's
/// resources/build target didn't change - which never happens on its own
/// once every other bot has already declined it, since nothing besides an
/// explicit accept/reject response ever removes a pending offer (see
/// `Trading.respond`/`GameState.pendingTradeOffers`). That both starves
/// `Bot.decideMainTurn` out of ever reaching `.endTurn` and piles up
/// unbounded duplicate offers in `GameState`.
@Test func proposeTradesSkipsWhenIdenticalOfferAlreadyPending() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    // One lumber short of a settlement (the nearest build target), with a
    // wool surplus to trade away.
    state.players[0].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 3, .ore: 0]

    let first = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(first.count == 1)
    #expect(first.first?.give == [.wool: 1])
    #expect(first.first?.want == [.lumber: 1])

    // Nobody has accepted or rejected it yet - it's still sitting in
    // `pendingTradeOffers`, exactly as it would be on the next call to
    // `Bot.decide` within the same stuck turn.
    state.pendingTradeOffers = first

    let second = TradeHeuristics.proposeTrades(state: state, player: player, personality: .balanced)
    #expect(second.isEmpty)
}

/// Companion to the above at the `Bot` level: once proposing is suppressed
/// by the dedupe above and nothing else is worth doing, `decideMainTurn`
/// must actually converge on `.endTurn` rather than relying solely on
/// `GameViewModel`'s view-layer `sameBotActionCap` backstop.
@Test func botEndsTurnRatherThanReproposingAnIdenticalPendingOffer() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    state.phase = .mainTurn(playerIndex: 1)
    let player = PlayerID(index: 1)
    state.players[1].resources = [.brick: 1, .lumber: 0, .grain: 1, .wool: 3, .ore: 0]
    state.pendingTradeOffers = [TradeOffer(from: player, give: [.wool: 1], want: [.lumber: 1])]

    let bot = Bot(personality: .balanced)
    let move = bot.decide(for: state, player: player)

    guard case .endTurn = move else {
        Issue.record("expected .endTurn, got \(move)")
        return
    }
}

/// Bots previously never fell back to the bank/port at all, only trading
/// with other players - a bot sitting on a lopsided surplus with no willing
/// trade partner would just stall. One brick short... no, one wool short of
/// a settlement, with a 5-brick surplus (well over the no-port 4:1 rate):
/// `bestBankTrade` should offer up brick for the missing wool.
@Test func bestBankTradeConvertsSurplusTowardTheNearestBuild() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 5, .lumber: 1, .grain: 1, .wool: 0, .ore: 0]

    let trade = TradeHeuristics.bestBankTrade(state: state, player: player, personality: .balanced)
    #expect(trade?.give == .brick)
    #expect(trade?.get == .wool)
    #expect(trade?.rate == 4) // no port owned (no settlements yet)
}

/// Nothing to convert into: already holds everything the nearest target
/// needs, so there's no "most needed" resource to trade for.
@Test func bestBankTradeIsNilWhenNothingIsBlockingTheNearestBuild() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1, .ore: 0]

    #expect(TradeHeuristics.bestBankTrade(state: state, player: player, personality: .balanced) == nil)
}
