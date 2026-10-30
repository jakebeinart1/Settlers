import CatanAI
import CatanEngine
import Foundation

/// `ghost duel`: the bot-strength protocol for policies `sim` cannot name
/// (ghost choice models, Expert revisions). Each board seed is played
/// four times, the candidate in each chair against three anchors; `--lone`
/// flips it, one anchor against three candidates, which asks how well a
/// table of candidates holds off a single player, the shape of every app
/// game with one human. One JSON line per game; `seats` carries each seat's
/// tallies, so behaviour and strength come from the same games.
func seatPolicy(_ name: String) throws -> any Policy {
    if name.hasPrefix("choices:") {
        // choices:<path>[@delta]: a fitted choice model, the person choosing
        // among moves within delta of Expert's best (default: the shipped limit).
        let spec = name.dropFirst("choices:".count).split(separator: "@").map(String.init)
        let model = try JSONDecoder().decode(ChoiceModel.self, from: Data(contentsOf: URL(fileURLWithPath: spec[0])))
        let regret = spec.count > 1 ? Double(spec[1]) : GhostPolicy.choiceRegret
        return GhostPolicy(person: .anchored(at: anchor), lambda: 0, choices: model, regret: regret)
    }
    if name.hasPrefix("opening") {
        // opening[:og,new]: OpeningPolicy.v1, or its opening weights swept (in pips).
        let w = name.split(separator: ":").dropFirst().first?.split(separator: ",").compactMap { Double($0) } ?? []
        guard !w.isEmpty else { return OpeningPolicy.v1 }
        return OpeningPolicy(oreGrain: w[0], newType: w.count > 1 ? w[1] : OpeningPolicy.v1.newType, id: name)
    }
    if name.hasPrefix("weights:") {
        // weights:production=0.5,roadLength=0.05: OpeningPolicy.v1 evaluating
        // with Classic's shipping weights, the named ones replaced.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EvaluationWeights.default)) as? [String: Any] ?? [:]
        for pair in name.dropFirst("weights:".count).split(separator: ",") {
            let parts = pair.split(separator: "=")
            guard parts.count == 2, json[String(parts[0])] != nil, let value = Double(parts[1]) else { fail("bad weight \(pair)") }
            json[String(parts[0])] = value
        }
        let weights = try JSONDecoder().decode(EvaluationWeights.self, from: JSONSerialization.data(withJSONObject: json))
        let timing = TimingPolicy(rules: [.margin, .preroll, .lean], id: name, weights: weights)
        let base = OpeningPolicy.v1
        return OpeningPolicy(oreGrain: base.oreGrain, newType: base.newType, id: name,
                             rest: TradeGuardPolicy(timing: timing, id: name))
    }
    switch name {
    case "timing": return TimingPolicy.oneAheadV1
    case "trade-guard": return TradeGuardPolicy.v1
    case "pcc": return EvaluationPolicy(revision: .pointCompletingCardsV1)
    case "legacy": return EvaluationPolicy()
    case "classic": return HeuristicPolicy(personality: .balanced, id: "balanced")
    default:
        // Any other Expert revision by its raw name, e.g. cityProductionV1.
        guard let revision = ExpertRevision(rawValue: name) else { fail("unknown seat \(name)") }
        return revision.policy
    }
}

func duel(candidate: String, anchor anchorName: String, firstSeed: UInt64, seeds: Int, lone: Bool,
          shard: (index: Int, count: Int)) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    for game in stride(from: shard.index, to: seeds * 4, by: shard.count) {
        let seed = firstSeed + UInt64(game / 4)
        let chair = game % 4
        let line: String = try autoreleasepoolIfAvailable {
            let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
            var policies: [PlayerID: any Policy] = [:]
            var labels: [String] = []
            for player in initial.players {
                let isCandidate = (player.id.index == chair) != lone
                policies[player.id] = try seatPolicy(isCandidate ? candidate : anchorName)
                labels.append(isCandidate ? "candidate" : "anchor")
            }
            var session = GameSession(state: initial, policies: policies, policySeed: seed &* 31 &+ 7)
            var moves: [LoggedMove] = []
            while moves.count < 3000, let step = try session.step() {
                moves.append(LoggedMove(player: step.actor, move: step.move))
            }
            let logged = LoggedGame(id: "\(seed)-\(chair)", initialState: initial, humanSeats: [], events: moves)
            let seats = try ladderSeats(logged, labels: labels, owner: "", ownerName: "")
            let record = DuelRecord(seed: seed, chair: chair, lone: lone, candidate: candidate, anchor: anchorName,
                                    moves: moves.count, decisive: seats.contains { $0.won },
                                    candidateWon: seats.contains { $0.won && $0.label == "candidate" }, seats: seats)
            return String(bytes: try encoder.encode(record), encoding: .utf8) ?? ""
        }
        print(line)
    }
}

struct DuelRecord: Encodable {
    let seed: UInt64
    let chair: Int
    let lone: Bool
    let candidate: String
    let anchor: String
    let moves: Int
    let decisive: Bool
    let candidateWon: Bool
    let seats: [LadderSeat]
}

/// A long loop of Foundation work leaks without a pool per iteration on
/// macOS (2026-09-29: ~23MB/s, three kernel panics). Linux has no pools.
func autoreleasepoolIfAvailable<T>(_ body: () throws -> T) rethrows -> T {
    #if canImport(Darwin)
    return try autoreleasepool { try body() }
    #else
    return try body()
    #endif
}
