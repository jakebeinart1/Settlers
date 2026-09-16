import CatanEngine

/// Prices trades by the only two hands they change.
///
/// ## Why not re-score the position per offer
/// A trade moves cards and nothing else: no road, building, port or
/// production changes, and no victory point. So every term of every seat's
/// standing is unchanged except the hand terms of the two seats trading.
/// Scoring those two hands against a baseline taken once is the same
/// arithmetic as `PositionEvaluator.evaluate` on the settled position - a test
/// pins the equivalence - at a small fraction of the cost. That cost is the
/// difference between weighing a handful of single-resource offers and
/// weighing every bundle a hand can compose, which is the whole point of the
/// trade cascade.
struct TradeValuation {

    let seat: PlayerID
    let state: GameState
    let ledger: PublicLedger
    let evaluator: PositionEvaluator
    /// This seat's evaluation before any trade.
    let standingStill: Double

    private let standings: [PlayerID: Double]
    private let hands: [PlayerID: Double]
    private let rates: [PlayerID: ProductionRate]
    private let finished: Set<PlayerID>

    /// `ledger` must already hold this seat's own hand exactly.
    init(evaluator: PositionEvaluator, state: GameState, ledger: PublicLedger) {
        let board = BoardIndex(state: state)
        var standings: [PlayerID: Double] = [:]
        var hands: [PlayerID: Double] = [:]
        var rates: [PlayerID: ProductionRate] = [:]
        var finished: Set<PlayerID> = []
        for player in state.players.map(\.id).sorted() {
            let rate = ProductionModel.rate(for: player, in: state, tiles: board.tiles)
            let standing = evaluator.standing(of: player, in: state, ledger: ledger, board: board)
            if standing == evaluator.weights.winning { finished.insert(player) }
            rates[player] = rate
            standings[player] = standing
            hands[player] = evaluator.handTerms(belief: ledger.belief(of: player), rate: rate, state: state)
        }
        self.seat = evaluator.seat
        self.state = state
        self.ledger = ledger
        self.evaluator = evaluator
        self.standings = standings
        self.hands = hands
        self.rates = rates
        self.finished = finished
        self.standingStill = Self.relative(standings, seat: evaluator.seat, rival: evaluator.weights.rival)
    }

    /// If `payer` accepts: this seat's evaluation afterwards, and how much the
    /// payer's own standing rises - the model of whether they would say yes.
    func value(of offer: TradeOffer, payer: PlayerID) -> (score: Double, payerGain: Double) {
        var after = ledger
        let event = GameEvent.acceptedTrade(payer, from: seat, gave: offer.want, got: offer.give)
        after.apply(event.masked(for: seat), stateBefore: state)

        var settled = standings
        let payerGain = handDelta(of: payer, after: after)
        for (player, delta) in [(seat, handDelta(of: seat, after: after)), (payer, payerGain)]
        where !finished.contains(player) {
            settled[player, default: 0] += delta
        }
        return (Self.relative(settled, seat: seat, rival: evaluator.weights.rival), payerGain)
    }

    /// The most this seat's own standing rises by building with `hand` this
    /// turn - a city on one of its settlements, or a settlement on a site it
    /// already reaches - or zero if `hand` buys neither.
    ///
    /// ## Why a trade needs to see the purchase after it
    /// Jake's example: three ore, one wheat, two brick and two wood, offering
    /// the brick and wood for a wheat. Scored on the position straight after
    /// the swap, that trade came out at -0.27: five cards instead of eight, a
    /// settlement further off, and a city-ready hand the evaluator only
    /// values a little. It could not see the city. A strong player makes that
    /// trade *because of* the build it enables, so a proposal is scored as the
    /// trade plus the best purchase it opens up, against the best purchase
    /// already open without trading - otherwise any trade would look good
    /// next to a build the seat could make anyway.
    ///
    /// Roads and development cards are left out: a road's value arrives
    /// through the approach term rather than on the turn, and a card's is an
    /// expectation `projectedDevCard` already prices as an ordinary move.
    func bestPurchaseGain(with hand: [Resource: Int]) -> Double {
        guard let index = state.players.firstIndex(where: { $0.id == seat }) else { return 0 }
        var holding = state
        holding.players[index].resources = hand
        var holdingLedger = ledger
        holdingLedger.reconcileObserverHand(from: holding)
        let before = evaluator.standing(
            of: seat, in: holding, ledger: holdingLedger, board: BoardIndex(state: holding)
        )

        let owner = holding.players[index]
        let cities = owner.settlements.sorted().map { GameMove.buildCity($0) }
        let settlements = BoardIndex(state: holding).buildableSites(for: seat, in: holding)
            .map { GameMove.buildSettlement($0) }
        var best = 0.0
        for purchase in cities + settlements {
            var built = holding
            guard (try? RulesEngine.apply(purchase, by: seat, to: &built)) != nil else { continue }
            var builtLedger = holdingLedger
            builtLedger.reconcileObserverHand(from: built)
            let after = evaluator.standing(of: seat, in: built, ledger: builtLedger, board: BoardIndex(state: built))
            best = max(best, after - before)
        }
        return best
    }

    private func handDelta(of player: PlayerID, after: PublicLedger) -> Double {
        guard let rate = rates[player], let before = hands[player] else { return 0 }
        return evaluator.handTerms(belief: after.belief(of: player), rate: rate, state: state) - before
    }

    /// `PositionEvaluator.evaluate`'s combination, over precomputed standings.
    /// Rivals are read in sorted order so a tie resolves the same way in every
    /// process.
    private static func relative(_ standings: [PlayerID: Double], seat: PlayerID, rival: Double) -> Double {
        let mine = standings[seat] ?? 0
        let strongest = standings.keys.filter { $0 != seat }.sorted().compactMap { standings[$0] }.max()
        guard let strongest else { return mine }
        return mine - rival * strongest
    }
}
