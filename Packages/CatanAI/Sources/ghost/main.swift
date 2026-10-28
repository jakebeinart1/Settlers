import CatanAI
import CatanEngine
import Foundation

// A model of one person from their recorded games, and its ghost.
//
// Usage:
//   ghost extract --out decisions.jsonl LOG.jsonl...   (one human seat per game; others skipped)
//   ghost profile decisions.jsonl                        (what this person does, per facet)
//   ghost fit --out person.json [--rounds 3] LOG.jsonl...   (fit on 3/4 of games, report on the held-out 1/4)
//   ghost calibrate --person P.json --target 0.54 [--games 40] [--tier classic|expert] [--lambdas 0,0.05,0.1]
//   ghost strength --person P.json --lambda L [--games 1248] [--tier expert]
//   ghost bundle --person P.json --lambda L --id jake --name "Jake's Ghost" --games-learned 24 --decisions-learned 2612
//                [--civilization greece] --out Settlers/Resources/Ghosts/jake.json
//   ghost baseline [--games 200] [--policy classic]     (self-play averages: the spider graph's reference, and the AI rows' own graphs)
//   ghost timing --person P.json --lambda L                (one game: ghost move time, then one retrain)
//   ghost selftest [--games 12] [--seed 700000] [--rounds 3] (recover a known synthetic person)
//   ghost fidelity [--cv 4 | --profile G.json | --choices C.json] [--detail] LOG...  (does the ghost make the person's moves?)
//   ghost choices --out C.json LOG...                   (fit a person's choice model)
//   ghost candidates --out cands.jsonl LOG...           (every option at each decision, for study)
//   ghost duel --candidate C --anchor A --seed S --seeds N [--lone] [--shard i/n]   (C in every chair vs three A)
//   ghost ladder GAME.json...                           (every seat of ranked CloudKit games: wins, how points were made)
//
// LOG is a phone's GameLogs/*.jsonl, or a ranked game from CloudKit (*.json,
// `scripts/cloudkit-games.py fetch`), whose person seat is its uploader.

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
/// `GHOST_FOLD` (0-3, default 3) picks which fourth, for cross-validating a fit.
let heldOutFold = Int(ProcessInfo.processInfo.environment["GHOST_FOLD"] ?? "3") ?? 3
func split(_ records: [DecisionRecord]) -> (train: [DecisionRecord], heldOut: [DecisionRecord]) {
    let games = Array(Set(records.map(\.game))).sorted()
    let heldOut = Set(games.enumerated().filter { $0.offset % 4 == heldOutFold }.map(\.element))
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
case "calibrate":
    guard let path = option("--person"), let target = Double(option("--target") ?? "") else {
        fail("calibrate needs --person and --target")
    }
    let games = Int(option("--games") ?? "40") ?? 40
    guard let tier = Tier(rawValue: option("--tier") ?? "classic") else { fail("--tier must be classic or expert") }
    let person = try readPerson(path)
    var best: (lambda: Double, gap: Double)?
    let grid = option("--lambdas").map { $0.split(separator: ",").compactMap { Double($0) } } ?? [0, 0.25, 0.5, 1, 2, 4]
    for lambda in grid {
        let started = Date()
        let result = try ghostWinRate(person: person, lambda: lambda, tier: tier, games: games)
        print("lambda " + number(lambda) + ": " + result.summary
              + String(format: "  (%.0fs)", Date().timeIntervalSince(started)))
        let gap = abs(result.rate - target)
        if best == nil || gap < best!.gap { best = (lambda, gap) }
    }
    print("closest to target " + number(target) + ": lambda " + number(best!.lambda))
case "strength":
    guard let path = option("--person"), let lambda = Double(option("--lambda") ?? "") else {
        fail("strength needs --person and --lambda")
    }
    let games = Int(option("--games") ?? "1248") ?? 1248
    guard let tier = Tier(rawValue: option("--tier") ?? "expert") else { fail("--tier must be classic or expert") }
    let choices = try option("--choices").map {
        try JSONDecoder().decode(ChoiceModel.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
    }
    let shard = option("--shard").map { $0.split(separator: "/").compactMap { Int($0) } } ?? [0, 1]
    let result = try ghostWinRate(person: try readPerson(path), lambda: lambda, tier: tier, games: games,
                                  choices: choices, shard: (shard[0], shard[1]))
    print("ghost vs three \(tier.rawValue) bots: " + result.summary + "  (null 0.250)")
    let (low, high) = result.interval
    print(low > 0.25 ? "BETTER than \(tier.rawValue) at 95%" : high < 0.25 ? "WORSE than \(tier.rawValue) at 95%"
          : "not distinguishable from \(tier.rawValue) at 95%")
case "baseline":
    let games = Int(option("--games") ?? "200") ?? 200
    let classic = option("--policy") == "classic"
    var seats: [SeatStats] = []
    for game in 0..<games {
        let seed = 910_000 + UInt64(game)
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players {
            policies[player.id] = classic ? HeuristicPolicy(personality: .balanced, id: "balanced") : EvaluationPolicy()
        }
        var session = GameSession(state: initial, policies: policies, policySeed: seed)
        var moves: [LoggedMove] = []
        while let step = try session.step() { moves.append(LoggedMove(player: step.actor, move: step.move)) }
        seats += try SeatStats.compute(initial: initial, moves: moves)
    }
    let radar = RadarMeasures(games: seats)
    print("\(classic ? "Classic" : "Expert") self-play, \(games) games, \(seats.count) seats, seeds 910000...")
    print("production  " + number(radar.production) + "  cards per turn")
    print("expansion   " + number(radar.expansion) + "  settlements + cities per game")
    print("trading     " + number(radar.trading) + "  trades completed per game")
    print("development " + number(radar.development) + "  dev cards played (+2 Largest Army) per game")
    print("robber      " + number(radar.robber) + "  share of robberies on the leader")
    print("finishing   " + number(radar.finishing) + "  final VP / target")
case "timing":
    // One game with the ghost in seat 1 against Classic bots: how long each
    // ghost move takes, then one retrain on that seat's decisions (what the
    // phone does after a game). Mac numbers; the phone is slower.
    guard let path = option("--person"), let lambda = Double(option("--lambda") ?? "") else {
        fail("timing needs --person and --lambda")
    }
    let person = try readPerson(path)
    let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: 920_000), seed: 920_000)
    let ghostSeat = initial.players[0].id
    let clock = MoveClock()
    var policies: [PlayerID: any Policy] = [:]
    for player in initial.players { policies[player.id] = Tier.classic.policy() }
    policies[ghostSeat] = TimedPolicy(inner: GhostPolicy(person: person, lambda: lambda), clock: clock)
    var session = GameSession(state: initial, policies: policies, policySeed: 920_000)
    var moves: [LoggedMove] = []
    while let step = try session.step() { moves.append(LoggedMove(player: step.actor, move: step.move)) }
    let ghostTimes = clock.times
    let sorted = ghostTimes.sorted()
    print("ghost moves: \(sorted.count), mean " + number(sorted.reduce(0, +) / Double(max(sorted.count, 1)))
          + "s, p95 " + number(sorted[Int(Double(sorted.count - 1) * 0.95)]) + "s, max " + number(sorted.last ?? 0) + "s")
    let game = LoggedGame(id: "timing", initialState: initial, humanSeats: [ghostSeat], events: moves)
    let extractStart = Date()
    let decisions = try DecisionExtractor.decisions(in: game, anchor: EvaluationWeights(vector: person.weights))
    let extractTime = Date().timeIntervalSince(extractStart)
    var options = FitOptions()
    options.iterations = 1000
    options.priorCenter = person
    options.priorEvidence = 2612
    let fitStart = Date()
    _ = PersonFitter.fit(decisions, anchor: .forMode(.classic), start: person, options: options)
    print("retrain: extract \(decisions.count) decisions " + number(extractTime) + "s, fit " + number(Date().timeIntervalSince(fitStart)) + "s")
