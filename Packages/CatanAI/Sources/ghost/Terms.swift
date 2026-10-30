import CatanAI
import CatanEngine
import Foundation

/// `ghost terms`: what each branch of a `ghost improve` decision did to
/// Expert's evaluation, term by term, so rollout wins can be regressed on
/// the terms and the weights read off what the rollouts say each is worth.
///
/// The study's main line is replayed (`ImproveLine` is deterministic) to each
/// recorded decision, every branch is applied, and the position after it is
/// scored once per `EvaluationWeights` term with that term's weight at 1 and
/// the rest at 0: this seat's standing less `rival` times the strongest
/// rival's, the rival picked under the shipping weights, as `evaluate` does.
struct TermsRecord: Encodable {
    let seed: UInt64
    let index: Int
    let rolls: Int
    let branch: Int
    let kind: String
    let wins: Int
    let rollouts: Int
    let features: [String: Double]
}

/// The fields `ghost terms` reads back from an `ImproveRecord` line.
private struct StudiedDecision: Decodable {
    struct Branch: Decodable {
        let move: String
        let kind: String
        let wins: Int
    }
    let seed: UInt64
    let table: String
    let index: Int
    let rolls: Int
    let chosen: Branch
    let alternatives: [Branch]
    let rollouts: Int
}

/// The linear terms of `PositionEvaluator.standing`, by weight.
nonisolated(unsafe) private let termWeights: [(String, WritableKeyPath<EvaluationWeights, Double>)] = [
    ("victoryPoint", \.victoryPoint), ("production", \.production), ("variety", \.variety),
    ("expansion", \.expansion), ("approach", \.approach), ("buildableSites", \.buildableSites),
    ("handSynergy", \.handSynergy), ("handCard", \.handCard), ("handCardOverflow", \.handCardOverflow),
    ("discardExposure", \.discardExposure), ("sevenLoss", \.sevenLoss), ("devCardHeld", \.devCardHeld),
    ("knight", \.knight), ("roadLength", \.roadLength), ("port", \.port)
]

func terms(lines: [String], expert: ExpertRevision) throws -> [TermsRecord] {
    let decisions = try lines.filter { $0.hasPrefix("{") }
        .map { try JSONDecoder().decode(StudiedDecision.self, from: Data($0.utf8)) }
    let games = Dictionary(grouping: decisions) { "\($0.seed) \($0.table)" }
    var records: [TermsRecord] = []
    for key in games.keys.sorted() {
        let studied = Dictionary(uniqueKeysWithValues: games[key]!.map { ($0.index, $0) })
        let first = games[key]![0]
        let line = try ImproveLine(seed: first.seed, opponents: first.table.split(separator: ",").map(String.init),
                                   expert: expert, allExpertSeats: true)
        try line.play { session, decision, index, _ in
            guard let wanted = studied[index] else { return }
            autoreleasepoolIfAvailable {
                records += branchTerms(wanted, session: session, seat: decision.seat,
                                       legal: decision.observation.legalMoves)
            }
        }
    }
    return records
}

private func branchTerms(_ wanted: StudiedDecision, session: GameSession, seat: PlayerID,
                         legal: [GameMove]) -> [TermsRecord] {
    let branches = [wanted.chosen] + wanted.alternatives
    return branches.enumerated().compactMap { offset, branch in
        guard let move = legal.first(where: { String(describing: $0) == branch.move }),
              let features = try? positionTerms(after: move, session: session, seat: seat) else { return nil }
        return TermsRecord(seed: wanted.seed, index: wanted.index, rolls: wanted.rolls, branch: offset,
                           kind: branch.kind, wins: branch.wins, rollouts: wanted.rollouts, features: features)
    }
}

/// Each term of the position after `move`. A bought card is scored as the
/// card it is unless it is a hidden point, which the rollouts (fresh deck per
/// rollout) mostly did not draw; it is then counted as a non-point card.
private func positionTerms(after move: GameMove, session: GameSession, seat: PlayerID) throws -> [String: Double] {
    var next = session
    _ = try next.applyExternal(move, by: seat)
    let state = next.state
    if case .gameOver = state.phase { return ["won": 1] }
    var ledger = next.ledger(for: seat)
    ledger.reconcileObserverHand(from: state)
    let board = BoardIndex(state: state)
    let shipping = EvaluationWeights.forMode(state.mode)
    let full = PositionEvaluator(seat: seat, weights: shipping, revision: .pointCompletingCardsV1)
    let strongest = state.players.map(\.id).filter { $0 != seat }.sorted()
        .max { full.standing(of: $0, in: state, ledger: ledger, board: board)
            < full.standing(of: $1, in: state, ledger: ledger, board: board) }
    func term(_ weights: EvaluationWeights, revision: ExpertRevision = .legacy) -> Double {
        let unit = PositionEvaluator(seat: seat, weights: weights, revision: revision)
        let rival = strongest.map { unit.standing(of: $0, in: state, ledger: ledger, board: board) } ?? 0
        return unit.standing(of: seat, in: state, ledger: ledger, board: board) - shipping.rival * rival
    }
    var zero = EvaluationWeights.forMode(state.mode)
    for (_, path) in termWeights { zero[keyPath: path] = 0 }
    var features: [String: Double] = [:]
    for (name, path) in termWeights {
        var unit = zero
        unit[keyPath: path] = 1
        features[name] = term(unit)
    }
    features["cityProduction"] = term(zero, revision: .pointCompletingCardsV1)
    let bought = state.devCardsBoughtThisTurn[seat] ?? []
    if case .buyDevCard = move, bought.last == .victoryPoint { features["victoryPoint", default: 0] -= 1 }
    return features
}
