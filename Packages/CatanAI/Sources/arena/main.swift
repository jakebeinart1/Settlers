import CatanAI
import CatanEngine
import Foundation

// Tournament referee: plays scheduled games where every seat can be a
// different version of the bots, including versions from old commits.
//
// ## Why not `sim`
// `sim` links one `CatanAI`, so every seat it can name is today's code. Jake's
// question (2026-09-28) was whether the card-spending Expert is really no
// stronger or weaker than the one that held cards, and whether today's bots
// beat every Expert and Classic that ever shipped. That needs old bots at the
// same table as new ones, which one process cannot hold. So each old version
// runs as a seat server built from its own commit
// (`scripts/tournament/build-version.sh`), and this referee asks it for moves
// over a pipe.
//
// ## The rules are today's, for everyone
// The game is played by today's `GameSession` and `RulesEngine`: same board,
// same dice, same trade cap, same runaway backstop for every seat. An old bot
// is shown today's legal moves and chooses among them with its own logic. A
// move today's rules reject is replaced by a neutral fallback and COUNTED, per
// seat, in the result - a version that needs many is reported, not hidden.
//
// ## Seat names
//   local:expert           today's Expert, in process
//   local:expert-holder    today's Expert without `HandDiscipline`
//   local:classic          today's Classic (balanced heuristic)
//   <sha>:<policy>         seat server `seat-<sha>` from --seats-dir, policy
//                          `expert`, `classic`, `classic-aggressive` or
//                          `classic-cautious`
//
// ## Randomness
// Every seat, local or remote, draws one 64-bit seed per decision from the
// session's policy RNG and plays with `RandomSource(seed:)`. Treating both
// kinds identically is what lets `--selftest` prove the pipe changes nothing:
// today's code over a pipe must produce the in-process game move for move.

private let maxMovesPerGame = 3000

private enum Stderr {
    static func write(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }
}

private func fail(_ message: String) -> Never {
    Stderr.write("arena: \(message)")
    exit(2)
}

// MARK: - Seats

/// Per-seat counters a policy wrapper can bump. A class so the session's
/// value-typed policy dictionary can share it with the game loop.
private final class SeatTally: @unchecked Sendable {
    var decisions = 0
    var fallbacks = 0
    var decodeErrors = 0
    /// Trade proposals and acceptances today's rules refuse: an offer past the
    /// three-refusal cap, an accept the seat cannot pay for. Old builds made
    /// these because their rules allowed them; declining is what today's
    /// rules do to anyone, so these are enforcement, not incompatibility.
    var tradesBlocked = 0
}

/// Today's code, reseeded per decision like a remote seat.
private struct LocalSeat: LedgerAwarePolicy {
    let base: any Policy
    let tally: SeatTally
    var id: String { base.id }

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        tally.decisions += 1
        var local = RandomSource(seed: rng.next())
        if let aware = base as? any LedgerAwarePolicy {
            return aware.decide(observation, ledger: ledger, rng: &local)
        }
        return base.decide(observation, rng: &local)
    }
}

/// A running seat server. One per version per referee process, reused across
/// games; a server holds no state between requests.
private final class SeatServer: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()

    init(binary: URL) {
        process.executableURL = binary
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError
        do { try process.run() } catch { fail("cannot start \(binary.path): \(error)") }
    }

    /// Pipe reads and writes autorelease on Darwin and a command-line loop
    /// never drains them: without the pool a worker grew ~3MB a second until,
    /// with its seat servers, the Mac ran out of swap (2026-09-29).
    func ask(_ request: Data) -> Data {
        #if canImport(ObjectiveC)
        return autoreleasepool { exchange(request) }
        #else
        return exchange(request)
        #endif
    }

    private func exchange(_ request: Data) -> Data {
        input.fileHandleForWriting.write(request + Data("\n".utf8))
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[(newline + 1)...])
                return Data(line)
            }
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else { fail("seat server \(process.executableURL?.path ?? "?") exited") }
            buffer.append(chunk)
        }
    }
}

private struct SeatRequest: Encodable {
    let policy: String
    let seed: UInt64
    let seat: PlayerID
    let state: GameState
    let legalMoves: [GameMove]
    let ledger: PublicLedger
}

