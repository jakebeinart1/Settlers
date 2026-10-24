import CatanEngine
import Foundation

/// A person's choices as two steps: what sort of move, then which one.
///
/// ## Why two steps
/// One flat choice over every option let ten knight placements outvote one
/// roll: before the dice, a flat fit played a knight Jake would not have,
/// and its pre-roll agreement fell from 94% to 54%. People decide "trade,
/// build or end" first and "which one" second, and fitting it that way
/// scored best on games left out of the fit (`ghost fidelity`, 2026-10-24).
///
/// ## Why not the person model
/// `PersonModel` reweights Expert's position score. That cannot express
/// "robs a 6 or 8" or "trades from the biggest pile": Expert's score has no
/// such term, so no reweighting reaches it. On Jake's held-out games this
/// model matched his move 64% of the time, the person model 60% on games
/// it had already seen, and Expert 29%.
public struct ChoiceModel: Codable, Sendable, Equatable {
    /// Weight per `ChoiceFeatures.kindRows` feature.
    public var kinds: [String: Double]
    /// Per family, weight per `ChoiceFeatures.optionRow` feature. A family
    /// with too few examples has none, and Expert picks within it.
    public var families: [String: [String: Double]]
    /// How many decisions it was fitted on.
    public var decisions: Int

    public init(kinds: [String: Double], families: [String: [String: Double]], decisions: Int) {
        self.kinds = kinds
        self.families = families
        self.decisions = decisions
    }

    /// Whether it was fitted with the person model's value as a feature, so
    /// choosing needs `GhostPolicy.personScores`.
    public var needsPerson: Bool {
        kinds["person"] != nil || families.values.contains { $0["person"] != nil }
    }

    public func choose(_ options: [ScoredCandidate], seat: PlayerID, state: GameState,
                       person: [GameMove: Double]? = nil) -> GameMove {
        let (kinds, rows) = ChoiceFeatures.kindRows(options, seat: seat, state: state, person: person)
        let kind = kinds[Self.argmax(rows.map { Self.dot($0, self.kinds) })]
        let mine = options.filter { ChoiceFeatures.kind($0.move) == kind }
        guard mine.count > 1 else { return mine[0].move }
        guard let weights = families[ChoiceFeatures.family(kind)] else { return mine[Self.argmax(mine.map(\.score))].move }
        let mineRows = ChoiceRecord.optionRows(mine, among: options, seat: seat, state: state, person: person)
        return mine[Self.argmax(mineRows.map { Self.dot($0, weights) })].move
    }

    /// Summed in key order: a `Dictionary`'s order changes between launches,
    /// and a float sum in a different order can break a tie the other way.
    static func dot(_ row: [String: Double], _ weights: [String: Double]) -> Double {
        row.keys.sorted().reduce(0) { $0 + row[$1]! * (weights[$1] ?? 0) }
    }

    /// The first best, so ties go to the earlier option as in `EvaluationPolicy.best`.
    static func argmax(_ values: [Double]) -> Int {
        values.indices.max { values[$0] < values[$1] }!
    }
}

/// One decision a person made, as the two steps see it.
public struct ChoiceRecord: Codable, Sendable, Equatable {
    public let kindRows: [[String: Double]]
    /// `nil` when the person's kind of move was not on offer to a bot seat
    /// (a free-form trade offer after the bot's three refusals).
    public let chosenKind: Int?
    public let family: String
    /// The options of the person's kind; empty when there was only one.
    public let optionRows: [[String: Double]]
    /// `nil` when the person's exact move was not among them.
    public let chosen: Int?

    public init(options: [ScoredCandidate], person move: GameMove, seat: PlayerID, state: GameState,
                personScores: [GameMove: Double]? = nil) {
        let (kinds, rows) = ChoiceFeatures.kindRows(options, seat: seat, state: state, person: personScores)
        let kind = ChoiceFeatures.kind(move)
        let mine = options.filter { ChoiceFeatures.kind($0.move) == kind }
        kindRows = rows
        chosenKind = kinds.firstIndex(of: kind)
        family = ChoiceFeatures.family(kind)
        optionRows = mine.count > 1 ? Self.optionRows(mine, among: options, seat: seat, state: state, person: personScores) : []
        chosen = mine.firstIndex { GhostFidelity.matches($0.move, move) }
    }

    /// `mine` against each other; Expert's and the person's values are taken
    /// relative to the best of every option on offer.
    static func optionRows(_ mine: [ScoredCandidate], among options: [ScoredCandidate], seat: PlayerID,
                           state: GameState, person: [GameMove: Double]?) -> [[String: Double]] {
        let top = options.map(\.score).max() ?? 0
        let personTop = person.map { scores in options.compactMap { scores[$0.move] }.max() ?? 0 }
        return mine.map { option in
            let value = personTop.flatMap { top in person?[option.move].map { $0 - top } }
            return ChoiceFeatures.optionRow(option, top: top, seat: seat, state: state, person: value)
        }
    }
}

