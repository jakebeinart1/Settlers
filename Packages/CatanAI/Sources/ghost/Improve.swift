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

/// Which decisions `ghost improve` studies.
struct ImproveSampling {
    /// One in this many eligible decisions.
    var oneIn: UInt64 = 40
    /// Every seat's opening settlements instead of a sample of one seat's
    /// decisions. Openings were the most frequent mistake (2026-10-28).
    var openings = false
    /// Only decisions made while the table's dice-roll count is in range:
    /// rolls 11-30 lost the most per decision once openings were fixed.
    var rolls: ClosedRange<Int>?
    /// Also study opponents seated as the same Expert revision. In self-play
    /// every seat is Expert, so this quadruples the decisions per main line.
    var allExpertSeats = false
}

func improve(seed: UInt64, opponents: [String], sampling: ImproveSampling, alternatives: Int, rollouts: Int,
             expert: ExpertRevision) throws -> [ImproveRecord] {
    let line = try ImproveLine(seed: seed, opponents: opponents, expert: expert, allExpertSeats: sampling.allExpertSeats)
    let run = Study(scorer: GhostPolicy(person: .anchored(at: anchor), lambda: 0), seed: seed, table: line.table,
                    alternatives: alternatives, rollouts: rollouts, policies: line.policies)
    var records: [ImproveRecord] = []
    try line.play { session, decision, index, rolls in
        let observation = decision.observation
        var pick = RandomSource(seed: seed &* 1_000_003 &+ UInt64(index))
        let inWindow = sampling.rolls.map { $0.contains(rolls) } ?? true
        let sampled = sampling.openings
            ? { if case .placeInitialSettlement = decision.move { true } else { false } }()
            : line.studied.contains(decision.seat) && inWindow && !isTrade(decision.move)
                && pick.next() % sampling.oneIn == 0
        guard sampled, observation.legalMoves.count > 1 else { return }
        let record: ImproveRecord? = autoreleasepoolIfAvailable {
            try? run.study(session, decision: decision, index: index, rolls: rolls)
        }
        if let record { records.append(record) }
    }
    return records
}

/// The main line `ghost improve` studies: one Expert seat (chair `seed % 4`)
/// and its opponents, played move by move. Deterministic, so `ghost terms`
/// replays it to the same positions the study sampled.
struct ImproveLine {
    let seed: UInt64
    let table: String
    let initial: GameState
    let policies: [PlayerID: any Policy]
    let studied: Set<PlayerID>

    init(seed: UInt64, opponents: [String], expert: ExpertRevision, allExpertSeats: Bool) throws {
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        let first = initial.players[Int(seed % UInt64(initial.players.count))].id
        var policies: [PlayerID: any Policy] = [first: expert.policy]
        var studied: Set<PlayerID> = [first]
        for (player, name) in zip(initial.players.filter { $0.id != first }, opponents) {
            policies[player.id] = try seatPolicy(name)
            if allExpertSeats, name == expert.rawValue { studied.insert(player.id) }
        }
        self.seed = seed
        self.table = opponents.joined(separator: ",")
        self.initial = initial
        self.policies = policies
        self.studied = studied
    }

    /// Calls `body` before each move is committed, with the dice-roll count so far.
    func play(_ body: (GameSession, GameSession.Decision, Int, Int) throws -> Void) throws {
        var session = GameSession(state: initial, policies: policies, policySeed: seed &* 31 &+ 7)
        var rolls = 0
        var index = 0
        while index < 3000, let decision = session.decideNextDetailed() {
            try body(session, decision, index, rolls)
            if decision.move == .rollDice { rolls += 1 }
            _ = try session.commit(seat: decision.seat, move: decision.move)
            index += 1
        }
    }
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
