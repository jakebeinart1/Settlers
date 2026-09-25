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
        let judged = expert.candidateScores(observation, ledger: ledger)
        guard !judged.isEmpty else { return legal[0] }
        // At lambda 0 the person cannot change the answer; skip scoring them.
        let habits = lambda == 0 ? judged : personal.candidateScores(observation, ledger: ledger)
        var best = 0
        var bestValue = -Double.greatestFiniteMagnitude
        for index in judged.indices {
            let style = StyleFeatures.of(judged[index].move, by: observation.seat, in: observation.state)
            let habit = person.beta * habits[index].score + person.habit(style)
            let value = judged[index].score + lambda * habit
            if value > bestValue {
                best = index
                bestValue = value
            }
        }
        return judged[best].move
    }
}