case "fidelity":
    // A ghost profile, or a person model, at each lambda in turn.
    let lambdas = option("--lambdas").map { $0.split(separator: ",").compactMap { Double($0) } }
    let detail = arguments.contains("--detail")
    arguments.removeAll { $0 == "--detail" }
    var seats: [(String, any LedgerAwarePolicy)] = []
    if let path = option("--profile") {
        let profile = try JSONDecoder().decode(GhostProfile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        for lambda in lambdas ?? [profile.lambda] {
            seats.append(("\(profile.name) lambda \(lambda)", GhostPolicy(person: profile.person, lambda: lambda)))
        }
    } else if let path = option("--choices") {
        let model = try JSONDecoder().decode(ChoiceModel.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        seats.append(("choice model", GhostPolicy(person: .anchored(at: anchor), lambda: 0, choices: model)))
    } else if let path = option("--person") {
        let person = try readPerson(path)
        for lambda in lambdas ?? [0] { seats.append(("person lambda \(lambda)", GhostPolicy(person: person, lambda: lambda))) }
    } else {
        seats.append(("Expert", EvaluationPolicy()))
    }
    let dump = option("--dump")
    let folds = option("--cv").flatMap { Int($0) }
    // --regret R: the person picks among moves within R of Expert's best;
    // --regret none: anything (the 2026-10-24 choice ghost).
    let regretOption = option("--regret")
    let regret: Double? = regretOption == "none" ? nil : regretOption.flatMap(Double.init) ?? GhostPolicy.choiceRegret
    let personFolds = option("--person-folds")
    let outcomes = option("--outcomes")
    let games = try arguments.map { try loadGame(URL(fileURLWithPath: $0)) }
        .filter { $0.humanSeats.count == 1 && $0.initialState.mode == .classic }
    if let folds {
        let persons = try personFolds.map { prefix in try (0..<folds).map { try readPerson("\(prefix)\($0).json") } }
        if let lambdas, let persons {
            for lambda in lambdas {
                let moments = try crossValidated(games, folds: folds, persons: persons, personLambda: lambda)
                fidelityReport(moments, label: "person model alone, lambda \(lambda), \(folds)-fold by game", detail: detail)
                try outcomes.map { try writeOutcomes(moments, to: $0) }
            }
            break
        }
        let moments = try crossValidated(games, folds: folds, persons: persons, regret: regret)
        fidelityReport(moments, label: "choice model\(persons == nil ? "" : " + person")"
                       + (regret.map { " regret \($0)" } ?? " unrestricted")
                       + ", \(folds)-fold by game", detail: detail)
        try outcomes.map { try writeOutcomes(moments, to: $0) }
        break
    }
    for (label, policy) in seats {
        let moments = try games.flatMap { try GhostFidelity.moments(in: $0, policy: policy) }
        fidelityReport(moments, label: label, detail: detail)
        if let dump { try moments.map { try JSONEncoder().encode($0) + Data([0x0A]) }.reduce(Data(), +)
            .write(to: URL(fileURLWithPath: dump)) }
    }
case "choices":
    // Fit a person's choice model on all their games.
    guard let out = option("--out") else { fail("choices needs --out and log files") }
    let games = try arguments.map { try loadGame(URL(fileURLWithPath: $0)) }
        .filter { $0.humanSeats.count == 1 && $0.initialState.mode == .classic }
    let model = ChoiceFitter.fit(try games.flatMap { try ChoiceRecord.records(in: $0) })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(model).write(to: URL(fileURLWithPath: out))
    print("\(model.decisions) decisions -> \(out)")
case "candidates":
    guard let out = option("--out") else { fail("candidates needs --out and log files") }
    try dumpCandidates(try arguments.map { try loadGame(URL(fileURLWithPath: $0)) }
        .filter { $0.humanSeats.count == 1 && $0.initialState.mode == .classic }, to: out)
case "ladder":
    // Every seat of every ranked CloudKit game, one JSON line each.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for path in arguments {
        for seat in try ladderSeats(URL(fileURLWithPath: path)) {
            print(String(bytes: try encoder.encode(seat), encoding: .utf8) ?? "")
        }
    }
case "revision":
    // Which Expert played a ranked game's bot seats: replay each "expert"
    // seat's decisions through every classic revision and count agreement.
    for path in arguments {
        let url = URL(fileURLWithPath: path)
        let game = try loadCloudGame(url)
        let seats = try JSONDecoder().decode(CloudSeats.self, from: Data(contentsOf: url)).game.seats
        let experts = seats.indices.filter { seats[$0] == "expert" }.map { game.initialState.players[$0].id }
        guard !experts.isEmpty else { continue }
        let botGame = LoggedGame(id: game.id, initialState: game.initialState, humanSeats: Set(experts), events: game.events)
        var line = game.id
        for revision in [ExpertRevision.legacy, .cityProductionV1, .pointCompletingCardsV1, .timingOneAheadV1, .timingTradeGuardV1, .openingOreGrainV1] {
            let moments = try GhostFidelity.moments(in: botGame, policy: revision.policy)
            line += String(format: "  %@ %.3f", revision.rawValue, Double(moments.filter(\.exact).count) / Double(max(moments.count, 1)))
        }
        print(line)
    }
case "leader":
    print("game\tbelievedStrongest\ttrueLeader\tpublicLeader\tvictim\twinner\tleaderVP\tleaderPublicVP")
    for path in arguments { try leaderDiagnosis(URL(fileURLWithPath: path)).forEach { print($0) } }
case "duel":
    guard let candidate = option("--candidate"), let anchorName = option("--anchor"),
          let first = UInt64(option("--seed") ?? ""), let seeds = Int(option("--seeds") ?? "") else {
        fail("duel needs --candidate --anchor --seed --seeds")
    }
    let shard = option("--shard").map { $0.split(separator: "/").compactMap { Int($0) } } ?? [0, 1]
    try duel(candidate: candidate, anchor: anchorName, firstSeed: first, seeds: seeds,
             lone: arguments.contains("--lone"), shard: (shard[0], shard[1]))
case "improve":
    // Expert's own mistakes: rollouts from its choice and its next-best moves, in self-play.
    guard let first = UInt64(option("--seed") ?? ""), let count = UInt64(option("--seeds") ?? "") else {
        fail("improve needs --seed --seeds [--opponents a,b,c] [--sample 40] [--alternatives 2] [--rollouts 24]")
    }
    let opponents = (option("--opponents") ?? "trade-guard,trade-guard,trade-guard").split(separator: ",").map(String.init)
    let sample = UInt64(option("--sample") ?? "40") ?? 40
    let alternatives = Int(option("--alternatives") ?? "2") ?? 2
    let rollouts = Int(option("--rollouts") ?? "24") ?? 24
    let revision = ExpertRevision(rawValue: option("--expert") ?? "timingTradeGuardV1") ?? .timingTradeGuardV1
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for seed in first..<(first + count) {
        for record in try improve(seed: seed, opponents: opponents, sampleOneIn: sample, alternatives: alternatives,
                                  rollouts: rollouts, expert: revision, openings: arguments.contains("--openings")) {
            print(String(bytes: try encoder.encode(record), encoding: .utf8) ?? "")
        }
    }
case "shoes":
    // Expert in the person's shoes: rollouts from the person's move and Expert's.
    let rollouts = Int(option("--rollouts") ?? "16") ?? 16
    let revision = ExpertRevision(rawValue: option("--expert") ?? "timingTradeGuardV1") ?? .timingTradeGuardV1
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for path in arguments {
        let game = try loadGame(URL(fileURLWithPath: path))
        guard game.humanSeats.count == 1, game.initialState.mode == .classic else { continue }
        for record in try shoes(game, rollouts: rollouts, expert: revision) {
            print(String(bytes: try encoder.encode(record), encoding: .utf8) ?? "")
        }
    }
case "refusals":
    print("game\tpersonBuiltThatTurn\ttradeGuard")
    for path in arguments { try refusalAudit(URL(fileURLWithPath: path)).forEach { print($0) } }
case "bundle":
    guard let path = option("--person"), let lambda = Double(option("--lambda") ?? ""),
          let id = option("--id"), let name = option("--name"), let out = option("--out") else {
        fail("bundle needs --person --lambda --id --name --out")
    }
    let profile = GhostProfile(id: id, name: name, person: try readPerson(path), lambda: lambda,
                               gamesLearned: Int(option("--games-learned") ?? "0") ?? 0,
                               decisionsLearned: Int(option("--decisions-learned") ?? "0") ?? 0,
                               civilization: option("--civilization"))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(profile).write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
default:
    fail("unknown command \(command)")
}
