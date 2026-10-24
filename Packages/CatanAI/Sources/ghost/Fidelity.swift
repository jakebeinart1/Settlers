import CatanAI
import CatanEngine
import Foundation

/// `ghost fidelity`: per pivotal moment, how often the seated policy makes the
/// person's move (exact) and the same sort of move (kind), and where it differs.
func fidelityReport(_ moments: [GhostFidelity.Moment], label: String, detail: Bool) {
    func percent(_ part: Int, _ whole: Int) -> String { String(format: "%5.1f%%", 100 * Double(part) / Double(max(whole, 1))) }
    print("\n== \(label): \(moments.count) moments, exact \(percent(moments.filter(\.exact).count, moments.count))"
          + ", kind \(percent(moments.filter(\.sameKind).count, moments.count))")
    print(pad("situation", 18) + "     n   exact    kind")
    for situation in GhostFidelity.Situation.allCases {
        let here = moments.filter { $0.situations.contains(situation) }
        guard !here.isEmpty else { continue }
        print(pad(situation.rawValue, 18) + String(format: "%6d", here.count) + "  "
              + percent(here.filter(\.exact).count, here.count) + "  " + percent(here.filter(\.sameKind).count, here.count))
        guard detail else { continue }
        var pairs: [String: Int] = [:]
        for moment in here where !moment.sameKind {
            pairs[shortKind(moment.person) + " -> ghost " + shortKind(moment.policy), default: 0] += 1
        }
        for (pair, count) in pairs.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(4) {
            print("      \(count)x  person " + pair)
        }
    }
}

/// Robber kinds carry their hex; in a confusion table only "robber" reads.
private func shortKind(_ move: GameMove) -> String {
    let kind = GhostFidelity.kind(move)
    return kind.hasPrefix("robber") ? "robber" : kind
}

/// Each game is judged by a model fitted without it: games the person made
/// a choice in are dealt into `folds` by id order (as `ghost fit` deals them,
/// so `GHOST_FOLD=k` fits line up), and each fold is played by a model fitted
/// on the rest. `persons[k]`, when given, adds fold k's person model as a feature.
///
/// `personLambda` instead seats fold k's person model alone, at that lambda,
/// as the app seated ghosts before choice models.
func crossValidated(_ games: [LoggedGame], folds: Int, persons: [PersonModel]? = nil,
                    personLambda: Double? = nil) throws -> [GhostFidelity.Moment] {
    let sorted = try games.filter { !(try ChoiceRecord.records(in: $0).isEmpty) }.sorted { $0.id < $1.id }
    var moments: [GhostFidelity.Moment] = []
    for fold in 0..<folds {
        let person = persons?[fold]
        if let person, let personLambda {
            let ghost = GhostPolicy(person: person, lambda: personLambda)
            for index in sorted.indices where index % folds == fold { moments += try GhostFidelity.moments(in: sorted[index], policy: ghost) }
            continue
        }
        let training = try sorted.indices.filter { $0 % folds != fold }
            .flatMap { try ChoiceRecord.records(in: sorted[$0], person: person) }
        let ghost = GhostPolicy(person: person ?? .anchored(at: anchor), lambda: 0, choices: ChoiceFitter.fit(training))
        for index in sorted.indices where index % folds == fold {
            moments += try GhostFidelity.moments(in: sorted[index], policy: ghost)
        }
    }
    return moments
}

/// One line per moment, `game<TAB>situations<TAB>exact<TAB>kind`, for paired comparisons.
func writeOutcomes(_ moments: [GhostFidelity.Moment], to path: String) throws {
    try moments.map { "\($0.game)\t\($0.situations.map(\.rawValue).joined(separator: ","))\t\($0.exact ? 1 : 0)\t\($0.sameKind ? 1 : 0)" }
        .joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
}
