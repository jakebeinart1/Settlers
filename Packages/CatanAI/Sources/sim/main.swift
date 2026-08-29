import CatanAI
import CatanEngine
import Foundation

// Headless seeded self-play harness for the Empires bots.
//
// ## What this is
// Plays N complete games with all four seats driven by `Bot`, from a
// contiguous range of board seeds, and writes one record per game. It exists
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
// harness. `sim --seed 1 --games 1 --jsonl` must print `7cc7aee7b0c9c4d9`.
//
// ## stdout is data, stderr is diagnostics
// Timing and progress go to stderr so that two runs over the same seeds are
// byte-identical on stdout and can be compared with `cmp`. Never print a
// duration, a rate or a path to stdout.

/// Hard stop on a single game, matching `SeededGameFingerprintTests`. A game
/// that has not ended by here is a stuck bot loop, not a long game: real games
/// finish in the low hundreds of moves.
private let maxMovesPerGame = 3000

/// Seats at the table. Fixed by the engine (`GameSetup.newGame` always builds
/// four players), so a personality list of any other length is a usage error.
private let seatCount = 4

/// Derives the bot tie-break RNG seed from the board seed. Any injective
/// function would do; this exact one is copied from `SeededGameFingerprintTests`
/// so the harness and that test play the same games.
private func botSeed(fromBoardSeed seed: UInt64) -> UInt64 { seed &* 31 &+ 7 }

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

/// One parsed invocation. Every field is required to have a value by the time
/// parsing finishes; there is no "unset" state to reason about downstream.
private struct Options {
    var games: Int = 1
    var firstSeed: UInt64 = 1
    var personalityNames: [String] = ["balanced", "aggressive", "cautious", "balanced"]
    var jsonl: Bool = false

    static let usage = """
        usage: sim [--games N] [--seed S] [--personalities a,b,c,d] [--jsonl]
          --games N            number of consecutive seeds to play (default 1)
          --seed S             first board seed; seeds S ..< S+N are played (default 1)
          --personalities LIST four comma-separated names from: balanced, aggressive, cautious
                               (default balanced,aggressive,cautious,balanced)
          --jsonl              one JSON object per game on stdout; without it, a text table
        """
}

/// Maps a personality name to the `BotPersonality` constant it refers to.
/// Unknown names abort rather than falling back to `.balanced`, because a
/// typo'd arm silently played by the default opponent is the exact way a
/// bogus strength claim gets made.
private func personality(named name: String) -> BotPersonality {
    switch name {
    case "balanced": return .balanced
    case "aggressive": return .aggressive
    case "cautious": return .cautious
    default: fail("unknown personality '\(name)'; expected balanced, aggressive or cautious")
    }
}

