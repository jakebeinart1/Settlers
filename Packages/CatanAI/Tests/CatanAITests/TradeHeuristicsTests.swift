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
    // Two wool, not one: holding three of a resource it does not need clears
    // `generousOfferSurplusThreshold`, so the bot offers the better deal
    // rather than the minimum. Trade proposals used to be hardcoded
    // one-for-one, which meant a bot could never express a two-for-one - and
    // that is most of how Catan is actually negotiated.
    #expect(first.first?.give == [.wool: 2])
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
    // The pending offer has to be the one the bot would actually compose now
    // (two wool for a lumber), or the dedupe does not recognise it and the
    // bot proposes again instead of ending its turn.
    state.pendingTradeOffers = [TradeOffer(from: player, give: [.wool: 2], want: [.lumber: 1])]

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

@Test func cautiousBotAsksAPlayerBeforePayingTheBankWhileBalancedUsesTheBank() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 41)
    state.phase = .mainTurn(playerIndex: 0)
    state.players[0].resources = [.brick: 4, .grain: 1, .wool: 1]
    let player = PlayerID(index: 0)
    var cautiousRNG = RandomSource(seed: 3)
    var balancedRNG = RandomSource(seed: 3)

    let cautious = Bot(personality: .cautious).decide(
        for: state, player: player, rng: &cautiousRNG
    )
    let balanced = Bot(personality: .balanced).decide(
        for: state, player: player, rng: &balancedRNG
    )

    #expect({ if case .proposeTrade = cautious { true } else { false } }())
    #expect({ if case .bankTrade = balanced { true } else { false } }())
}

/// A marginally-favorable deal is accepted from an average opponent but
/// rejected from a dramatically more threatening one, since accepting hands
/// them resources - see `evaluate`'s threat-shift doc. Uses `.aggressive`
/// (low trade willingness) so the *baseline* threshold is already nonzero
/// (`0.5 - 0.2 = 0.3`) - with `.balanced`/`.cautious` the baseline is
/// already clamped to `0`, and this scenario is built around crossing a
/// nonzero baseline, not the zero-baseline floor `neverAcceptsANetLoss...`
/// already covers.
@Test func evaluateRequiresABetterDealFromAHighThreatProposer() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let receiver = PlayerID(index: 0)
    let proposer = PlayerID(index: 1)

    // Ore is only needed by the city (short 2, with grain also short 2 -
    // keeping its "closeness" low) and not at all by the devCard target
    // (already holds the 1 ore it needs) - giving a small-but-positive
    // value (~0.83) rather than the large one wool/grain would carry via
    // the settlement target. Wool is given up in return, already fully
    // covered everywhere, so it carries zero value - netGain ~0.83, above
    // the 0.3 baseline threshold but comfortably below the ~1.3 threshold
    // an above-average-threat proposer would need to clear.
    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 0, .wool: 1, .ore: 1]
    let offer = TradeOffer(from: proposer, give: [.ore: 1], want: [.wool: 1])

    // Baseline: proposer is an average opponent (nobody has built anything
    // yet), so `relativeWeight` falls back to `1.0` and this reads the same
    // as before threat-weighting existed.
    let baselineAccept = TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: state, personality: .aggressive)
    #expect(baselineAccept)

    // Now make the proposer dramatically more threatening than the other
    // opponents - the same marginal deal should flip to a rejection.
    var withThreat = state
    let vertex = state.board.onBoardVertices.sorted().first!
    withThreat.players[1].settlements.insert(vertex)
    withThreat.players[1].cities.insert(vertex)
    withThreat.players[1].devCards = Array(repeating: DevCardType.knight, count: 10)
    let underThreat = TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: withThreat, personality: .aggressive)
    #expect(!underThreat)
}

/// Same marginal deal as above, but this time the *receiver* (not the
/// proposer) is the one built up into a commanding lead over the rest of
/// the field - trading with winning in mind means a bot that's already well
/// ahead has less reason to hand a trailing opponent resources for a
/// merely-okay deal, so the same net gain that clears the bar at an average
/// standing should fail to clear it here.
@Test func evaluateRequiresABetterDealWhenReceiverIsComfortablyAhead() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let receiver = PlayerID(index: 0)
    let proposer = PlayerID(index: 1)

    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 0, .wool: 1, .ore: 1]
    let offer = TradeOffer(from: proposer, give: [.ore: 1], want: [.wool: 1])

    let baselineAccept = TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: state, personality: .aggressive)
    #expect(baselineAccept)

    var receiverAhead = state
    let vertex = state.board.onBoardVertices.sorted().first!
    receiverAhead.players[0].settlements.insert(vertex)
    receiverAhead.players[0].cities.insert(vertex)
    receiverAhead.players[0].devCards = Array(repeating: DevCardType.knight, count: 20)

    let aheadAccept = TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: receiverAhead, personality: .aggressive)
    #expect(!aheadAccept)
}

