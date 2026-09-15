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

    /// A development card priced at its expectation over the deck's *public*
    /// composition, never over what the deck actually holds.
    ///
    /// ## Why an expectation and not a single placeholder
    /// This used to append a knight, and only a knight, so that the deck's
    /// order could not reach the decision. That was safe and it was wrong in
    /// one decisive place: **a bought card could never project a victory
    /// point.** At 24 of 25 with no site left to build on, the only route to
    /// the last point is a victory-point card, and this priced it as worthless
    /// - so the bot held its cards, and Expanded games between Expert bots
    /// stalled one or two points short of the target until the move cap
    /// ended them. Measured: 4 of 6 seeded Expanded games never finished. The
    /// hand-set weights hid it only partly (2 of 16), because it is not a
    /// weighting error; the card's best outcome was simply absent.
    ///
    /// Scoring both outcomes and weighting them by the chance of each is exact
    /// expected value, and a card that would reach the target now carries
    /// `EvaluationWeights.winning` in proportion to that chance.
    ///
    /// ## Why the rulebook's composition and not the live deck's
    /// Which cards remain is not public: every seat's victory-point draws are
    /// hidden until the game ends. The live deck's composition would therefore
    /// tell this seat what its opponents have drawn. The deck the ruleset
    /// *starts* with is printed in the rules, so that fraction is the honest
    /// prior. `theEvaluatorIgnoresWhatItIsNotEntitledToSee` reverses the deck
    /// and requires the same move, which this still satisfies because nothing
    /// here reads the deck at all beyond whether it is empty.
    func projectedDevCard(
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double? {
        guard let paid = paidForDevCard(in: state, seat: evaluator.seat) else { return nil }
        let chance = Self.publicVictoryPointChance(in: state.rules)

        let asKnight = evaluated(paid, drawing: .knight, seat: evaluator.seat, ledger: ledger, evaluator: evaluator)
        guard chance > 0 else { return asKnight }
        let asPoint = evaluated(
            paid, drawing: .victoryPoint, seat: evaluator.seat, ledger: ledger, evaluator: evaluator
        )
        return chance * asPoint + (1 - chance) * asKnight
    }

    /// The fraction of the ruleset's printed deck that is victory points.
    static func publicVictoryPointChance(in rules: Ruleset) -> Double {
        let size = rules.devCardDeckSize
        guard size > 0 else { return 0 }
        return Double(rules.devCardDeck[.victoryPoint] ?? 0) / Double(size)
    }

    /// The position with the card's cost paid, or `nil` if it cannot be.
    private func paidForDevCard(in state: GameState, seat: PlayerID) -> GameState? {
        guard let index = state.players.firstIndex(where: { $0.id == seat }) else { return nil }
        guard !state.devCardDeck.isEmpty else { return nil }

        var next = state
        for resource in Resource.allCases {
            let due = Building.devCardCost[resource] ?? 0
            guard due > 0 else { continue }
            let held = next.players[index].resources[resource] ?? 0
            guard held >= due else { return nil }
            next.players[index].resources[resource] = held - due
        }
        return next
    }

    /// `paid` with `card` in this seat's hand, evaluated.
    private func evaluated(
        _ paid: GameState,
        drawing card: DevCardType,
        seat: PlayerID,
        ledger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double {
        var next = paid
        if let index = next.players.firstIndex(where: { $0.id == seat }) {
            next.players[index].devCards.append(card)
        }
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

        // Worth proposing only if even the least favourable acceptance leaves
        // this seat meaningfully better off than not trading at all. See
        // `EvaluationWeights.tradeMargin`.
        let standingStill = evaluator.evaluate(state, ledger: ledger)
        var worst: Double?
        for payer in payers {
            guard let settled = settled(offer, payer: payer, in: state) else { continue }
            var nextLedger = ledger
            nextLedger.reconcileObserverHand(from: settled)
            let score = evaluator.evaluate(settled, ledger: nextLedger)
            worst = worst.map { Swift.min($0, score) } ?? score
        }
        guard let worst, worst > standingStill + evaluator.weights.tradeMargin else { return nil }
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
