// Seat server: one historical build of the bots, answering move requests.
//
// ## Why this file is compiled into OLD checkouts
// The tournament puts bots from different commits at one table. Two versions
// of `CatanAI` cannot link into one process (same module name, different
// code), so each version runs as its own process built from its own commit,
// and the referee (`arena`, built from today's tree) asks it for moves over a
// pipe. `scripts/tournament/build-version.sh` drops this file into a clean
// export of the commit as an extra executable target and builds it there, so
// the bot answering is exactly the bot that shipped at that commit, running on
// that commit's own engine helpers.
//
// ## The API differs by era, so the build passes flags
// - `POLICY_API`   the `Policy` seam exists (f7268e1, 2026-08-29 onward)
// - `LEDGER_API`   `LedgerAwarePolicy` / `PublicLedger` exist
// - `EXPERT`       `EvaluationPolicy` exists (1f2c8f0, 2026-09-14 onward)
// - `RNG_OVERLOAD` `Bot.decide(for:player:rng:)` exists
// - `TRADE_EVAL`   `TradeHeuristics.evaluate(offer:receiver:state:personality:)`
//
// ## Wire format: one JSON object per line each way
// in:  {"policy": "...", "seed": N, "seat": ..., "state": ..., "legalMoves": [...], "ledger": ...?}
// out: {"move": ..., "ledger": true|false} or {"error": "..."}
// The referee validates every move against today's rules; this process only
// proposes. A request this build cannot decode is answered with an error so
// the referee counts it rather than guessing.

import CatanAI
import CatanEngine
import Foundation

private struct Request: Decodable {
    let policy: String
    let seed: UInt64
    let seat: PlayerID
    let state: GameState
    let legalMoves: [GameMove]
}

#if LEDGER_API
private struct LedgerBox: Decodable { let ledger: PublicLedger? }
#endif

private struct Reply: Encodable {
    let move: GameMove
    let ledger: Bool
}

#if !POLICY_API
/// SplitMix64, for builds that predate `RandomSource`. Any seeded generator
/// would do; what matters is that the referee's seed decides the tie-breaks.
private struct SeatRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
#endif

private func personality(_ name: String) -> BotPersonality {
    switch name {
    case "classic-aggressive": return .aggressive
    case "classic-cautious": return .cautious
    default: return .balanced
    }
}

#if POLICY_API
private func makePolicy(_ name: String) -> (any Policy)? {
    switch name {
    case "classic", "classic-balanced", "classic-aggressive", "classic-cautious":
        return HeuristicPolicy(personality: personality(name), id: "heuristic-\(name)")
    #if EXPERT
    case "expert":
        return EvaluationPolicy()
    #endif
    default:
        return nil
    }
}

/// Built per request: every policy here is a value type with no state
/// between calls, which is exactly what `Policy` promises.
private func decide(_ request: Request, line: Data) -> Reply? {
    guard let policy = makePolicy(request.policy) else { return nil }
    let observation = GameObservation(seat: request.seat, state: request.state, legalMoves: request.legalMoves)
    var rng = RandomSource(seed: request.seed)
    #if LEDGER_API
    if let aware = policy as? any LedgerAwarePolicy {
        if let box = try? JSONDecoder().decode(LedgerBox.self, from: line), let ledger = box.ledger {
            return Reply(move: aware.decide(observation, ledger: ledger, rng: &rng), ledger: true)
        }
        return Reply(move: aware.decide(observation, rng: &rng), ledger: false)
    }
    #endif
    return Reply(move: policy.decide(observation, rng: &rng), ledger: false)
}
#else
/// Before the `Policy` seam: `Bot` chose for the whole table from its own
/// engine's move list, and trade answers went through `TradeHeuristics`
/// directly from the app. The referee masks the answer either way.
private func decide(_ request: Request, line: Data) -> Reply? {
    guard request.policy.hasPrefix("classic") else { return nil }
    let bot = Bot(personality: personality(request.policy))
    if case .respondToTrade(let offerID, _)? = request.legalMoves.first,
       request.legalMoves.allSatisfy({ if case .respondToTrade = $0 { return true } else { return false } }) {
        #if TRADE_EVAL
        guard let offer = request.state.pendingTradeOffers.first(where: { $0.id == offerID }) else { return nil }
        let yes = TradeHeuristics.evaluate(offer: offer, receiver: request.seat, state: request.state,
                                           personality: personality(request.policy))
        return Reply(move: .respondToTrade(offerID: offerID, accept: yes), ledger: false)
        #else
        return Reply(move: .respondToTrade(offerID: offerID, accept: false), ledger: false)
        #endif
    }
    #if RNG_OVERLOAD
    var rng = SeatRNG(state: request.seed)
    return Reply(move: bot.decide(for: request.state, player: request.seat, rng: &rng), ledger: false)
    #else
    return Reply(move: bot.decide(for: request.state, player: request.seat), ledger: false)
    #endif
}
#endif

nonisolated(unsafe) private var reportedErrors = 0

/// Fields an older `GameState` requires that today's no longer writes, with
/// the value that means "nothing happened": an old build reads them, never
/// plays by them. Filled in only when the decoder names one as missing.
nonisolated(unsafe) private let legacyDefaults: [String: Any] = ["log": [String]()]

/// Inserts `legacyDefaults[key]` at `path` in `object`.
private func insert(_ key: String, at path: [CodingKey], in object: inout Any) -> Bool {
    guard var dictionary = object as? [String: Any] else { return false }
    guard let head = path.first else {
        guard let value = legacyDefaults[key], dictionary[key] == nil else { return false }
        dictionary[key] = value
        object = dictionary
        return true
    }
    guard var child = dictionary[head.stringValue], insert(key, at: Array(path.dropFirst()), in: &child) else {
        return false
    }
    dictionary[head.stringValue] = child
    object = dictionary
    return true
}

private func decodeRequest(_ data: Data) throws -> (Request, Data) {
    var data = data
    for _ in 0..<legacyDefaults.count {
        do {
            return (try JSONDecoder().decode(Request.self, from: data), data)
        } catch DecodingError.keyNotFound(let key, let context) {
            var object = try JSONSerialization.jsonObject(with: data)
            guard insert(key.stringValue, at: context.codingPath, in: &object) else { throw DecodingError.keyNotFound(key, context) }
            data = try JSONSerialization.data(withJSONObject: object)
        }
    }
    return (try JSONDecoder().decode(Request.self, from: data), data)
}

private func answer(_ line: String) -> String {
    let data: Data
    let request: Request
    do {
        (request, data) = try decodeRequest(Data(line.utf8))
    } catch {
        reportedErrors += 1
        if reportedErrors <= 3 { FileHandle.standardError.write(Data("seat-server: \(error)\n".utf8)) }
        return #"{"error":"decode"}"#
    }
    guard let reply = decide(request, line: data),
          let encoded = try? JSONEncoder().encode(reply) else {
        return #"{"error":"policy"}"#
    }
    return String(bytes: encoded, encoding: .utf8) ?? #"{"error":"policy"}"#
}

while let line = readLine(strippingNewline: true) {
    FileHandle.standardOutput.write(Data((answer(line) + "\n").utf8))
}
