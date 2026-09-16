import CatanAI
import CatanEngine
import Foundation

// Headless seeded self-play harness for the Empires bots.
//
// ## What this is
// Plays N complete games with every seat driven by a policy, from a
// contiguous range of match seeds, and writes one record per game. It exists
// because every claim about the bots - "this heuristic is better", "this
// change is neutral", "that crash reproduces" - needs a way to play thousands
// of games without a simulator, a UI, or a human.
//
// ## The property that makes it worth anything: cross-process reproducibility
// The same seed must produce the same game in a DIFFERENT process, not merely
// twice inside one. Swift seeds `Set`/`Dictionary` iteration order once per
// process, so two runs in one process share that seed and agree with each
// other while disagreeing with tomorrow's run. Three rules keep this honest
// and each one is load-bearing:
//
//   1. Board and engine randomness come from `GameSetup.newGame(board:seed:)`,
//      which puts a `RandomSource` (SplitMix64) inside `GameState`.
//   2. Bot tie-breaks come from `Bot.decide(for:player:rng:)` with a seeded
//      `RandomSource`. The no-RNG overload `Bot.decide(for:player:)`
//      constructs a fresh `SystemRandomNumberGenerator` on EVERY call
//      (`Bot.swift:29`) and therefore can never be reproducible - a
//      measurement harness must never use it.
//   3. Everything printed to stdout is rendered in a fixed order. Dictionary
//      payloads inside a move go through `Rendering.canonical`, which walks
//      `Resource.allCases` rather than the dictionary, and the JSON object
//      below is emitted field by field rather than through an encoder.
//
// ## Why the fingerprint is FNV-1a over rendered moves
// It has one job: change when the move sequence changes. It is deliberately
// identical - same canonicalization, same hash, same bot RNG derivation - to
// `Packages/CatanAI/Tests/CatanAITests/SeededGameFingerprintTests.swift`, so
// that suite's five pinned constants double as an external check on this
// harness. The test file is the single source of truth for those constants;
// compare a fresh Release harness against it rather than copying a second set
// here. Those values have moved after intentional trade, road, and development
// card behavior changes, which is exactly why a duplicate literal went stale.
//
// ## stdout is data, stderr is diagnostics
// Timing and progress go to stderr so that two runs over the same seeds are
// byte-identical on stdout and can be compared with `cmp`. Never print a
// duration, a rate or a path to stdout.

/// Hard stop on a single game, matching `SeededGameFingerprintTests`. A game
/// that has not ended by here is a stuck bot loop, not a long game: real games
/// finish in the low hundreds of moves.
private let maxMovesPerGame = 3000

/// Wire version of one game-result JSON object. Bump whenever fields or their
/// meanings change; evaluation tools reject mismatches rather than guessing.
private let resultSchemaVersion = 5

/// The no-argument lineup remains byte-for-byte the historical four-seat
/// default. A three-seat run takes its prefix unless `--seats` names an
/// explicit roster.
private let defaultSeatNames = ["balanced", "aggressive", "cautious", "balanced"]

/// Product-supported evaluation targets. `WinCondition` accepts the whole
/// 8...12 range for save compatibility, while the product and evaluator offer
/// only the three calibrated match lengths.
private let evaluationVictoryPointTargets: Set<Int> = [8, 10, 12]

/// Derives the bot tie-break RNG seed from the match seed. Any injective
/// function would do; this exact one is copied from `SeededGameFingerprintTests`
/// so the harness and that test play the same games.
private func policySeed(from seed: UInt64) -> UInt64 { seed &* 31 &+ 7 }

// MARK: - stderr

