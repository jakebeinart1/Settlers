import CatanEngine

/// One move a policy weighed, and what it scored.
public struct ScoredCandidate: Sendable, Equatable {
    public let move: GameMove
    public let score: Double
}

extension EvaluationPolicy {

    /// Every candidate at this decision with Expert's value for it, including
    /// offers Expert itself would never make.
    ///
    /// ## Why not reuse `best`
    /// `best` filters: a proposal that fails the cascade's bar is never scored.
    /// A model of a person needs a value for the move the person actually made,
    /// and people make offers Expert filters out. So proposals are valued, not
    /// judged: the worst plausible acceptance plus the purchase it opens, less
    /// the purchase already open (the same correction bank trades use). An
    /// offer nobody could accept is worth standing still.
    ///
    /// The list depends only on the observation, never on the weights, so two
    /// weight vectors give lists that line up index for index.
    ///
    /// `humanTrading` applies the app's rule for a person instead of the
    /// engine's enumeration: a person may offer anything they can afford on
    /// their own turn, including their last card of a kind, which `legalMoves`
    /// never lists. The ghost leaves it off and trades under bot rules.
    public func candidateScores(
        _ observation: GameObservation,
        ledger: PublicLedger,
        extraProposals: [TradeOffer] = [],
        humanTrading: Bool = false
    ) -> [ScoredCandidate] {
        var counted = ledger
        counted.reconcileObserverHand(from: observation.state)
        let state = observation.state
        let evaluator = PositionEvaluator(seat: observation.seat, weights: weights(for: state))
        var purchases: PurchaseGains? = PurchaseGains(
            valuation: TradeValuation(evaluator: evaluator, state: state, ledger: counted)
        )
        var result: [ScoredCandidate] = []
        for move in observation.legalMoves where move != .rollDice {
            if case .proposeTrade = move { continue }
            // Expert's `acceptance` refuses to score an accept that does not
            // beat declining - a weight-dependent filter. A person may accept
            // anyway, so an accept is valued as the position it leads to.
            if case .respondToTrade(_, true) = move {
                if let (next, nextLedger) = applied(move, to: state, ledger: counted, by: evaluator.seat) {
                    result.append(ScoredCandidate(move: move, score: evaluator.evaluate(next, ledger: nextLedger)))
                }
                continue
            }
            if let value = score(move, state: state, ledger: counted, evaluator: evaluator, purchases: &purchases) {
                result.append(ScoredCandidate(move: move, score: value))
            }
        }
        return result + proposalScores(observation, ledger: counted, evaluator: evaluator,
                                       extra: extraProposals, humanTrading: humanTrading)
    }

    private func proposalScores(
        _ observation: GameObservation,
        ledger: PublicLedger,
        evaluator: PositionEvaluator,
        extra: [TradeOffer],
        humanTrading: Bool
    ) -> [ScoredCandidate] {
        let state = observation.state
        let legal = observation.legalMoves
        let enumerated = legal.compactMap { move -> TradeOffer? in
            if case .proposeTrade(let offer) = move { offer } else { nil }
        }
        let mayPropose = !enumerated.isEmpty || (humanTrading && Self.personMayPropose(observation))
        guard mayPropose, let me = state.players.first(where: { $0.id == observation.seat }) else { return [] }

        // ponytail: O(n²) dedupe over at most a few hundred offers per decision.
        // Switch to a content-keyed Set if extraction profiling shows it.
        // A person's offer from the UI carries a random id, and the engine
        // permits a composed offer only under its content-derived id, so every
        // offer is re-issued under that id before it is judged.
        var offers: [TradeOffer] = []
        for offer in enumerated + TradeComposer.offers(from: me) + extra
        where !offers.contains(where: { $0.sameProposition(as: offer) }) {
            offers.append(TradeOffer.enumerated(from: offer.from, give: offer.give, want: offer.want))
        }
        let valuation = TradeValuation(evaluator: evaluator, state: state, ledger: ledger)
        let payers = PlannerTradeEvaluator(seat: observation.seat)
        var purchases = PurchaseGains(valuation: valuation)
        let openNow = purchases.gain(with: me.resources)
        var result: [ScoredCandidate] = []
        for offer in offers {
            let move = GameMove.proposeTrade(offer)
            // The engine's check also asks "may this seat propose at all", which
            // it reads off `legal`. Under human rules that was answered above.
            let gate = enumerated.isEmpty ? legal + [move] : legal
            guard legal.contains(move)
                || RulesEngine.isPermittedComposedProposal(move, by: observation.seat, in: state, legal: gate)
            else { continue }
            let settled = appeal(of: offer, payers: payers, valuation: valuation)?.worst ?? valuation.standingStill
            let opened = purchases.gain(with: me.resources.trading(offer))
            result.append(ScoredCandidate(move: move, score: settled + opened - openNow))
        }
        return result
    }

    /// The app's rule for a person: their own main turn, no offer of theirs pending.
    static func personMayPropose(_ observation: GameObservation) -> Bool {
        let state = observation.state
        guard case .mainTurn(let index) = state.phase, state.players.indices.contains(index),
              state.players[index].id == observation.seat else { return false }
        return !state.pendingTradeOffers.contains { $0.from == observation.seat }
    }
}