/// Nothing to convert into: already holds everything the nearest target
/// needs, so there's no "most needed" resource to trade for.
@Test func bestBankTradeIsNilWhenNothingIsBlockingTheNearestBuild() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1, .ore: 0]

    #expect(TradeHeuristics.bestBankTrade(state: state, player: player, personality: .balanced) == nil)
}

/// Regression test for player feedback: bots accepted trades "too easily" -
/// most personalities' base threshold used to collapse straight to `0`
/// (any net-positive deal, however razor-thin, cleared the old bar), rather
/// than requiring a genuinely meaningful benefit. This specific case has
/// netGain ~0.417: below `.aggressive`'s *old* threshold's complement
/// (0.5 - 0.2 = 0.3, so it used to clear it) but above its *new* floor
/// (max(0.4, 0.7 - 0.2*0.6) = 0.58, so it no longer does) - a marginal deal
/// that flips from accept to reject under the fix.
/// Regression test for player feedback: a proposer sitting one card short of
/// a settlement could complete it via a trade that looked individually
/// reasonable to the receiver, because `evaluate` only ever weighed "is this
/// good for me" and never noticed it was also handing the opponent an
/// immediate build. Same offer/receiver/personality as the passing baseline
/// in `evaluateRequiresABetterDealFromAHighThreatProposer` (netGain ~0.83,
/// baseline threshold 0.58) - only the proposer's resources differ, so the
/// unlock check alone is what flips accept to reject.
@Test func evaluateRejectsATradeThatWouldHandTheProposerAnImmediateBuild() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let receiver = PlayerID(index: 0)
    let proposer = PlayerID(index: 1)

    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 0, .wool: 1, .ore: 1]
    let offer = TradeOffer(from: proposer, give: [.ore: 1], want: [.wool: 1])

    // Control: proposer is nowhere near affording a settlement even after
    // this trade (missing brick/lumber/grain too) - accepted, same as the
    // existing baseline test.
    var farFromBuild = state
    farFromBuild.players[1].resources = [.brick: 0, .lumber: 0, .grain: 0, .wool: 0, .ore: 1]
    #expect(TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: farFromBuild, personality: .aggressive))

    // Same offer, but the proposer already holds everything else a
    // settlement needs and is only short the wool this trade would hand
    // them - accepting completes their settlement on the spot.
    var oneCardFromBuild = state
    oneCardFromBuild.players[1].resources = [.brick: 1, .lumber: 1, .grain: 1, .wool: 0, .ore: 1]
    #expect(!TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: oneCardFromBuild, personality: .aggressive))
}

/// Regression test for player feedback: a proposer sitting on a surplus of
/// one resource could work the whole table with a string of individually-
/// plausible one-for-one offers, each evaluated as if it were the only trade
/// happening that turn. Same offer/personality as the baseline above
/// (netGain ~0.83, threshold 0.58) - a single prior acceptance this turn
/// (+0.35 suspicion, threshold 0.93) is already enough to flip it.
@Test func evaluateSuspicionShiftRejectsARepeatTradeFromTheSameProposerThisTurn() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let receiver = PlayerID(index: 0)
    let proposer = PlayerID(index: 1)

    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 0, .wool: 1, .ore: 1]
    let offer = TradeOffer(from: proposer, give: [.ore: 1], want: [.wool: 1])

    #expect(TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: state, personality: .aggressive))

    var afterOneAccept = state
    afterOneAccept.tradesAcceptedThisTurn[proposer] = 1
    #expect(!TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: afterOneAccept, personality: .aggressive))
}

@Test func evaluateRequiresAMeaningfulBenefitNotJustAnyPositiveMargin() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let receiver = PlayerID(index: 0)
    let proposer = PlayerID(index: 1)

    // Settlement/devCard both already satisfied for ore/grain (1 each
    // held) - only City still wants more of either, so ore and grain's
    // values come solely from City's own (asymmetric) closeness there.
    state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1, .ore: 1]
    let offer = TradeOffer(from: proposer, give: [.ore: 1], want: [.grain: 1])

    #expect(!TradeHeuristics.evaluate(offer: offer, receiver: receiver, state: state, personality: .aggressive))
}