/// Diagnostics channel. Kept separate from the results channel so nothing
/// non-reproducible can leak into the comparable output.
private enum Stderr {
    static func write(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

/// Results channel, written through a `FileHandle` rather than `print`.
///
/// Two reasons, and the second is the portable one. `print` goes to libc
/// `stdout`, which is fully buffered when redirected to a file - which is
/// exactly how this is meant to be run - so a run interrupted or trapped part
/// way loses every game it had already recorded, and progress is invisible for
/// the whole run. The obvious fix, `setvbuf(stdout, ...)`, does not compile on
/// Linux under Swift 6: there `stdout` is a mutable global and referencing it
/// is a concurrency error. `FileHandle` writes immediately and behaves the
/// same on both platforms.
private enum Stdout {
    static func write(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }
}

/// Fails the process with a usage message. Prefer this to a silent default:
/// a harness that quietly substitutes a value produces numbers nobody can
/// trace back to an invocation.
private func fail(_ message: String) -> Never {
    Stderr.write("sim: \(message)")
    Stderr.write(Options.usage)
    exit(2)
}

// MARK: - Options

private extension EvaluationBoardMode {
    func board(seed: UInt64, mode: GameMode = .classic) -> Board {
        let shape: BoardShape = mode == .expanded ? .expanded : .classic
        switch self {
        case .standard: return BoardGenerator.standard(shape)
        case .randomized: return BoardGenerator.randomized(seed: seed, shape: shape)
        }
    }
}

/// Rules and board generation that define one evaluation arm. These values
/// travel together into both game construction and output provenance so the
/// label cannot drift from the state that was actually played.
private struct SimulationConfiguration {
    var playerCount = GameSetup.standardPlayerCount
    var victoryPointTarget = Ruleset.forMode(.classic).defaultVictoryPointTarget
    var boardMode = EvaluationBoardMode.randomized
    /// Which rule set the arm is played under. Expanded fixes its own target,
    /// so `--victory-points` is not accepted with it - a run labelled 25 that
    /// silently played to 10 is precisely the kind of drift this struct exists
    /// to prevent.
    var mode = GameMode.classic

    func state(seed: UInt64) -> GameState {
        GameSetup.newGame(
            board: boardMode.board(seed: seed, mode: mode),
            seed: seed,
            playerCount: playerCount,
            victoryPointTarget: victoryPointTarget,
            mode: mode
        )
    }
}

/// One parsed invocation. Every field is required to have a value by the time
/// parsing finishes; there is no "unset" state to reason about downstream.
private struct Options {
    var games: Int = 1
    var firstSeed: UInt64 = 1
    var seatNames = defaultSeatNames
    var seatNamesWereProvided = false
    var victoryPointsWereProvided = false
    var configuration = SimulationConfiguration()
    var buildID = "working-tree"
    var buildIDWasProvided = false
    var jsonl: Bool = false
    var trainingOutput: String?
    var decisionOutput: String?
    var traceMaxBytes = CorpusWriter.defaultMaxBytes
    var trainingInformationPolicy: HiddenInformationPolicy = .revealAll
    /// Weights for the `eval-tuned` seat. A sweep varies this and nothing
    /// else, so one binary plays every candidate and the arms of a
    /// comparison differ by a value rather than by a build.
    var tunedWeights: EvaluationWeights = .default

    static let usage = """
        usage: sim [--games N] [--seed S] [--players 3|4] [--victory-points 8|10|12]
                   [--board standard|randomized] [--seats LIST] [--build-id ID] [--jsonl]
                   [--weights W1,...,W14]
                   [--training-jsonl PATH]
                   [--training-information reveal-all|public-counts]
                   [--decision-jsonl PATH] [--trace-max-bytes N]
          --games N     number of consecutive seeds to play (default 1)
          --seed S      first match seed; seeds S ..< S+N are played (default 1)
          --players N   seats at the table: 3 or 4 (default 4)
          --victory-points N
                        points required to win: 8, 10 or 12 (default 10)
          --board MODE  standard fixed layout or seeded randomized layout
          --mode MODE   classic or expanded rule set (default classic).
                        expanded fixes the target at 25 and rejects
                        --victory-points
                        (default randomized)
          --seats LIST  comma-separated policy names, exactly one per player
                        heuristics: balanced, aggressive, cautious
                        anchors:    greedy, random
                        search: eval (position evaluation, the current candidate)
                        sweep:  eval-tuned (same, with --weights)
                        anchor: eval-round3 (Expert as shipped at dac279c)
                        variant: eval-worthit (composed offers, no escalation ladder)
                        experiment: joint-balanced (trade-response accounting only)
                        (four-seat default balanced,aggressive,cautious,balanced;
                        a three-seat run uses the first three)
                        --personalities is accepted as an alias
          --build-id ID provenance label written into every result
                        (default working-tree; letters, digits, dot, dash, underscore)
          --jsonl       one JSON object per game on stdout; without it, a text table
          --training-jsonl PATH
                        write one versioned masked policy/value example per decision
          --training-information MODE
                        opponent holdings in training features (default reveal-all)
          --decision-jsonl PATH
                        retained diagnostic JSONL; requires explicit --build-id
          --trace-max-bytes N
                        total diagnostic file cap (default 268435456 bytes)
        """
}

/// Maps a seat name to the policy that plays it.
///
/// The anchors are here as first-class seats, not as a special mode, because
/// an anchored measurement is the ordinary case: a win rate against other
/// heuristics is 25% by construction and says nothing about strength. Naming
/// `greedy` or `random` on the command line is how a run gets a scale.
///
/// Unknown names abort rather than falling back to `.balanced`: a typo'd arm
/// silently played by the default opponent is the exact way a bogus strength
/// claim gets made.
private func policy(named name: String, writer: CorpusWriter? = nil,
                    tunedWeights: EvaluationWeights = .default) -> any Policy {
    let base: any Policy
    let personality: BotPersonality?
    switch name {
    case "balanced": personality = .balanced
    case "aggressive": personality = .aggressive
    case "cautious": personality = .cautious
    case "greedy", "random", "joint-balanced", "planner", "eval", "eval-tuned", "eval-round3", "eval-worthit": personality = nil
    default:
        fail(
            "unknown seat '\(name)'; expected balanced, aggressive, cautious, "
                + "eval, eval-tuned, eval-round3, planner, greedy, random or joint-balanced"
        )
    }
    if let personality {
        base = HeuristicPolicy(personality: personality, id: "heuristic-\(name)")
    } else if name == "greedy" {
        base = GreedyPolicy()
    } else if name == "planner" {
        base = PlannerPolicy()
    } else if name == "eval" {
        base = EvaluationPolicy()
    } else if name == "eval-tuned" {
        base = EvaluationPolicy(id: "evaluation-tuned", weights: tunedWeights)
    } else if name == "eval-worthit" {
        base = EvaluationPolicy(id: "evaluation-worthit", tradeModel: .worthIt)
    } else if name == "eval-round3" {
        // Expert as it shipped at `dac279c`, so new trading can be measured
        // against the Expert it replaces in the same game. See
        // `EvaluationPolicy.TradeModel` for why that needs one binary.
        base = EvaluationPolicy(id: "evaluation-round3", tradeModel: .roundThree)
    } else if name == "joint-balanced" {
        base = JointTradeResponsePolicy()
    } else {
        base = RandomPolicy()
    }
    guard let writer else { return base }
    return CorpusPolicy(base: base, bot: personality.map { Bot(personality: $0) }, writer: writer)
}

/// Reads `CommandLine.arguments` into `Options`, aborting on anything it does
/// not recognise. Flags may appear in any order; each consumes exactly one
/// value except `--jsonl`, which is a switch.
private func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var index = arguments.startIndex + 1
    var seenConfigurationFlags: Set<String> = []

    func nextValue(for flag: String) -> String {
        index += 1
        guard index < arguments.endIndex else { fail("\(flag) needs a value") }
        return arguments[index]
    }

    func uniqueValue(for flag: String) -> String {
        guard seenConfigurationFlags.insert(flag).inserted else {
            fail("\(flag) may be supplied only once")
        }
        return nextValue(for: flag)
    }

    while index < arguments.endIndex {
        switch arguments[index] {
        case "--games":
            guard let count = Int(nextValue(for: "--games")), count > 0 else { fail("--games must be a positive integer") }
            options.games = count
        case "--seed":
            guard let seed = UInt64(nextValue(for: "--seed")) else { fail("--seed must be a non-negative integer") }
            options.firstSeed = seed
        case "--players":
            guard let count = Int(uniqueValue(for: "--players")),
                  GameSetup.supportedPlayerCounts.contains(count) else {
                fail("--players must be 3 or 4")
            }
            options.configuration.playerCount = count
        case "--victory-points":
            guard let target = Int(uniqueValue(for: "--victory-points")),
                  evaluationVictoryPointTargets.contains(target) else {
                fail("--victory-points must be 8, 10 or 12")
            }
            // Order-independent: Expanded fixes its own target, so naming both
            // is a contradiction however they are ordered on the line, and a
            // run whose label disagrees with the rules it played is worse than
            // one that refuses to start.
            guard options.configuration.mode == .classic else {
                fail("--victory-points cannot be combined with --mode expanded, which fixes the target at 25")
            }
            options.configuration.victoryPointTarget = target
            options.victoryPointsWereProvided = true
        case "--board":
            let value = uniqueValue(for: "--board")
            guard let mode = EvaluationBoardMode(rawValue: value) else {
                fail("--board must be standard or randomized")
            }
            options.configuration.boardMode = mode
        case "--mode":
            let value = uniqueValue(for: "--mode")
            switch value {
            case "classic": options.configuration.mode = .classic
            case "expanded":
                guard !options.victoryPointsWereProvided else {
                    fail("--victory-points cannot be combined with --mode expanded, which fixes the target at 25")
                }
                options.configuration.mode = .expanded
                options.configuration.victoryPointTarget =
                    Ruleset.forMode(.expanded).defaultVictoryPointTarget
            default: fail("--mode must be classic or expanded")
            }
        case "--seats", "--personalities":
            let flag = arguments[index]
            options.seatNames = nextValue(for: flag).split(separator: ",").map(String.init)
            options.seatNamesWereProvided = true
        case "--build-id":
            let value = uniqueValue(for: "--build-id")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            guard !value.isEmpty, !value.hasPrefix("--"), value.unicodeScalars.allSatisfy(allowed.contains) else {
                fail("--build-id may contain only letters, digits, dot, dash and underscore")
            }
            options.buildID = value
            options.buildIDWasProvided = true
        case "--weights":
            let value = uniqueValue(for: "--weights")
            let numbers = value.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard numbers.allSatisfy({ $0 != nil }) else { fail("--weights must be comma-separated numbers") }
            let parsed = numbers.compactMap { $0 }
            guard parsed.count == EvaluationWeights.vectorLabels.count else {
                fail(
                    "--weights needs \(EvaluationWeights.vectorLabels.count) values in the order "
                        + EvaluationWeights.vectorLabels.joined(separator: ",")
                        + "; got \(parsed.count)"
                )
            }
            guard parsed.allSatisfy({ $0.isFinite }) else { fail("--weights must all be finite") }
            options.tunedWeights = EvaluationWeights(vector: parsed)
        case "--jsonl":
            options.jsonl = true
        case "--training-jsonl":
            options.trainingOutput = nextValue(for: "--training-jsonl")
        case "--decision-jsonl":
            let value = uniqueValue(for: "--decision-jsonl")
            guard !value.isEmpty, !value.hasPrefix("--") else { fail("--decision-jsonl needs a path") }
            options.decisionOutput = value
        case "--trace-max-bytes":
            guard let value = Int(uniqueValue(for: "--trace-max-bytes")), value > 0 else {
                fail("--trace-max-bytes must be a positive integer")
            }
            options.traceMaxBytes = value
        case "--training-information":
            let value = nextValue(for: "--training-information")
            switch value {
            case "reveal-all": options.trainingInformationPolicy = .revealAll
            case "public-counts": options.trainingInformationPolicy = .publicCountsOnly
            default: fail("--training-information must be reveal-all or public-counts")
            }
        case "--help", "-h":
            Stderr.write(Options.usage)
            exit(0)
        default:
            fail("unknown argument '\(arguments[index])'")
        }
        index += 1
    }

    if !options.seatNamesWereProvided {
        options.seatNames = Array(defaultSeatNames.prefix(options.configuration.playerCount))
    }
    guard options.seatNames.count == options.configuration.playerCount else {
        fail("--seats needs exactly \(options.configuration.playerCount) names, got \(options.seatNames.count)")
    }
    if options.trainingOutput != nil, options.buildID == "working-tree" {
        fail("--training-jsonl requires an explicit non-placeholder --build-id")
    }
    // Expert composes trade offers the fixed action space cannot index, and a
    // training example requires every chosen move to have an index. Refusing
    // here beats a precondition failure hundreds of games into an export.
    if options.trainingOutput != nil,
       let expert = options.seatNames.first(where: { $0.hasPrefix("eval") }) {
        fail("--training-jsonl cannot record '\(expert)': composed trade offers have no action index")
    }
    if options.decisionOutput != nil, !options.buildIDWasProvided {
        fail("--decision-jsonl requires an explicit --build-id")
    }
    if seenConfigurationFlags.contains("--trace-max-bytes"), options.decisionOutput == nil {
        fail("--trace-max-bytes requires --decision-jsonl")
    }
    let finalOffset = UInt64(options.games - 1)
    guard finalOffset <= UInt64.max - options.firstSeed else {
        fail("seed range overflows UInt64")
    }
    return options
}

// MARK: - Canonical rendering

/// Everything that turns game data into text. Isolated here because every
/// function in it has the same constraint: its output may not depend on
/// per-process hash ordering.
private enum Rendering {
    /// Renders a `[Resource: Int]` in `Resource.allCases` order. Iterating the
    /// dictionary directly would order keys per process, which would make the
    /// fingerprint differ between runs for reasons that have nothing to do
    /// with play.
    static func table(_ amounts: [Resource: Int]) -> String {
        Resource.allCases
            .compactMap { resource in amounts[resource].map { "\(resource)=\($0)" } }
            .joined(separator: ",")
    }

