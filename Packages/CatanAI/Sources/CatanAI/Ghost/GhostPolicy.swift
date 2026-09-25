import CatanEngine

/// Expert's judgement, pulled toward one person's habits.
///
/// Picks `argmax S_Expert(m) + lambda · (beta · S_person(m) + theta · style(m))`.
/// This is human-regularized search (piKL, Jacob et al. 2022). `lambda` slides
/// from Expert (0) toward the person (large). It is set so the ghost wins as
/// often as the person does, and there it makes the person's kinds of
/// mistakes rather than random ones. The Expert term is what stops the collapse
/// a pure imitation policy showed here (0/40, stopped building).
///
/// `lambda · log Z` is the same for every candidate, so it is dropped. Ties go
/// to the earlier candidate, whose order is the engine's sorted enumeration,
/// so a seeded game replays move for move.
public struct GhostPolicy: LedgerAwarePolicy {
    public let id: String
    public let person: PersonModel
    public let lambda: Double
    private let expert = EvaluationPolicy()
    private let personal: EvaluationPolicy

    public init(person: PersonModel, lambda: Double, id: String = "ghost") {
        self.id = id
        self.person = person
        self.lambda = lambda
        self.personal = EvaluationPolicy(weights: EvaluationWeights(vector: person.weights))
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let legal = observation.legalMoves
        guard legal.count > 1 else { return legal[0] }
        if legal.contains(.rollDice) { return .rollDice }
        var counted = ledger
        counted.reconcileObserverHand(from: observation.state)
        let judged = expertOptions(observation, ledger: counted)
        guard !judged.isEmpty else { return legal[0] }
        // At lambda 0 the person cannot change the answer; skip scoring them.
        let habits: [GameMove: Double] = lambda == 0 ? [:] : Dictionary(
            personal.candidateScores(observation, ledger: ledger).map { ($0.move, $0.score) },
            uniquingKeysWith: { first, _ in first }
        )
        var best = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for index in judged.indices {
            let move = judged[index].move
            var value = judged[index].score
            if lambda != 0 {
                guard let mine = habits[move] else { preconditionFailure("the person has no score for \(move)") }
                let style = StyleFeatures.of(move, by: observation.seat, in: observation.state)
                value += lambda * (person.beta * mine + person.habit(style))
            }
            if value > bestValue {
                best = index
                bestValue = value
            }
        }
        return judged[best].move
    }

    /// What Expert itself would weigh, scored as Expert scores it.
    ///
    /// Not `candidateScores`, which values every move plainly: that accepted
    /// offers gaining nothing (Expert's `acceptance` refuses them) and proposed
    /// offers below Expert's cascade bar, so lambda 0 was a weaker player than
    /// the Expert tier lambda is calibrated against. This mirrors `best`: the
    /// non-proposal moves `score` accepts, in legal order, then the offers that
    /// clear the bar, Expert's own pick first so ties resolve its way.
    func expertOptions(_ observation: GameObservation, ledger: PublicLedger) -> [ScoredCandidate] {
        let state = observation.state
        let legal = observation.legalMoves
        let evaluator = PositionEvaluator(seat: observation.seat, weights: expert.weights(for: state))
        var purchases = legal.contains(where: { if case .bankTrade = $0 { true } else { false } })
            ? PurchaseGains(valuation: TradeValuation(evaluator: evaluator, state: state, ledger: ledger))
            : nil
        var result: [ScoredCandidate] = []
        for move in legal {
            if case .proposeTrade = move { continue }
            if let value = expert.score(move, state: state, ledger: ledger, evaluator: evaluator, purchases: &purchases) {
                result.append(ScoredCandidate(move: move, score: value))
            }
        }
        guard let pick = expert.cascadeProposal(state: state, ledger: ledger, evaluator: evaluator, legal: legal) else {
            return result
        }
        let others = expert.cascadeOptions(state: state, ledger: ledger, evaluator: evaluator, legal: legal)
            .filter { !$0.offer.sameProposition(as: pick.offer) }
            .filter { option in
                legal.contains(.proposeTrade(option.offer))
                    || RulesEngine.isPermittedComposedProposal(.proposeTrade(option.offer), by: observation.seat,
                                                              in: state, legal: legal)
            }
        return result + [ScoredCandidate(move: .proposeTrade(pick.offer), score: pick.score)]
            + others.map { ScoredCandidate(move: .proposeTrade($0.offer), score: $0.score) }
    }
}
