import CatanAI
import CatanEngine
import Foundation

/// `ghost improve`: where Expert's own play loses. One Expert seat (chair
/// `seed % 4`) plays a table of `opponents` (`ghost duel` seat names: itself,
/// older Experts, fitted ghosts); at a sample of that seat's decisions, its chosen move and its next-best alternatives
/// are each played out `rollouts` times (every seat keeps its own policy, the
/// same dice per rollout across branches, as in `ghost shoes`). A decision
/// where an alternative wins measurably more is a mistake Expert makes, found
/// in Expert's own games rather than in any one person's.
///
/// Alternatives come from `GhostPolicy.expertOptions`, Expert's scored
/// candidate list. A decision whose position cannot be rebuilt is skipped.
/// Moves Expert never lists cannot be found this way; human
/// games (`ghost shoes`) are where those come from.
struct ImproveRecord: Encodable {
    struct Branch: Encodable {
        let move: String
        let kind: String
        /// Expert's own score for the move; nil for the chosen move when the
        /// candidate list does not contain it (pre-roll, timing overrides).
        let score: Double?
        let wins: Int
        /// For an opening settlement: what the spot is, for fitting placement.
        let features: [String: Double]?
    }
    let seed: UInt64
    let table: String
    let index: Int
    let seat: Int
    let rolls: Int
    let publicVP: Int
    let situations: [GhostFidelity.Situation]
    let chosen: Branch
    let alternatives: [Branch]
    let rollouts: Int
}

/// `openings`: every seat's opening settlements instead of a sample of one
/// seat's decisions. Openings were the most frequent mistake (2026-10-28).
func improve(seed: UInt64, opponents: [String], sampleOneIn: UInt64, alternatives: Int, rollouts: Int,
             expert: ExpertRevision, openings: Bool = false) throws -> [ImproveRecord] {
    let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
    let studied = initial.players[Int(seed % UInt64(initial.players.count))].id
    var policies: [PlayerID: any Policy] = [studied: expert.policy]
    for (player, name) in zip(initial.players.filter { $0.id != studied }, opponents) {
        policies[player.id] = try seatPolicy(name)
    }
    let table = opponents.joined(separator: ",")
    var session = GameSession(state: initial, policies: policies, policySeed: seed &* 31 &+ 7)
    let run = Study(scorer: GhostPolicy(person: .anchored(at: anchor), lambda: 0), seed: seed, table: table,
                    alternatives: alternatives, rollouts: rollouts, policies: policies)
    var records: [ImproveRecord] = []
    var rolls = 0
    var index = 0
    while index < 3000, let decision = session.decideNextDetailed() {
        let observation = decision.observation
        var pick = RandomSource(seed: seed &* 1_000_003 &+ UInt64(index))
        let sampled = openings
            ? { if case .placeInitialSettlement = decision.move { true } else { false } }()
            : decision.seat == studied && !isTrade(decision.move) && pick.next() % sampleOneIn == 0
        if sampled, observation.legalMoves.count > 1 {
            let record: ImproveRecord? = autoreleasepoolIfAvailable {
                try? run.study(session, decision: decision, index: index, rolls: rolls)
            }
            if let record { records.append(record) }
        }
        if decision.move == .rollDice { rolls += 1 }
        _ = try session.commit(seat: decision.seat, move: decision.move)
        index += 1
    }
    return records
}

/// A refused offer changes nothing and Expert makes its real move next step,
/// so both branches play the same game: offers and replies carry no signal
/// here. Replies also arrive queued, which a checkpoint cannot always rebuild.
private func isTrade(_ move: GameMove) -> Bool {
    switch move {
    case .proposeTrade, .respondToTrade: true
    default: false
    }
}

/// One table's settings for studying a decision.
private struct Study {
    let scorer: GhostPolicy
    let seed: UInt64
    let table: String
    let alternatives: Int
    let rollouts: Int
    let policies: [PlayerID: any Policy]

    func study(_ session: GameSession, decision: GameSession.Decision, index: Int, rolls: Int) throws -> ImproveRecord? {
        let observation = decision.observation
        let ranked = scorer.expertOptions(observation, ledger: session.ledger(for: decision.seat))
            .sorted { $0.score > $1.score }
        let others = ranked.filter { !isTrade($0.move) && !GhostFidelity.matches($0.move, decision.move)
            && !GhostFidelity.matches(decision.move, $0.move) }
            .prefix(alternatives)
        guard !others.isEmpty else { return nil }
        func wins(_ move: GameMove) throws -> Int {
            var total = 0
            for rollout in 0..<rollouts {
                let rolloutSeed = seed &* 7_919 &+ UInt64(index) &* 1_000_003 &+ UInt64(rollout)
                if try playOut(session, first: move, seat: decision.seat, seed: rolloutSeed, policies: policies) { total += 1 }
            }
            return total
        }
        let chosenScore = ranked.first { GhostFidelity.matches($0.move, decision.move) }?.score
        return ImproveRecord(
            seed: seed, table: table, index: index, seat: decision.seat.index, rolls: rolls,
            publicVP: session.state.publicVictoryPoints(for: decision.seat),
            situations: GhostFidelity.situations(session.state, legal: observation.legalMoves),
            chosen: .init(move: String(describing: decision.move), kind: GhostFidelity.kind(decision.move),
                          score: chosenScore, wins: try wins(decision.move),
                          features: spotFeatures(decision.move, session.state, decision.seat)),
            alternatives: try others.map {
                .init(move: String(describing: $0.move), kind: GhostFidelity.kind($0.move), score: $0.score,
                      wins: try wins($0.move), features: spotFeatures($0.move, session.state, decision.seat))
            },
            rollouts: rollouts)
    }
}

/// An opening settlement's spot: pips per resource it touches, the seat's
/// pips already owned per resource, its port, and whether it is the second
/// placement. Nil for any other move.
private func spotFeatures(_ move: GameMove, _ state: GameState, _ seat: PlayerID) -> [String: Double]? {
    guard case .placeInitialSettlement(let vertex) = move else { return nil }
    let pips = { OpeningPolicy.pips(at: $0, state) }
    var features: [String: Double] = [:]
    let spot = pips(vertex)
    let owned = state.players[seat.index].settlements.sorted().map(pips)
    for resource in Resource.allCases {
        features["pips_\(resource)"] = Double(spot[resource] ?? 0)
        features["owned_\(resource)"] = Double(owned.reduce(0) { $0 + ($1[resource] ?? 0) })
    }
    if let port = state.board.ports.first(where: { $0.vertexA == vertex || $0.vertexB == vertex }) {
        features["port_\(port.kind)"] = 1
    }
    features["second"] = owned.isEmpty ? 0 : 1
    return features
}
