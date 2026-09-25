import CatanAI
import CatanEngine
import Foundation

// A model of one person from their recorded games, and its ghost.
//
// Usage:
//   ghost extract --out decisions.jsonl LOG.jsonl...   (one human seat per game; others skipped)
//   ghost profile decisions.jsonl                        (what this person does, per facet)
//   ghost fit --out person.json [--rounds 3] LOG.jsonl...   (fit on 3/4 of games, report on the held-out 1/4)
//   ghost selftest [--games 12] [--seed 700000] [--rounds 3] (recover a known synthetic person)

// Line-buffered so a run that dies still leaves its progress: the first
// selftest crashed after 19 minutes with an empty log.
// Darwin only: under Linux Swift 6, `stdout` is a global var the compiler
// rejects as not concurrency-safe, and CI builds every target there.
#if canImport(Darwin)
setvbuf(stdout, nil, _IOLBF, 0)
#endif

let anchor = EvaluationWeights.forMode(.classic)
var arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

@MainActor func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

/// Left-aligned in `width` columns. `String(format:)` with `%@` is not portable to Linux.
func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func number(_ value: Double) -> String { String(format: "%8.3f", value) }

func writeDecisions(_ records: [DecisionRecord], to path: String) throws {
    let encoder = JSONEncoder()
    var data = Data()
    for record in records {
        data.append(try encoder.encode(record))
        data.append(0x0A)
    }
    try data.write(to: URL(fileURLWithPath: path))
}

func readDecisions(_ path: String) throws -> [DecisionRecord] {
    try String(contentsOfFile: path, encoding: .utf8).split(separator: "\n")
        .map { try JSONDecoder().decode(DecisionRecord.self, from: Data($0.utf8)) }
}

/// Review Focus 3: a hot-seat game mixes several people, so it is skipped out loud.
func extract(_ games: [LoggedGame], at weights: EvaluationWeights = anchor,
             humanTrading: Bool = true) throws -> [DecisionRecord] {
    var records: [DecisionRecord] = []
    for game in games.sorted(by: { $0.id < $1.id }) {
        guard game.humanSeats.count == 1 else {
            print("skip \(game.id): \(game.humanSeats.count) human seats; a ghost is one person")
            continue
        }
        let found = try DecisionExtractor.decisions(in: game, anchor: weights, humanTrading: humanTrading)
        print("\(game.id): \(found.count) decisions")
        records += found
    }
    return records
}

/// Every fourth game, in id order, is held out: deterministic, and whole games, not decisions.
func split(_ records: [DecisionRecord]) -> (train: [DecisionRecord], heldOut: [DecisionRecord]) {
    let games = Array(Set(records.map(\.game))).sorted()
    let heldOut = Set(games.enumerated().filter { $0.offset % 4 == 3 }.map(\.element))
    return (records.filter { !heldOut.contains($0.game) }, records.filter { heldOut.contains($0.game) })
}

func report(_ fitted: PersonModel, heldOut: [DecisionRecord]) {
    let expert = PersonModel.anchored(at: anchor)
    print(pad("facet", 14) + "     n  expert-top1 person-top1  expert-ll  person-ll")
    for facet in Facet.allCases {
        let decisions = heldOut.filter { $0.facet == facet }
        guard !decisions.isEmpty else { continue }
        print(pad(facet.rawValue, 14) + String(format: "%6d", decisions.count)
              + "    " + number(expert.top1Accuracy(decisions)) + "    " + number(fitted.top1Accuracy(decisions))
              + "   " + number(expert.meanLogLikelihood(decisions)) + "   " + number(fitted.meanLogLikelihood(decisions)))
    }
    print("beta " + number(fitted.beta))
    for (label, value) in zip(StyleFeatures.labels, fitted.theta) { print("habit  " + pad(label, 22) + number(value)) }
    for (slot, label) in EvaluationWeights.vectorLabels.enumerated() where fitted.weights[slot] != anchor.vector[slot] {
        print("weight " + pad(label, 22) + number(anchor.vector[slot]) + " -> " + number(fitted.weights[slot]))
    }
}