private struct SeatReply: Decodable {
    let move: GameMove?
    let error: String?
}

/// An old version, over a pipe. Every answer is checked against today's rules.
private struct RemoteSeat: LedgerAwarePolicy {
    let server: SeatServer
    let policy: String
    let id: String
    let tally: SeatTally

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        tally.decisions += 1
        let request = SeatRequest(policy: policy, seed: rng.next(), seat: observation.seat,
                                  state: observation.state, legalMoves: observation.legalMoves, ledger: ledger)
        guard let data = try? JSONEncoder().encode(request) else { fail("cannot encode a request") }
        let reply = try? JSONDecoder().decode(SeatReply.self, from: server.ask(data))
        guard let proposed = reply?.move else {
            tally.decodeErrors += 1
            tally.fallbacks += 1
            return fallback(observation)
        }
        let move = canonical(proposed, in: observation.legalMoves)
        let legal = observation.legalMoves.contains(move)
            || RulesEngine.isPermittedComposedProposal(move, by: observation.seat, in: observation.state,
                                                       legal: observation.legalMoves)
        guard legal else {
            let answeringAnOffer = observation.legalMoves.allSatisfy {
                if case .respondToTrade = $0 { true } else { false }
            }
            switch move {
            case .proposeTrade, .respondToTrade: tally.tradesBlocked += 1
            // Builds from before a987a25 (2026-09-02) could not be asked about
            // someone else's offer at all and answered as if it were their own
            // turn. Declining is what they did in effect.
            case _ where answeringAnOffer: tally.tradesBlocked += 1
            default: tally.fallbacks += 1
            }
            if tally.fallbacks < 5, ProcessInfo.processInfo.environment["ARENA_DEBUG"] != nil {
                Stderr.write("\(id) proposed \(move) in \(observation.state.phase); legal: \(observation.legalMoves.prefix(4))")
            }
            return fallback(observation)
        }
        return move
    }

    /// A proposal with the same content as an enumerated one, under that one's
    /// id. Builds before 2026-08-29 gave every offer a fresh `UUID()`; today an
    /// enumerated offer's id is derived from its content, so the same offer
    /// would otherwise be rejected for its name alone.
    private func canonical(_ move: GameMove, in legal: [GameMove]) -> GameMove {
        guard case .proposeTrade(let offer) = move else { return move }
        return legal.first {
            guard case .proposeTrade(let listed) = $0 else { return false }
            return listed.from == offer.from && listed.give == offer.give && listed.want == offer.want
        } ?? move
    }

    /// The least opinionated legal move: decline, else end the turn, else the
    /// first move offered (a forced choice such as a discard or a placement).
    private func fallback(_ observation: GameObservation) -> GameMove {
        let moves = observation.legalMoves
        if let decline = moves.first(where: { if case .respondToTrade(_, false) = $0 { true } else { false } }) {
            return decline
        }
        if moves.contains(.endTurn) { return .endTurn }
        return moves[0]
    }
}

private final class SeatFactory {
    let seatsDirectory: URL?
    private var servers: [String: SeatServer] = [:]

    init(seatsDirectory: URL?) { self.seatsDirectory = seatsDirectory }

    func make(_ name: String, tally: SeatTally) -> any Policy {
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { fail("seat '\(name)' is not <version>:<policy>") }
        if parts[0] == "local" { return LocalSeat(base: local(parts[1]), tally: tally) }
        return RemoteSeat(server: server(parts[0]), policy: parts[1], id: name, tally: tally)
    }

    private func local(_ policy: String) -> any Policy {
        switch policy {
        case "expert": return EvaluationPolicy()
        case "expert-holder": return EvaluationPolicy(id: "evaluation-holder", handDiscipline: false)
        case "classic": return HeuristicPolicy(personality: .balanced, id: "heuristic-classic")
        case "classic-aggressive": return HeuristicPolicy(personality: .aggressive, id: "heuristic-aggressive")
        case "classic-cautious": return HeuristicPolicy(personality: .cautious, id: "heuristic-cautious")
        default: fail("unknown local policy '\(policy)'")
        }
    }