/// Maximum-likelihood fit of a `ChoiceModel`: a conditional logit per step,
/// pulled toward zero (no habit).
public enum ChoiceFitter {
    /// Chosen on Jake's games by held-out agreement (`ghost fidelity`); flat
    /// from 10 to 100 for kinds and 1 to 3 for families.
    public static let kindPrior = 10.0
    public static let familyPrior = 1.0
    /// A family needs this many examples before its habits replace Expert's pick.
    public static let familyMinimum = 3
    /// Below this many decisions (about three of Jake's games) a ghost keeps
    /// playing by its person model: a kind choice fitted on less wanders.
    public static let minimumDecisions = 100
    static let iterations = 2000
    static let learningRate = 0.05

    public static func fit(_ records: [ChoiceRecord], kindPrior: Double = kindPrior,
                           familyPrior: Double = familyPrior) -> ChoiceModel {
        let kindProblems = records.compactMap { record in
            record.chosenKind.flatMap { record.kindRows.count > 1 ? (record.kindRows, $0) : nil }
        }
        var families: [String: [String: Double]] = [:]
        for family in Set(records.map(\.family)).sorted() {
            let problems = records.filter { $0.family == family }.compactMap { record in
                record.chosen.flatMap { record.optionRows.count > 1 ? (record.optionRows, $0) : nil }
            }
            if problems.count >= familyMinimum { families[family] = logit(problems, prior: familyPrior) }
        }
        return ChoiceModel(kinds: logit(kindProblems, prior: kindPrior), families: families, decisions: records.count)
    }

    /// Minimises `-sum log P(chosen) + prior * |w|^2`, `P` a softmax over each problem's rows.
    static func logit(_ problems: [(rows: [[String: Double]], chosen: Int)], prior: Double) -> [String: Double] {
        let names = Set(problems.flatMap { $0.rows.flatMap(\.keys) }).sorted()
        guard !names.isEmpty else { return [:] }
        let index = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })
        // Sparse, in slot order so every sum runs in the same order on every launch.
        let sparse = problems.map { problem in
            (problem.rows.map { row in row.map { (index[$0.key]!, $0.value) }.sorted { $0.0 < $1.0 } }, problem.chosen)
        }
        var weights = [Double](repeating: 0, count: names.count)
        var adam = Adam(count: names.count)
        for _ in 0..<iterations {
            var gradient = weights.map { 2 * prior * $0 }
            for (rows, chosen) in sparse { accumulate(&gradient, rows: rows, chosen: chosen, weights: weights) }
            adam.step(&weights, gradient, rate: learningRate)
        }
        return Dictionary(uniqueKeysWithValues: zip(names, weights).filter { $0.1 != 0 })
    }

    private static func accumulate(_ gradient: inout [Double], rows: [[(Int, Double)]], chosen: Int, weights: [Double]) {
        let logits = rows.map { row in row.reduce(0) { $0 + weights[$1.0] * $1.1 } }
        let top = logits.max() ?? 0
        let exps = logits.map { exp($0 - top) }
        let total = exps.reduce(0, +)
        for (row, weight) in zip(rows, exps) {
            for (slot, value) in row { gradient[slot] += weight / total * value }
        }
        for (slot, value) in rows[chosen] { gradient[slot] -= value }
    }
}

extension ChoiceRecord {
    /// The person's choices in one game, as a bot seat would have seen them.
    /// Before-the-roll choices are left out: the ghost rolls (`GhostPolicy`).
    /// With `person`, each option also carries that person model's value.
    public static func records(in game: LoggedGame, person: PersonModel? = nil) throws -> [ChoiceRecord] {
        let ghost = GhostPolicy(person: person ?? .anchored(at: .forMode(.classic)), lambda: 0)
        var result: [ChoiceRecord] = []
        try GhostFidelity.forEachDecision(in: game) { observation, ledger, move in
            guard !observation.legalMoves.contains(.rollDice) else { return }
            var counted = ledger
            counted.reconcileObserverHand(from: observation.state)
            let options = ghost.expertOptions(observation, ledger: counted)
            guard !options.isEmpty else { return }
            result.append(ChoiceRecord(options: options, person: move, seat: observation.seat, state: observation.state,
                                       personScores: person == nil ? nil : ghost.personScores(observation, ledger: ledger)))
        }
        return result
    }
}