/// Review Focus 5: how far the linearised score is from an exact re-score at
/// the fitted weights, on the first two games.
func linearisationDrift(_ fitted: PersonModel, _ records: [DecisionRecord], games: [LoggedGame],
                        humanTrading: Bool) throws -> Double {
    let sample = Array(games.sorted { $0.id < $1.id }.prefix(2))
    let exact = try sample.flatMap {
        try DecisionExtractor.decisions(in: $0, anchor: EvaluationWeights(vector: fitted.weights), humanTrading: humanTrading)
    }
    let linear = records.filter { record in sample.contains { $0.id == record.game } }
    var total = 0.0
    var count = 0
    for (lin, ex) in zip(linear, exact) {
        for (lc, ec) in zip(lin.candidates, ex.candidates) {
            total += abs(fitted.personalScore(lc, anchor: lin.anchor) - ec.score)
            count += 1
        }
    }
    return count > 0 ? total / Double(count) : 0
}

/// Fit, then re-linearise at the fitted weights and fit again.
///
/// One linearisation at Expert's weights cannot reach a person far from
/// Expert: measured on the selftest persona (production 54% above Expert),
/// a single round left drift at 0.122 and moved production the wrong way.
/// The prior still pulls toward Expert every round; only the point the
/// slopes are taken at moves.
func relinearisedFit(_ games: [LoggedGame], rounds: Int,
                     humanTrading: Bool = true) throws -> (PersonModel, heldOut: [DecisionRecord]) {
    guard rounds >= 1 else { fail("--rounds must be at least 1") }
    var person = PersonModel.anchored(at: anchor)
    var heldOut: [DecisionRecord] = []
    for round in 1...rounds {
        let records = try extract(games, at: EvaluationWeights(vector: person.weights), humanTrading: humanTrading)
        let parts = split(records)
        person = PersonFitter.fit(parts.train, anchor: anchor, start: person)
        heldOut = parts.heldOut
        let drift = try linearisationDrift(person, records, games: games, humanTrading: humanTrading)
        print("round \(round): trained on \(parts.train.count), held out \(parts.heldOut.count), drift" + number(drift))
    }
    return (person, heldOut)
}

func profile(_ records: [DecisionRecord]) {
    for facet in Facet.allCases {
        let decisions = records.filter { $0.facet == facet }
        guard !decisions.isEmpty else { continue }
        print("\(facet.rawValue): \(decisions.count) decisions")
        for (feature, label) in StyleFeatures.labels.enumerated() {
            let mean = decisions.reduce(0) { $0 + $1.candidates[$1.chosen].style[feature] } / Double(decisions.count)
            if mean != 0 { print("  " + pad(label, 22) + number(mean) + " per decision") }
        }
    }
}

guard let command = arguments.first else { fail("usage: ghost extract|profile|fit|selftest") }
arguments.removeFirst()

switch command {
case "extract":
    guard let out = option("--out") else { fail("extract needs --out") }
    let records = try extract(try arguments.map { try loadGame(URL(fileURLWithPath: $0)) })
    try writeDecisions(records, to: out)
    print("\(records.count) decisions -> \(out)")
case "profile":
    guard let path = arguments.first else { fail("profile needs a decisions file") }
    profile(try readDecisions(path))
case "fit":
    guard let out = option("--out") else { fail("fit needs --out and log files") }
    let rounds = Int(option("--rounds") ?? "3") ?? 3
    // Not filtered here: `extract` skips multi-human games out loud, every round.
    let games = try arguments.map { try loadGame(URL(fileURLWithPath: $0)) }
    let (fitted, heldOut) = try relinearisedFit(games, rounds: rounds)
    try JSONEncoder().encode(fitted).write(to: URL(fileURLWithPath: out))
    report(fitted, heldOut: heldOut)
case "selftest":
    let count = Int(option("--games") ?? "12") ?? 12
    let seed = UInt64(option("--seed") ?? "700000") ?? 700_000
    let rounds = Int(option("--rounds") ?? "3") ?? 3
    let games = try selftestGames(count: count, seed: seed)
    let truth = selftestPersona()
    // The persona is a GameSession bot, so it is read under bot trading rules.
    let (fitted, heldOut) = try relinearisedFit(games, rounds: rounds, humanTrading: false)
    let heldOutGames = Set(heldOut.map(\.game))
    // The true person scored on its own exact scores, not a linearisation of them.
    let exactTruth = try extract(games.filter { heldOutGames.contains($0.id) },
                                 at: EvaluationWeights(vector: truth.weights), humanTrading: false)
    print("\nTRUE person:")
    report(truth, heldOut: exactTruth)
    print("\nFITTED person:")
    report(fitted, heldOut: heldOut)
default:
    fail("unknown command \(command)")
}
