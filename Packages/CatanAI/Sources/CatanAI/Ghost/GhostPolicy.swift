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
    /// See `EvaluationPolicy.handDiscipline`: off only to measure the rule.
    public let handDiscipline: Bool
    /// The person's own choices, once fitted (`ChoiceModel`). When present it
    /// decides, and `lambda` and the person model are not consulted.
    public let choices: ChoiceModel?
    /// With `choices`: the person picks only among moves Expert scores within
    /// this much of its best (`choiceRegret`). `nil` lets the person pick anything.
    public let regret: Double?

    /// How far below Expert's best a ghost may go to play its person's move.
    ///
    /// Unrestricted, a choice ghost copied habits and ignored how good a move
    /// was (the fitted weight on Expert's score was ~0.001): 2,735 of Kbeast's
    /// decisions made a ghost that won 2.2% against three Experts while Kbeast
    /// won 84%, playing 0.2 knights a game to his 2.6. Within this limit it
    /// plays at Expert strength and still matches its person far more often
    /// than Expert does. Measured 2026-10-25, every chair vs three
    /// `pointCompletingCardsV1` Experts, seeds 1200000-1200099, and 4-fold
    /// held-out fidelity: docs/AI_summaries/2026-10-25-ladder-games.md.
    public static let choiceRegret = 0.15
    private let expert = EvaluationPolicy()
    private let personal: EvaluationPolicy

    public init(person: PersonModel, lambda: Double, id: String = "ghost", handDiscipline: Bool = true,
                choices: ChoiceModel? = nil, regret: Double? = GhostPolicy.choiceRegret) {
        self.id = id
        self.handDiscipline = handDiscipline
        self.person = person
        self.lambda = lambda
        self.choices = choices
        self.regret = regret
        self.personal = EvaluationPolicy(weights: EvaluationWeights(vector: person.weights))
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let legal = observation.legalMoves
        guard legal.count > 1 else { return legal[0] }
        if legal.contains(.rollDice) { return choices == nil ? .rollDice : beforeTheRoll(observation) }
        var counted = ledger
        counted.reconcileObserverHand(from: observation.state)
        let judged = expertOptions(observation, ledger: counted)
        guard !judged.isEmpty else { return legal[0] }
        if let choices {
            let person = choices.needsPerson ? personScores(observation, ledger: ledger) : nil
            let top = judged.map(\.score).max() ?? 0
            let allowed = regret.map { limit in judged.filter { $0.score >= top - limit } } ?? judged
            return disciplined(choices.choose(allowed, seat: observation.seat, state: observation.state, person: person),
                               judged: judged, observation: observation)
        }
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
        return disciplined(judged[best].move, judged: judged, observation: observation)
    }

    /// The person model's value per move, the term `lambda` scales:
    /// `beta · S_person + theta · style`.
    public func personScores(_ observation: GameObservation, ledger: PublicLedger) -> [GameMove: Double] {
        Dictionary(personal.candidateScores(observation, ledger: ledger).map { candidate in
            (candidate.move, person.beta * candidate.score
                + person.habit(StyleFeatures.of(candidate.move, by: observation.seat, in: observation.state)))
        }, uniquingKeysWith: { first, _ in first })
    }

    private func disciplined(_ move: GameMove, judged: [ScoredCandidate], observation: GameObservation) -> GameMove {
        handDiscipline && move == .endTurn && HandDiscipline.mustSpend(observation.seat, in: observation.state)
            ? spendDown(judged) ?? .endTurn
            : move
    }

    /// Roll, unless a knight wins the game now. Jake played 8 knights before
    /// the dice in 136 chances across 25 games, with no situation that
    /// predicted them on games left out of the fit (robber on his own hex
    /// did not); always rolling matched him 94% of the time, every fitted
    /// rule less.
    private func beforeTheRoll(_ observation: GameObservation) -> GameMove {
        observation.legalMoves.first {
            TimingPolicy.isKnight($0) && TimingPolicy.wins($0, observation.seat, observation.state)
        } ?? .rollDice
    }

    /// Expert's best spending move, when the ghost would otherwise end a turn
    /// over the discard threshold (`HandDiscipline`).
    ///
    /// Expert's judgement alone, not the person's: this is where the person's
    /// habits did the damage. Jake's model carries -1.3 on bank trades and
    /// -0.7 on ending the turn, and at a 0.014 margin that difference was the
    /// whole decision, eight turns running.
    private func spendDown(_ judged: [ScoredCandidate]) -> GameMove? {
        judged.filter { HandDiscipline.spends($0.move) }.max { $0.score < $1.score }?.move
    }

    /// What Expert itself would weigh, scored as Expert scores it.
    ///
    /// Not `candidateScores`, which values every move plainly: that accepted
    /// offers gaining nothing (Expert's `acceptance` refuses them) and proposed
    /// offers below Expert's cascade bar, so lambda 0 was a weaker player than
    /// the Expert tier lambda is calibrated against. This mirrors `best`: the
    /// non-proposal moves `score` accepts, in legal order, then the offers that
    /// clear the bar, Expert's own pick first so ties resolve its way.
    public func expertOptions(_ observation: GameObservation, ledger: PublicLedger) -> [ScoredCandidate] {
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
