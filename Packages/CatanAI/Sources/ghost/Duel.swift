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
    switch name {
    case "timing": return TimingPolicy.oneAheadV1
    case "trade-guard": return TradeGuardPolicy.v1
    case "pcc": return EvaluationPolicy(revision: .pointCompletingCardsV1)
    case "legacy": return EvaluationPolicy()
    case "classic": return HeuristicPolicy(personality: .balanced, id: "balanced")
    default: fail("unknown seat \(name)")
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