/// Reads `CommandLine.arguments` into `Options`, aborting on anything it does
/// not recognise. Flags may appear in any order; each consumes exactly one
/// value except `--jsonl`, which is a switch.
private func parseOptions(_ arguments: [String]) -> Options {
    var options = Options()
    var index = arguments.startIndex + 1

    func nextValue(for flag: String) -> String {
        index += 1
        guard index < arguments.endIndex else { fail("\(flag) needs a value") }
        return arguments[index]
    }

    while index < arguments.endIndex {
        switch arguments[index] {
        case "--games":
            guard let count = Int(nextValue(for: "--games")), count > 0 else { fail("--games must be a positive integer") }
            options.games = count
        case "--seed":
            guard let seed = UInt64(nextValue(for: "--seed")) else { fail("--seed must be a non-negative integer") }
            options.firstSeed = seed
        case "--personalities":
            options.personalityNames = nextValue(for: "--personalities").split(separator: ",").map(String.init)
        case "--jsonl":
            options.jsonl = true
        case "--help", "-h":
            Stderr.write(Options.usage)
            exit(0)
        default:
            fail("unknown argument '\(arguments[index])'")
        }
        index += 1
    }

    guard options.personalityNames.count == seatCount else {
        fail("--personalities needs exactly \(seatCount) names, got \(options.personalityNames.count)")
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
    let seed: UInt64
    let moves: Int
    let winner: PlayerID?
    let victoryPoints: [Int]
    let fingerprint: String
}

/// Whoever may act, or `nil` at game over. `.discarding` carries a `Set` of
/// pending players, so it is sorted before taking the first - taking `.first`
/// of the set directly would pick a per-process-arbitrary seat.
private func actingPlayer(_ state: GameState) -> PlayerID? {
    switch state.phase {
    case .setupForward(let i), .setupBackward(let i),
         .rollDice(let i), .mainTurn(let i), .movingRobber(let i):
        return state.players[i].id
    case .discarding(let pending):
        return pending.sorted().first
    case .gameOver:
        return nil
    }
}

/// Applies one bot move, or stops the whole run.
///
/// `Bot.decide` promises to return a member of `RulesEngine.legalMoves(for:)`,
/// so a throw here is a broken invariant rather than a data point. Swallowing
/// it would produce a JSONL record that looks like a finished game and is not
/// one, which is the worst possible outcome for a measurement tool - so the
/// process dies, naming the seed and the move that broke it. (`try!` would do
/// the same thing with a useless message, and is banned outside test files:
/// `force_try` is only disabled under `Packages/*/Tests/.swiftlint.yml`.)
private func applyOrDie(_ move: GameMove, by actor: PlayerID, to state: inout GameState, seed: UInt64) {
    do {
        try RulesEngine.apply(move, by: actor, to: &state)
    } catch {
        fatalError("seed \(seed): P\(actor.index) played an illegal \(Rendering.canonical(move)): \(error)")
    }
}

/// Plays one complete game on a randomized board derived from `seed`, with
/// `bots[i]` seated at index `i`.
///
/// Conceptually: build the seeded state, then loop - ask whoever is to act for
/// a move, record its canonical rendering, apply it - until the phase becomes
/// `.gameOver` or the move cap trips.
private func playGame(seed: UInt64, bots: [Bot]) -> GameResult {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
    var botRNG = RandomSource(seed: botSeed(fromBoardSeed: seed))
    var trace: [String] = []

    for _ in 0..<maxMovesPerGame {
        if case .gameOver = state.phase { break }
        guard let actor = actingPlayer(state) else { break }
        let move = bots[actor.index].decide(for: state, player: actor, rng: &botRNG)
        trace.append("P\(actor.index):\(Rendering.canonical(move))")
        applyOrDie(move, by: actor, to: &state, seed: seed)
    }

    var winner: PlayerID?
    if case .gameOver(let who) = state.phase { winner = who }
    return GameResult(
        seed: seed,
        moves: trace.count,
        winner: winner,
        victoryPoints: state.players.map { state.victoryPoints(for: $0.id) },
        fingerprint: Rendering.fingerprint(trace)
    )
}

// MARK: - Output

/// One JSON object per game, fields emitted in a fixed order. Hand-rendered
/// rather than encoded: `JSONEncoder` would need a `Codable` mirror of this
/// struct and its own key-order guarantees, and every value here is an
/// integer, a null or an already-safe hex string.
private func jsonLine(_ result: GameResult) -> String {
    let winner = result.winner.map { "\($0.index)" } ?? "null"
    let points = result.victoryPoints.map(String.init).joined(separator: ",")
    return "{\"seed\":\(result.seed),\"moves\":\(result.moves),\"winner\":\(winner),"
        + "\"vp\":[\(points)],\"fingerprint\":\"\(result.fingerprint)\"}"
}

/// The human-readable form, for eyeballing a handful of games.
private func textLine(_ result: GameResult) -> String {
    let winner = result.winner.map { "P\($0.index)" } ?? "none"
    let points = result.victoryPoints.map(String.init).joined(separator: "/")
    return "seed \(result.seed)  moves \(result.moves)  winner \(winner)  vp \(points)  \(result.fingerprint)"
}

// MARK: - Run

// These are `private` because `Options` is: a top-level `let` in main.swift
// is a module-scope declaration, and Swift refuses to expose one whose type is
// less visible than it is.
private let options = parseOptions(CommandLine.arguments)
private let bots = options.personalityNames.map { Bot(personality: personality(named: $0)) }
private let clock = ContinuousClock()
private let started = clock.now

for offset in 0..<options.games {
    let result = playGame(seed: options.firstSeed &+ UInt64(offset), bots: bots)
    Stdout.write(options.jsonl ? jsonLine(result) : textLine(result))
}

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
