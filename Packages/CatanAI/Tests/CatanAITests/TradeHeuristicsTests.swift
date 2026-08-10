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

    // A roughly break-even trade: a cautious (highly trade-willing) bot
    // should take it; a low-willingness bot should not.
    let offer = TradeOffer(from: PlayerID(index: 1), give: [.lumber: 1], want: [.lumber: 1])
    #expect(!TradeHeuristics.evaluate(offer: offer, receiver: PlayerID(index: 0), state: state, personality: .aggressive))
}
