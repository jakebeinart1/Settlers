import CatanAI
import CatanEngine
import Foundation

/// A person who samples from a known `PersonModel`. The recovery test: if the
/// fit cannot find this person's weights and habits in real games, it will not
/// find Jake's.
struct SamplingPersona: LedgerAwarePolicy {
    let id = "persona"
    let person: PersonModel

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let legal = observation.legalMoves
        guard legal.count > 1 else { return legal[0] }
        if legal.contains(.rollDice) { return .rollDice }
        let scored = EvaluationPolicy(weights: EvaluationWeights(vector: person.weights))
            .candidateScores(observation, ledger: ledger)
        guard !scored.isEmpty else { return legal[0] }
        let logits = scored.map { candidate in
            person.beta * candidate.score
                + person.habit(StyleFeatures.of(candidate.move, by: observation.seat, in: observation.state))
        }
        let top = logits.max()!
        let weights = logits.map { exp($0 - top) }
        var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
        for (index, weight) in weights.enumerated() {
            if roll < weight { return scored[index].move }
            roll -= weight
        }
        return scored[scored.count - 1].move
    }
}

/// The persona the pipeline has to find: likes production, proposes often, robs the leader.
func selftestPersona() -> PersonModel {
    var person = PersonModel.anchored(at: .forMode(.classic))
    person.weights[1] += 0.25
    person.beta = 4
    person.theta[StyleFeatures.labels.firstIndex(of: "propose")!] = 1.0
    person.theta[StyleFeatures.labels.firstIndex(of: "robberHitsLeader")!] = 1.5
    return person
}

/// Full games against shipping heuristic bots, the persona's chair rotating.
func selftestGames(count: Int, seed: UInt64) throws -> [LoggedGame] {
    try (0..<count).map { number in
        let gameSeed = seed + UInt64(number)
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: gameSeed), seed: gameSeed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = HeuristicPolicy(personality: .balanced, id: "balanced") }
        let human = initial.players[number % initial.players.count].id
        policies[human] = SamplingPersona(person: selftestPersona())
        var session = GameSession(state: initial, policies: policies, policySeed: gameSeed)
        var events: [LoggedMove] = []
        while let step = try session.step() { events.append(LoggedMove(player: step.actor, move: step.move)) }
        return LoggedGame(id: "selftest-\(gameSeed)", initialState: initial, humanSeats: [human], events: events)
    }
}
