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
        let scores = payers.compactMap {
            settledScore(offer, payer: $0, state: state, ledger: ledger, evaluator: evaluator)
        }
        guard let worst = scores.min(), worst > standingStill + evaluator.weights.tradeMargin else { return nil }
        return worst
    }

    /// This seat's standing if `payer` accepts `offer`, or `nil` if this seat
    /// cannot cover its own side.
    ///
    /// ## The counterparty has to gain something in the model too
    /// This used to move the cards in `GameState` and then refresh only this
    /// seat's own hand in the ledger. But every opponent's hand terms are read
    /// from the ledger, not from the state, so the payer's belief never
    /// changed: to the evaluator, a trade handed its counterparty nothing. The
    /// rival term - the thing that is supposed to stop this seat helping the
    /// leader more than itself - was pricing every trade as a free gift to
    /// nobody. The payer's side now goes through the same `acceptedTrade`
    /// event the engine emits when a trade really happens, so the belief moves
    /// exactly as it would at the table.
    ///
    /// ## Whether the payer can pay is decided from public information only
    /// This also used to refuse any projection where the payer's *real* hand
    /// was short - which let a hidden hand decide which proposals got made.
    /// `plausiblePayers` already answers that question from the counted
    /// ledger. Here the payer's cards are only moved as far as they go; the
    /// evaluation never reads them, because opponents are scored from belief.
    func settledScore(
        _ offer: TradeOffer,
        payer: PlayerID,
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double? {
        // Round three checked the payer's real hand here. That was hidden
        // information choosing proposals, and it is kept only in the frozen
        // anchor so the anchor plays exactly what shipped.
        if tradeModel == .roundThree,
           let index = state.players.firstIndex(where: { $0.id == payer }),
           !RulesEngine.canAfford(offer.want, player: state.players[index]) {
            return nil
        }
        guard let settled = settled(offer, payer: payer, in: state) else { return nil }
        var nextLedger = ledger
        if tradeModel != .roundThree {
            let event = GameEvent.acceptedTrade(payer, from: offer.from, gave: offer.want, got: offer.give)
            nextLedger.apply(event.masked(for: evaluator.seat), stateBefore: state)
        }
        nextLedger.reconcileObserverHand(from: settled)
        return evaluator.evaluate(settled, ledger: nextLedger)
    }

    /// The position after `offer` is executed between its proposer and `payer`,
    /// or `nil` if the proposer - whose hand is this seat's own - cannot cover
    /// its side.
    private func settled(_ offer: TradeOffer, payer: PlayerID, in state: GameState) -> GameState? {
        guard let proposer = state.players.firstIndex(where: { $0.id == offer.from }),
              let accepter = state.players.firstIndex(where: { $0.id == payer }) else { return nil }
        guard RulesEngine.canAfford(offer.give, player: state.players[proposer]) else { return nil }

        var next = state
        transfer(offer.give, from: proposer, to: accepter, in: &next)
        transfer(offer.want, from: accepter, to: proposer, in: &next)
        return next
    }

    /// Moves `amounts` between two seats, never below zero. Only the proposer's
    /// side is guaranteed covered; the payer's is a belief.
    private func transfer(
        _ amounts: [Resource: Int],
        from giver: Int,
        to taker: Int,
        in state: inout GameState
    ) {
        for resource in Resource.allCases {
            let amount = amounts[resource] ?? 0
            guard amount > 0 else { continue }
            let held = state.players[giver].resources[resource] ?? 0
            state.players[giver].resources[resource] = max(0, held - amount)
            state.players[taker].resources[resource] = (state.players[taker].resources[resource] ?? 0) + amount
        }
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