    private func server(_ version: String) -> SeatServer {
        if let running = servers[version] { return running }
        guard let seatsDirectory else { fail("seat '\(version)' needs --seats-dir") }
        let binary = seatsDirectory.appendingPathComponent("seat-\(version)")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { fail("no seat server at \(binary.path)") }
        let started = SeatServer(binary: binary)
        servers[version] = started
        return started
    }
}

// MARK: - One game

/// Order-stable move text and its FNV-1a hash: the same rendering `sim` uses,
/// so a fingerprint changes exactly when the move sequence does.
private enum Rendering {
    static func table(_ amounts: [Resource: Int]) -> String {
        Resource.allCases.compactMap { resource in amounts[resource].map { "\(resource)=\($0)" } }
            .joined(separator: ",")
    }

    static func canonical(_ move: GameMove) -> String {
        switch move {
        case .discard(let amounts): return "discard[\(table(amounts))]"
        case .bankTrade(let give, let get): return "bankTrade[\(table(give))->\(table(get))]"
        case .buyArmyCard(let paying): return "buyArmyCard[\(table(paying))]"
        case .proposeTrade(let offer):
            return "proposeTrade[p\(offer.from.index):\(table(offer.give))->\(table(offer.want))]"
        default: return "\(move)"
        }
    }

    static func fingerprint(_ moves: [String]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in moves.joined().utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return String(hash, radix: 16)
    }
}

private struct SeatResult: Encodable {
    let seat: String
    let vp: Int
    let turnsEnded: Int
    /// Own turns ended holding more than the discard threshold (7).
    let turnsEndedOverSeven: Int
    let turnsEndedOverFifteen: Int
    let handAtEndTurnTotal: Int
    let maxHand: Int
    let cardsDiscarded: Int
    let decisions: Int
    let fallbacks: Int
    let decodeErrors: Int
    let tradesBlocked: Int
}

private struct GameRecord: Encodable {
    let match: String
    let seed: UInt64
    let seats: [String]
    let winner: Int?
    let moves: Int
    let fingerprint: String
    let results: [SeatResult]
}

private struct Hands {
    var turnsEnded = 0, overSeven = 0, overFifteen = 0, total = 0, maxHand = 0, discarded = 0
}

private func handSize(_ state: GameState, _ seat: PlayerID) -> Int {
    state.players[seat.index].resources.values.reduce(0, +)
}

private func play(match: String, seed: UInt64, seatNames: [String], factory: SeatFactory) -> GameRecord {
    let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed, shape: Ruleset.forMode(.classic).board),
                                  seed: seed, playerCount: seatNames.count, victoryPointTarget: 10)
    let tallies = seatNames.map { _ in SeatTally() }
    var policies: [PlayerID: any Policy] = [:]
    for (index, name) in seatNames.enumerated() {
        policies[state.players[index].id] = factory.make(name, tally: tallies[index])
    }
    var session = GameSession(state: state, policies: policies, policySeed: seed &* 31 &+ 7)
    var hands = Array(repeating: Hands(), count: seatNames.count)
    var trace: [String] = []
    for _ in 0..<maxMovesPerGame {
        guard case .seat = session.nextActor(), let decision = session.decideNextDetailed() else { break }
        let before = session.state
        let index = decision.seat.index
        let held = handSize(before, decision.seat)
        do { _ = try session.commit(seat: decision.seat, move: decision.move) } catch {
            fail("seed \(seed): today's rules rejected a checked move: \(error)")
        }
        trace.append("P\(index):\(Rendering.canonical(decision.move))")
        for seat in before.players.map(\.id) {
            hands[seat.index].maxHand = max(hands[seat.index].maxHand, handSize(session.state, seat))
        }
        if case .discard = decision.move { hands[index].discarded += held - handSize(session.state, decision.seat) }
        if case .endTurn = decision.move, case .mainTurn(let current) = before.phase, current == index {
            hands[index].turnsEnded += 1
            hands[index].total += held
            if held > before.rules.discardThreshold { hands[index].overSeven += 1 }
            if held > 15 { hands[index].overFifteen += 1 }
        }
    }
    var winner: Int?
    if case .gameOver(let who) = session.state.phase { winner = who.index }
    let results = seatNames.indices.map { index in
        SeatResult(seat: seatNames[index],
                   vp: session.state.victoryPoints(for: session.state.players[index].id),
                   turnsEnded: hands[index].turnsEnded, turnsEndedOverSeven: hands[index].overSeven,
                   turnsEndedOverFifteen: hands[index].overFifteen, handAtEndTurnTotal: hands[index].total,
                   maxHand: hands[index].maxHand, cardsDiscarded: hands[index].discarded,
                   decisions: tallies[index].decisions, fallbacks: tallies[index].fallbacks,
                   decodeErrors: tallies[index].decodeErrors, tradesBlocked: tallies[index].tradesBlocked)
    }
    return GameRecord(match: match, seed: seed, seats: seatNames, winner: winner, moves: trace.count,
                      fingerprint: Rendering.fingerprint(trace), results: results)
}

