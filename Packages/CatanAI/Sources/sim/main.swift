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
    func board(seed: UInt64) -> Board {
        switch self {
        case .standard: BoardGenerator.standard()
        case .randomized: BoardGenerator.randomized(seed: seed)
        }
    }
}

/// Rules and board generation that define one evaluation arm. These values
/// travel together into both game construction and output provenance so the
/// label cannot drift from the state that was actually played.
private struct SimulationConfiguration {
    var playerCount = GameSetup.standardPlayerCount
    var victoryPointTarget = WinCondition.standardTarget
    var boardMode = EvaluationBoardMode.randomized

    func state(seed: UInt64) -> GameState {
        GameSetup.newGame(
            board: boardMode.board(seed: seed),
            seed: seed,
            playerCount: playerCount,
            victoryPointTarget: victoryPointTarget
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
    var configuration = SimulationConfiguration()
    var buildID = "working-tree"
    var jsonl: Bool = false
    var listPolicies = false
    var trainingOutput: String?
    var policyAuditOutput: String?
    var trainingInformationPolicy: HiddenInformationPolicy = .revealAll

    static let usage = """
        usage: sim [--games N] [--seed S] [--players 3|4] [--victory-points 8|10|12]
                   [--board standard|randomized] [--seats LIST] [--build-id ID] [--jsonl]
                   [--training-jsonl PATH] [--policy-audit-jsonl PATH]
                   [--training-information reveal-all|public-counts]
               sim --list-policies
          --games N     number of consecutive seeds to play (default 1)
          --seed S      first match seed; seeds S ..< S+N are played (default 1)
          --players N   seats at the table: 3 or 4 (default 4)
          --victory-points N
                        points required to win: 8, 10 or 12 (default 10)
          --board MODE  standard fixed layout or seeded randomized layout
                        (default randomized)
          --seats LIST  comma-separated policy names, exactly one per player
                        heuristics: balanced, aggressive, cautious
                        anchors:    greedy, random
                        hybrid:     neural-r2 (bundled model, balanced heuristic trading;
                                    all hands visible, experimental)
                        (four-seat default balanced,aggressive,cautious,balanced;
                        a three-seat run uses the first three)
                        --personalities is accepted as an alias
          --build-id ID provenance label written into every result
                        (default working-tree; letters, digits, dot, dash, underscore)
          --jsonl       one JSON object per game on stdout; without it, a text table
          --list-policies
                        standalone JSON object: seat name -> actual policy ID;
                        validates the bundled model, runs no games
          --training-jsonl PATH
                        write one versioned masked policy/value example per decision
          --policy-audit-jsonl PATH
                        exclusively create a route-count sidecar, one JSON row per game;
                        retains completed rows on failure, not network inference counts
          --training-information MODE
                        opponent holdings in training features (default reveal-all)
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
private enum SeatPolicy: String, CaseIterable {
    case balanced, aggressive, cautious, greedy, random
    case neuralR2 = "neural-r2"

    private static let balancedFallback = HeuristicPolicy(personality: .balanced, id: "heuristic-balanced")

    /// Lazy, process-wide immutable weights: heuristic-only runs do not load
    /// the model, and every neural seat/game shares the same validated value.
    private static let network: UpstreamNetwork = {
        do {
            return try UpstreamNetwork.bundled()
        } catch {
            fail("cannot load neural-r2 bundled model: \(error)")
        }
    }()

    func makePolicy() -> any Policy {
        switch self {
        case .balanced: return Self.balancedFallback
        case .aggressive: return HeuristicPolicy(personality: .aggressive, id: "heuristic-aggressive")
        case .cautious: return HeuristicPolicy(personality: .cautious, id: "heuristic-cautious")
        case .greedy: return GreedyPolicy()
        case .random: return RandomPolicy()
        case .neuralR2:
            return UpstreamPolicy(network: Self.network, fallback: Self.balancedFallback)
        }
    }
}

private func policy(named name: String) -> any Policy {
    guard let seat = SeatPolicy(rawValue: name) else {
        fail("unknown seat '\(name)'; expected \(SeatPolicy.allCases.map(\.rawValue).joined(separator: ", "))")
    }
    return seat.makePolicy()
}

/// Derive identifiers from the same constructors as play; wrappers must not
/// duplicate a neural identifier or assume that it hashes the bundled model.
private func writePolicyRegistry() {
    let registry = Dictionary(uniqueKeysWithValues: SeatPolicy.allCases.map { ($0.rawValue, $0.makePolicy().id) })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        guard let json = String(data: try encoder.encode(registry), encoding: .utf8) else {
            fail("cannot encode UTF-8 policy registry")
        }
        Stdout.write(json)
    } catch {
        fail("cannot encode policy registry: \(error)")
    }
}

/// Reads `CommandLine.arguments` into `Options`, aborting on anything it does
/// not recognise. Flags may appear in any order; each consumes exactly one
/// value except the `--jsonl` switch and standalone `--list-policies` query.
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
            options.configuration.victoryPointTarget = target
        case "--board":
            let value = uniqueValue(for: "--board")
            guard let mode = EvaluationBoardMode(rawValue: value) else {
                fail("--board must be standard or randomized")
            }
            options.configuration.boardMode = mode
        case "--seats", "--personalities":
            let flag = arguments[index]
            options.seatNames = nextValue(for: flag).split(separator: ",").map(String.init)
            options.seatNamesWereProvided = true
        case "--build-id":
            let value = nextValue(for: "--build-id")
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
            guard !value.isEmpty, value.unicodeScalars.allSatisfy(allowed.contains) else {
                fail("--build-id may contain only letters, digits, dot, dash and underscore")
            }
            options.buildID = value
        case "--jsonl":
            options.jsonl = true
        case "--list-policies":
            guard arguments.count == 2 else { fail("--list-policies must be used alone") }
            options.listPolicies = true
        case "--training-jsonl":
            options.trainingOutput = nextValue(for: "--training-jsonl")
        case "--policy-audit-jsonl":
            let path = uniqueValue(for: "--policy-audit-jsonl")
            guard !path.isEmpty else { fail("--policy-audit-jsonl path cannot be empty") }
            options.policyAuditOutput = path
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
    let policyAudit: PolicyAudit?
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
    auditPolicies: Bool
) -> GameResult {
    let state = configuration.state(seed: seed)
    precondition(policies.count == state.players.count,
                 "policy roster must match the configured player count")
    var seats: [PlayerID: any Policy] = [:]
    for (index, policy) in policies.enumerated() { seats[state.players[index].id] = policy }
    var session = GameSession(state: state, policies: seats,
                              policySeed: policySeed(from: seed))
    var trace: [String] = []
    var behavior = Array(repeating: PolicyBehaviorMetrics(), count: state.players.count)
    var decisions: [RecordedDecision] = []
    var policyAudit = auditPolicies ? PolicyAudit(seed: seed, policyIDs: policies.map(\.id)) : nil

    for _ in 0..<maxMovesPerGame {
        guard case .seat = session.nextActor() else { break }
        guard let decision = session.decideNextDetailed() else { break }
        for evaluated in session.lastPolicyDecisions {
            behavior[evaluated.seat.index].observeDecision(evaluated.observation, chosen: evaluated.move)
        }
        record(session.lastPolicyDecisions, policies: policies, enabled: recordTraining, into: &decisions)
        policyAudit?.observe(session.lastPolicyDecisions)
        let step: GameSession.Step?
        do {
            step = try session.commit(seat: decision.seat, move: decision.move)
        } catch {
            fatalError("seed \(seed): a policy played an illegal move: \(error)")
        }
        guard let step else { break }
        for evaluated in session.lastPolicyDecisions {
            behavior[evaluated.seat.index].observeDecision(evaluated.observation, chosen: evaluated.move)
        }
        record(session.lastPolicyDecisions, policies: policies, enabled: recordTraining, into: &decisions)
        policyAudit?.observe(session.lastPolicyDecisions)
        trace.append("P\(step.actor.index):\(Rendering.canonical(step.move))")
        behavior[step.actor.index].observe(step.events, for: step.actor)
    }

    var winner: PlayerID?
    if case .gameOver(let who) = session.state.phase { winner = who }
    policyAudit?.validate(evaluationCount: session.policyEvaluationCount)
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
        policyEvaluationCount: session.policyEvaluationCount,
        policyAudit: policyAudit
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

/// Selection routes, not inference calls: compounds may score several times,
/// and trade responders may be evaluated without becoming a committed move.
private struct PolicyAudit: Encodable {
    let schemaVersion = 1
    let seed: UInt64
    private(set) var evaluationCount = 0
    private(set) var seats: [Seat]
    private var evaluationIndices: Set<Int> = []

    private enum CodingKeys: String, CodingKey { case schemaVersion, seed, evaluationCount, seats }

    struct Seat: Encodable {
        let policyID: String
        var evaluations = 0
        var sources: [String: Int] = [:]
        var fallbackReasons: [String: Int] = [:]

        mutating func observe(_ selection: PolicySelection) {
            evaluations += 1
            sources[selection.source, default: 0] += 1
            if let reason = selection.fallbackReason { fallbackReasons[reason, default: 0] += 1 }
        }
    }

    init(seed: UInt64, policyIDs: [String]) {
        self.seed = seed
        seats = policyIDs.map { Seat(policyID: $0) }
    }

    mutating func observe(_ decisions: [GameSession.Decision]) {
        for decision in decisions {
            guard let trace = decision.policyTrace,
                  trace.evaluationIndex == decision.evaluationIndex,
                  seats.indices.contains(decision.seat.index),
                  trace.policyID == seats[decision.seat.index].policyID,
                  !trace.selection.source.isEmpty,
                  evaluationIndices.insert(decision.evaluationIndex).inserted else {
                fail("seed \(seed): missing, inconsistent or duplicate policy audit trace")
            }
            seats[decision.seat.index].observe(trace.selection)
            evaluationCount += 1
        }
    }

    func validate(evaluationCount expected: Int) {
        guard evaluationIndices == Set(0..<expected) else {
            fail("seed \(seed): policy audit captured \(evaluationCount) of \(expected) evaluations")
        }
    }
}

/// Unlike a training dataset, completed audit rows remain useful after a later
/// failure. Write directly to an exclusively created file and flush each row;
/// never rename away or remove this evidence during cleanup.
private final class PolicyAuditWriter {
    private let handle: FileHandle
    private let encoder = JSONEncoder()

    init(path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            try Data().write(to: url, options: .withoutOverwriting)
            handle = try FileHandle(forWritingTo: url)
        } catch {
            fail("cannot create policy audit at \(path) (existing paths are refused): \(error)")
        }
        encoder.outputFormatting = [.sortedKeys]
    }

    func write(_ audit: PolicyAudit) {
        do {
            var row = try encoder.encode(audit)
            row.append(0x0A)
            try handle.write(contentsOf: row)
            try handle.synchronize()
        } catch {
            fail("seed \(audit.seed): cannot write policy audit: \(error)")
        }
    }

    func finish() {
        do {
            try handle.close()
        } catch {
            fail("cannot close policy audit: \(error)")
        }
    }
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
if options.listPolicies {
    writePolicyRegistry()
    exit(0)
}
private let seats = options.seatNames.map { policy(named: $0) }
private let clock = ContinuousClock()
private let started = clock.now
private let policyAuditWriter = options.policyAuditOutput.map { PolicyAuditWriter(path: $0) }
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
        auditPolicies: policyAuditWriter != nil
    )
    if let audit = result.policyAudit { policyAuditWriter?.write(audit) }
    trainingWriter?.write(result)
    Stdout.write(options.jsonl ? jsonLine(result) : textLine(result))
}
policyAuditWriter?.finish()

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
