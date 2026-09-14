import CatanEngine

/// Plays the move that leaves the best position, judged by `PositionEvaluator`.
///
/// ## What changed from `PlannerPolicy`
/// The objective is the same - be further along than the seat closest to
/// winning - but the quantity computed at the point of decision is different.
/// The planner priced each candidate by re-running a bounded route search for
/// two seats, which cost about 100ms and, more importantly, answered with an
/// estimate whose tail was a single purchase repeated. This scores the
/// resulting position directly. No horizon, no tail, nothing to approximate
/// away.
///
/// Expected turns to the target has not been thrown out; it is the term this
/// policy does not yet carry, and folding it in as one weighted feature is
/// what the planner work was for. It is deliberately absent from this first
/// version so its contribution can be measured rather than assumed.
///
/// ## Public information only
/// Hands are read from the `PublicLedger`, so an opponent's composition is a
/// belief and never their real cards.
///
/// Two deliberate gaps, both narrow and both in this seat's own favour rather
/// than against an opponent's privacy:
/// - A development card is evaluated as *a card*, not as the card the deck
///   would actually deal. `buyDevCard` is projected rather than applied, so
///   the deck's order cannot reach the decision.
/// - A candidate that steals is applied, so the evaluation sees which card the
///   steal would take. That is one card of hidden information reaching a
///   robber placement. It is recorded here rather than hidden because it is
///   the kind of thing that silently makes a strength measurement flattering.
public struct EvaluationPolicy: LedgerAwarePolicy {

    public let id: String
    public let weights: EvaluationWeights

    public init(id: String = "evaluation-v1", weights: EvaluationWeights = .default) {
        self.id = id
        self.weights = weights
    }

    /// Without a ledger, fall back to a position-only belief: exact hand
    /// sizes, unknown composition. Weaker, never wrong.
    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(
            observation,
            ledger: PublicLedger.fromPositionAlone(observation.state, observer: observation.seat),
            rng: &rng
        )
    }

    public func decide(
        _ observation: GameObservation,
        ledger: PublicLedger,
        rng: inout RandomSource
    ) -> GameMove {
        let legal = observation.legalMoves
        precondition(!legal.isEmpty, "asked to decide with no legal moves")
        guard legal.count > 1 else { return legal[0] }
        // A roll is not a decision; nothing downstream of it has happened yet.
        if legal.contains(.rollDice) { return .rollDice }

        var counted = ledger
        counted.reconcileObserverHand(from: observation.state)

        let chosen = best(among: legal, state: observation.state, ledger: counted)
        precondition(legal.contains(chosen), "evaluation policy returned a move outside its mask")
        return chosen
    }

    // MARK: - Choosing

    /// The highest-scoring legal move.
    ///
    /// Ties fall back to the engine's enumeration order, which is sorted and
    /// process-independent, so a seeded game replays move for move.
    func best(among legal: [GameMove], state: GameState, ledger: PublicLedger) -> GameMove {
        // The ledger knows whose view this is; the policy does not carry a
        // seat of its own, so there is only one place the two can disagree.
        let evaluator = PositionEvaluator(seat: ledger.observer, weights: weights)

        var bestMove = legal[0]
        var bestScore = -Double.greatestFiniteMagnitude
        for move in legal {
            guard let score = score(move, state: state, ledger: ledger, evaluator: evaluator) else {
                continue
            }
            if score > bestScore {
                bestScore = score
                bestMove = move
            }
        }
        return bestMove
    }

    /// One candidate's score, or `nil` if the engine refuses the move.
    private func score(
        _ move: GameMove,
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double? {
        if case .proposeTrade(let offer) = move {
            return projectedTrade(offer, state: state, ledger: ledger, evaluator: evaluator)
        }
        if case .buyDevCard = move {
            return projectedDevCard(state: state, ledger: ledger, evaluator: evaluator)
        }
        guard let (next, nextLedger) = applied(move, to: state, ledger: ledger, by: evaluator.seat) else {
            return nil
        }
        return evaluator.evaluate(next, ledger: nextLedger)
    }

    /// Applies `move` and folds its events into the ledger, masked for this
    /// seat so the belief a candidate is scored against is the belief this
    /// seat would actually hold afterwards.
    private func applied(
        _ move: GameMove,
        to state: GameState,
        ledger: PublicLedger,
        by seat: PlayerID
    ) -> (GameState, PublicLedger)? {
        var next = state
        guard let events = try? RulesEngine.apply(move, by: seat, to: &next) else { return nil }
        var nextLedger = ledger
        for event in events {
            nextLedger.apply(event.masked(for: seat), stateBefore: state)
        }
        nextLedger.reconcileObserverHand(from: next)
        return (next, nextLedger)
    }
}