    /// A stable one-line rendering of a move. Only the three cases carrying
    /// dictionary payloads need special handling; every other case's
    /// synthesized description is already order-independent.
    static func canonical(_ move: GameMove) -> String {
        switch move {
        case .discard(let amounts):
            return "discard[\(table(amounts))]"
        case .bankTrade(let give, let get):
            return "bankTrade[\(table(give))->\(table(get))]"
        case .proposeTrade(let offer):
            return "proposeTrade[p\(offer.from.index):\(table(offer.give))->\(table(offer.want))]"
        default:
            return "\(move)"
        }
    }

    /// FNV-1a over the concatenated move renderings, printed as 16 lowercase
    /// hex digits. Not cryptographic - it only has to change when the
    /// sequence does. Formatted without `String(format:)` so the digits are
    /// produced by the stdlib rather than by a locale-aware formatter.
    static func fingerprint(_ moves: [String]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for move in moves {
            for byte in move.utf8 {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
        }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}

// MARK: - Playing one game

/// Everything one finished game contributes to a measurement.
private struct GameResult {
    let buildID: String
    let configuration: SimulationConfiguration
    let policyIDs: [String]
    let seed: UInt64
    let moves: Int
    let winner: PlayerID?
    let victoryPoints: [Int]
    let fingerprint: String
    let behavior: [PolicyBehaviorMetrics]
    let decisions: [RecordedDecision]
    let policyEvaluationCount: Int
}

private struct RecordedDecision {
    let decision: GameSession.Decision
    let policyID: String
}

/// Plays one complete game on a randomized board derived from `seed`, with
/// `policies[i]` seated at index `i`.
///
/// Conceptually: build the seeded state, hand every seat to a `GameSession`,
/// then step it - recording the canonical rendering of each applied move -
/// until the game ends or the move cap trips.
///
/// **It runs through `GameSession` rather than calling the policies directly,
/// and that is the entire point.** This harness used to drive `Bot.decide` in
/// its own loop while the app drove one of its own, so the bots being measured
/// here were not the bots being played there: this loop saw the unscoped
/// action list and had no runaway backstop, and the app had both. Any strength
/// number produced by a private loop describes only that loop.
private func playGame(
    seed: UInt64,
    policies: [any Policy],
    configuration: SimulationConfiguration,
    buildID: String,
    recordTraining: Bool,
    corpus: CorpusWriter?
) -> GameResult {
    let state = configuration.state(seed: seed)
    precondition(policies.count == state.players.count,
                 "policy roster must match the configured player count")
    var seats: [PlayerID: any Policy] = [:]
    for (index, policy) in policies.enumerated() { seats[state.players[index].id] = policy }
    // Start must precede construction: restoring pending trades can invoke
    // policies inside GameSession.init, before its caller receives a session.
    corpus?.start(seed: seed, payload: CorpusStart(buildID: buildID, policyIDs: policies.map(\.id),
                                                 boardMode: configuration.boardMode, initialState: state))
    var session = GameSession(state: state, policies: seats,
                              policySeed: policySeed(from: seed))
    corpus?.verify(session: session)
    var trace: [String] = []
    var behavior = Array(repeating: PolicyBehaviorMetrics(), count: state.players.count)
    var decisions: [RecordedDecision] = []

    for _ in 0..<maxMovesPerGame {
        guard case .seat = session.nextActor() else { break }
        let nextDecision = session.decideNextDetailed()
        corpus?.verify(session: session)
        guard let decision = nextDecision else { break }
        for evaluated in session.lastPolicyDecisions {
            behavior[evaluated.seat.index].observeDecision(evaluated.observation, chosen: evaluated.move)
        }
        record(session.lastPolicyDecisions, policies: policies, enabled: recordTraining, into: &decisions)
        let step: GameSession.Step?
        do {
            step = try session.commit(seat: decision.seat, move: decision.move)
        } catch {
            corpus?.abort(error)
            fatalError("seed \(seed): a policy played an illegal move: \(error)")
        }
        corpus?.verify(session: session)
        guard let step else { break }
        corpus?.commit(moveIndex: trace.count, step: step, session: session)
        for evaluated in session.lastPolicyDecisions {
            behavior[evaluated.seat.index].observeDecision(evaluated.observation, chosen: evaluated.move)
        }
        record(session.lastPolicyDecisions, policies: policies, enabled: recordTraining, into: &decisions)
        trace.append("P\(step.actor.index):\(Rendering.canonical(step.move))")
        behavior[step.actor.index].observe(step.events, for: step.actor)
    }

    var winner: PlayerID?
    corpus?.end(session: session, moves: trace.count)
    if case .gameOver(let who) = session.state.phase { winner = who }
    return GameResult(
        buildID: buildID,
        configuration: configuration,
        policyIDs: policies.map(\.id),
        seed: seed,
        moves: trace.count,
        winner: winner,
        victoryPoints: session.state.players.map { session.state.victoryPoints(for: $0.id) },
        fingerprint: Rendering.fingerprint(trace),
        behavior: behavior,
        decisions: decisions,
        policyEvaluationCount: session.policyEvaluationCount
    )
}

private func record(
    _ evaluated: [GameSession.Decision],
    policies: [any Policy],
    enabled: Bool,
    into decisions: inout [RecordedDecision]
) {
    guard enabled else { return }
    decisions.append(contentsOf: evaluated.map {
        RecordedDecision(decision: $0, policyID: policies[$0.seat.index].id)
    })
}

// MARK: - Output

/// One JSON object per game, fields emitted in a fixed order. Hand-rendered
/// rather than encoded: `JSONEncoder` would need a `Codable` mirror of this
/// struct and its own key-order guarantees, and every value here is an
/// integer, a null or an already-safe hex string.
private func jsonLine(_ result: GameResult) -> String {
    let winner = result.winner.map { "\($0.index)" } ?? "null"
    let points = result.victoryPoints.map(String.init).joined(separator: ",")
    let policies = result.policyIDs.map { "\"\($0)\"" }.joined(separator: ",")
    let configuration = result.configuration
    return "{\"schemaVersion\":\(resultSchemaVersion),\"buildID\":\"\(result.buildID)\","
        + "\"playerCount\":\(configuration.playerCount),"
        + "\"victoryPointTarget\":\(configuration.victoryPointTarget),"
        + "\"boardMode\":\"\(configuration.boardMode.rawValue)\","
        + "\"policies\":[\(policies)],"
        + "\"seed\":\(result.seed),\"moves\":\(result.moves),\"winner\":\(winner),"
        + "\"vp\":[\(points)],\"fingerprint\":\"\(result.fingerprint)\","
        + "\"behavior\":\(behaviorJSON(result.behavior))}"
}

private func behaviorJSON(_ metrics: [PolicyBehaviorMetrics]) -> String {
    let objects = metrics.map(behaviorObjectJSON)
    return "[\(objects.joined(separator: ","))]"
}

/// Keep each fragment small enough for the Linux Swift compiler to type-check
/// reliably. The same chained interpolation compiled on macOS but exceeded the
/// compiler's expression-complexity limit in CI.
private func behaviorObjectJSON(_ metric: PolicyBehaviorMetrics) -> String {
    let production = "{\"roadsBuilt\":\(metric.roadsBuilt),\"settlementsBuilt\":\(metric.settlementsBuilt),"
        + "\"citiesBuilt\":\(metric.citiesBuilt),\"developmentCardsBought\":\(metric.developmentCardsBought),"
        + "\"knightsPlayed\":\(metric.knightsPlayed),\"robberMoves\":\(metric.robberMoves),"
        + "\"bankTrades\":\(metric.bankTrades),\"tradesProposed\":\(metric.tradesProposed),"
        + "\"resolvedTradeAcceptances\":\(metric.resolvedTradeAcceptances),"
        + "\"resolvedTradeRejections\":\(metric.resolvedTradeRejections),\"turnsEnded\":\(metric.turnsEnded),"
    let buildChoices = "\"settlementCityOpportunities\":\(metric.settlementCityOpportunities),"
        + "\"settlementsChosenInMixedBuildOpportunities\":\(metric.settlementsChosenInMixedBuildOpportunities),"
        + "\"citiesChosenInMixedBuildOpportunities\":\(metric.citiesChosenInMixedBuildOpportunities),"
        + "\"cityBuildOpportunities\":\(metric.cityBuildOpportunities),"
        + "\"citiesChosenWhenBuildable\":\(metric.citiesChosenWhenBuildable),"
        + "\"developmentCardBuildOpportunities\":\(metric.developmentCardBuildOpportunities),"
        + "\"developmentCardsChosenOverPermanentBuild\":\(metric.developmentCardsChosenOverPermanentBuild),"
    let tradeChoices = "\"tradeResponseOpportunities\":\(metric.tradeResponseOpportunities),"
        + "\"tradeResponsesAccepted\":\(metric.tradeResponsesAccepted),"
        + "\"proposalCardsGiven\":\(metric.proposalCardsGiven),"
        + "\"proposalCardsRequested\":\(metric.proposalCardsRequested),"
    let tacticalChoices = "\"playableKnightOpportunities\":\(metric.playableKnightOpportunities),"
        + "\"knightsChosenWhenPlayable\":\(metric.knightsChosenWhenPlayable),"
        + "\"differentiatedRobberTargetOpportunities\":\(metric.differentiatedRobberTargetOpportunities),"
        + "\"highestPublicVPRobberTargets\":\(metric.highestPublicVPRobberTargets),"
        + "\"tradeProposalOpportunities\":\(metric.tradeProposalOpportunities)}"
    return production + buildChoices + tradeChoices + tacticalChoices
}

/// The human-readable form, for eyeballing a handful of games.
private func textLine(_ result: GameResult) -> String {
    let winner = result.winner.map { "P\($0.index)" } ?? "none"
    let points = result.victoryPoints.map(String.init).joined(separator: "/")
    return "seed \(result.seed)  moves \(result.moves)  winner \(winner)  vp \(points)  \(result.fingerprint)"
}

private final class TrainingWriter {
    private let finalURL: URL
    private let temporaryURL: URL
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private let informationPolicy: HiddenInformationPolicy
    private var isFinished = false

    init(path: String, informationPolicy: HiddenInformationPolicy) {
        precondition(!path.isEmpty, "--training-jsonl path cannot be empty")
        precondition(!FileManager.default.fileExists(atPath: path),
                     "refusing to overwrite existing training data at \(path)")
        finalURL = URL(fileURLWithPath: path)
        temporaryURL = finalURL.deletingLastPathComponent()
            .appendingPathComponent(".\(finalURL.lastPathComponent).\(UUID().uuidString).tmp")
        precondition(FileManager.default.createFile(atPath: temporaryURL.path, contents: nil),
                     "could not create temporary training output beside \(path)")
        guard let handle = FileHandle(forWritingAtPath: temporaryURL.path) else {
            preconditionFailure("could not open temporary training output beside \(path)")
        }
        self.handle = handle
        self.informationPolicy = informationPolicy
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    deinit {
        guard !isFinished else { return }
        // Best-effort cleanup only: `finish()` owns the checked close and
        // atomic publication path. A crash may leave a visibly temporary file,
        // never a valid-looking final dataset.
        try? handle.close()
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    func write(_ result: GameResult) {
        guard let winner = result.winner else {
            preconditionFailure("training data requires a decisive game for seed \(result.seed)")
        }
        precondition(result.decisions.count == result.policyEvaluationCount,
                     "captured \(result.decisions.count) of \(result.policyEvaluationCount) policy evaluations")
        for recorded in result.decisions {
            let decision = recorded.decision
            let example = TrainingExample(
                buildID: result.buildID,
                seed: result.seed,
                decisionIndex: decision.evaluationIndex,
                policyID: recorded.policyID,
                hiddenInformationPolicy: informationPolicy,
                boardMode: result.configuration.boardMode,
                observation: decision.observation,
                chosenMove: decision.move,
                winner: winner
            )
            do {
                handle.write(try encoder.encode(example))
                handle.write(Data("\n".utf8))
            } catch {
                preconditionFailure("could not encode training example: \(error)")
            }
        }
    }

    func finish() throws {
        try handle.synchronize()
        try handle.close()
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        isFinished = true
    }
}

// MARK: - Run

// These are `private` because `Options` is: a top-level `let` in main.swift
// is a module-scope declaration, and Swift refuses to expose one whose type is
// less visible than it is.
private let options = parseOptions(CommandLine.arguments)
// Validate all seats before creating either export file.
private let validatedSeats = options.seatNames.map {
    policy(named: $0, tunedWeights: options.tunedWeights)
}
private let corpusWriter: CorpusWriter? = {
    guard let path = options.decisionOutput else { return nil }
    do {
        return try CorpusWriter(path: path, maxBytes: options.traceMaxBytes)
    } catch {
        fail("could not create decision trace (refusing overwrite) at \(path): \(error)")
    }
}()
private let seats = corpusWriter.map { writer in
    options.seatNames.map { policy(named: $0, writer: writer, tunedWeights: options.tunedWeights) }
}
    ?? validatedSeats
private let clock = ContinuousClock()
private let started = clock.now
private let trainingWriter = options.trainingOutput.map {
    TrainingWriter(path: $0, informationPolicy: options.trainingInformationPolicy)
}

for offset in 0..<options.games {
    let result = playGame(
        seed: options.firstSeed &+ UInt64(offset),
        policies: seats,
        configuration: options.configuration,
        buildID: options.buildID,
        recordTraining: trainingWriter != nil,
        corpus: corpusWriter
    )
    trainingWriter?.write(result)
    Stdout.write(options.jsonl ? jsonLine(result) : textLine(result))
}
corpusWriter?.finish()

// Sampled ONCE. Reading `clock.now` twice took `seconds` from the first read
// and `attoseconds` from the second, so a pair straddling a whole-second
// boundary reported a figure a full second out - and this is the number the
// sim-harness and bot-strength skills quote as measured throughput and use to
// budget how long an evaluation arm takes.
let duration = clock.now - started
let elapsed = Double(duration.components.seconds)
    + Double(duration.components.attoseconds) / 1e18
Stderr.write(String(format: "sim: %d games in %.2fs (%.1f games/sec)",
                    options.games, elapsed, Double(options.games) / elapsed))
do {
    try trainingWriter?.finish()
} catch {
    fatalError("could not publish training data: \(error)")
}
