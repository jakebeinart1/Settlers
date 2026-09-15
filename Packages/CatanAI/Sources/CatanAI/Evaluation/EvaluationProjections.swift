import CatanEngine

/// The two candidates that cannot be scored by applying them.
///
/// Everything else the engine offers resolves immediately, so "apply it and
/// look at the result" is both the simplest scoring rule and the most
/// faithful. These two do not resolve:
///
/// - `buyDevCard` draws from a shuffled deck. Applying it would let the deck's
///   order decide which card the evaluation sees, so a seat could prefer the
///   turn on which the deck happens to hold a victory point. That is hidden
///   information steering a decision, and it would flatter every strength
///   measurement taken afterwards.
/// - `proposeTrade` only puts an offer on the table. Applying it changes
///   nothing about the position, so every proposal would score exactly zero
///   and the policy would never propose anything - which is precisely the
///   failure the planner shipped with, at 2.9 proposals a game against the
///   heuristic's 20.6.
extension EvaluationPolicy {

    /// A development card priced as *a* card rather than as the card the deck
    /// would deal: the cost leaves the hand and an unplayed card enters it.
    ///
    /// The placeholder is a knight specifically because it is the one type
    /// that changes no other term - it adds no victory point and, unplayed,
    /// no army progress. What the card is worth on average is carried by
    /// `EvaluationWeights.devCardHeld`, where a sweep can reach it.
    func projectedDevCard(
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double? {
        guard let index = state.players.firstIndex(where: { $0.id == evaluator.seat }) else { return nil }
        guard state.devCardDeck.count > 0 else { return nil }

        var next = state
        for resource in Resource.allCases {
            let due = Building.devCardCost[resource] ?? 0
            guard due > 0 else { continue }
            let held = next.players[index].resources[resource] ?? 0
            guard held >= due else { return nil }
            next.players[index].resources[resource] = held - due
        }
        next.players[index].devCards.append(.knight)

        var nextLedger = ledger
        nextLedger.reconcileObserverHand(from: next)
        return evaluator.evaluate(next, ledger: nextLedger)
    }

    /// A proposal priced by the trade it would become, against the payer who
    /// would benefit most from paying.
    ///
    /// ## Why the pessimistic payer
    /// We do not choose who accepts; they do. Scoring against the friendliest
    /// plausible payer would make every offer look good and turn this seat
    /// into the table's donor - which the planner measurably became, accepting
    /// 10.3 trades a game against the heuristic's 4.5. Taking the minimum over
    /// plausible payers asks a stricter question: is this offer still worth
    /// making if the seat it helps most is the one who takes it?
    ///
    /// A proposal nobody is believed able to pay for scores `nil` and is never
    /// made.
    func projectedTrade(
        _ offer: TradeOffer,
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double? {
        guard improvesOnEveryRefusal(offer, in: state) else { return nil }

        let payers = PlannerTradeEvaluator(seat: evaluator.seat)
            .plausiblePayers(of: offer, state: state, ledger: ledger)
        guard !payers.isEmpty else { return nil }

        var worst: Double?
        for payer in payers {
            guard let settled = settled(offer, payer: payer, in: state) else { continue }
            var nextLedger = ledger
            nextLedger.reconcileObserverHand(from: settled)
            let score = evaluator.evaluate(settled, ledger: nextLedger)
            worst = worst.map { Swift.min($0, score) } ?? score
        }
        return worst
    }

    /// The position after `offer` is executed between its proposer and `payer`.
    ///
    /// Returns `nil` when the payer cannot actually cover it. The belief that
    /// put them on the plausible list is a belief; this is the arithmetic.
    private func settled(_ offer: TradeOffer, payer: PlayerID, in state: GameState) -> GameState? {
        guard let proposer = state.players.firstIndex(where: { $0.id == offer.from }),
              let accepter = state.players.firstIndex(where: { $0.id == payer }) else { return nil }

        var next = state
        guard move(offer.give, from: proposer, to: accepter, in: &next) else { return nil }
        guard move(offer.want, from: accepter, to: proposer, in: &next) else { return nil }
        return next
    }

    /// Moves `amounts` between two seats, or reports that the giver is short.
    private func move(
        _ amounts: [Resource: Int],
        from giver: Int,
        to taker: Int,
        in state: inout GameState
    ) -> Bool {
        for resource in Resource.allCases {
            let amount = amounts[resource] ?? 0
            guard amount > 0 else { continue }
            let held = state.players[giver].resources[resource] ?? 0
            guard held >= amount else { return false }
            state.players[giver].resources[resource] = held - amount
            state.players[taker].resources[resource] = (state.players[taker].resources[resource] ?? 0) + amount
        }
        return true
    }

    /// Whether `offer` is worth putting in front of a table that has already
    /// refused something this turn.
    ///
    /// ## Why this is not the engine's job
    /// `RulesEngine.maxTradeProposalsPerTurn` caps a seat at three proposals a
    /// turn, and its doc comment says plainly what the cap is for: stopping "a
    /// policy that just keeps retrying a declined offer forever". It is a
    /// backstop, not the rule. `TradeHeuristics.untried` is where the shipping
    /// bot declines to re-ask, and this policy had no equivalent - so it
    /// re-proposed the same offer until the cap cut it off, three identical
    /// asks in a row. Declining changes nothing about the board, so the offer
    /// that scored highest before scores highest again; nothing here was ever
    /// going to break that loop on its own.
    ///
    /// ## "A better trade or nothing"
    /// Three shapes are refused, all of them re-asks that a person has already
    /// said no to:
    /// - the identical offer;
    /// - the same ask for less on the table;
    /// - the same goods on the table for a bigger ask.
    ///
    /// A genuinely different trade - different resources, or more offered for
    /// the same ask - is still allowed, because that is a new proposition
    /// rather than pestering. Comparison is by content and never by `id`: an
    /// offer the player refused and an offer the search regenerated are equal
    /// as propositions however they were built.
    func improvesOnEveryRefusal(_ offer: TradeOffer, in state: GameState) -> Bool {
        let refusals = state.declinedTradeOffersThisTurn[offer.from] ?? []
        for refused in refusals {
            if refused.give == offer.give && refused.want == offer.want { return false }
            if refused.want == offer.want, total(offer.give) <= total(refused.give) { return false }
            if refused.give == offer.give, total(offer.want) >= total(refused.want) { return false }
        }
        return true
    }

    /// Cards in a half of a trade. Summed over `Resource.allCases` rather than
    /// the dictionary's own order - these are counts feeding a comparison that
    /// orders candidate moves, and dictionary order is seeded per process.
    private func total(_ amounts: [Resource: Int]) -> Int {
        Resource.allCases.reduce(0) { $0 + (amounts[$1] ?? 0) }
    }
}