// MARK: - Schedule and CLI

/// One line of a schedule file.
private struct ScheduledGame: Decodable {
    let match: String
    let seed: UInt64
    let seats: [String]
}

private struct Options {
    var schedule: URL?
    var seatsDirectory: URL?
    var shard = 0
    var shards = 1
    var done: [URL] = []
    var seats: [String] = []
    var seed: UInt64 = 1
}

private func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.dropFirst().makeIterator()
    func value(_ flag: String) -> String {
        guard let next = iterator.next() else { fail("\(flag) needs a value") }
        return next
    }
    while let flag = iterator.next() {
        switch flag {
        case "--schedule": options.schedule = URL(fileURLWithPath: value(flag))
        case "--seats-dir": options.seatsDirectory = URL(fileURLWithPath: value(flag))
        case "--done": options.done.append(URL(fileURLWithPath: value(flag)))
        case "--seats": options.seats = value(flag).split(separator: ",").map(String.init)
        case "--seed": options.seed = UInt64(value(flag)) ?? { fail("--seed must be an integer") }()
        case "--shard":
            let pair = value(flag).split(separator: "/").compactMap { Int($0) }
            guard pair.count == 2, pair[1] > 0, (0..<pair[1]).contains(pair[0]) else { fail("--shard i/n") }
            (options.shard, options.shards) = (pair[0], pair[1])
        default: fail("unknown flag \(flag)")
        }
    }
    return options
}

/// Games already recorded, so a killed run resumes instead of replaying -
/// from any number of result files, so a resumed run may use a different
/// shard count than the one it replaces.
private func finishedGames(in files: [URL]) -> Set<String> {
    files.reduce(into: Set<String>()) { $0.formUnion(finishedGames(in: $1)) }
}

private func finishedGames(in file: URL) -> Set<String> {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    struct Key: Decodable { let match: String; let seed: UInt64; let seats: [String] }
    return Set(text.split(separator: "\n").compactMap { line in
        (try? JSONDecoder().decode(Key.self, from: Data(line.utf8))).map { "\($0.match)|\($0.seed)|\($0.seats)" }
    })
}

private let options = parse(CommandLine.arguments)
private let factory = SeatFactory(seatsDirectory: options.seatsDirectory)
private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}()

private func emit(_ record: GameRecord) {
    guard let data = try? encoder.encode(record) else { fail("cannot encode a result") }
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

if let schedule = options.schedule {
    guard let text = try? String(contentsOf: schedule, encoding: .utf8) else { fail("cannot read \(schedule.path)") }
    let finished = finishedGames(in: options.done)
    for (line, raw) in text.split(separator: "\n").enumerated() where line % options.shards == options.shard {
        guard let game = try? JSONDecoder().decode(ScheduledGame.self, from: Data(raw.utf8)) else {
            fail("schedule line \(line + 1) is not a game")
        }
        guard !finished.contains("\(game.match)|\(game.seed)|\(game.seats)") else { continue }
        emit(play(match: game.match, seed: game.seed, seatNames: game.seats, factory: factory))
    }
} else {
    guard options.seats.count == 4 else { fail("--seats needs four comma-separated seats, or use --schedule") }
    emit(play(match: "adhoc", seed: options.seed, seatNames: options.seats, factory: factory))
}
