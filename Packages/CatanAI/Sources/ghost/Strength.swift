import CatanAI
import CatanEngine
import Foundation

/// The seat policy a ghost is measured against.
enum Tier: String {
    case classic, expert

    func policy() -> any Policy {
        switch self {
        case .classic: return HeuristicPolicy(personality: .balanced, id: "balanced")
        case .expert: return EvaluationPolicy()
        }
    }
}

struct WinRate {
    let wins: Int
    let games: Int
    var rate: Double { games == 0 ? 0 : Double(wins) / Double(games) }

    /// Wilson 95% interval: honest at small samples, where the normal
    /// approximation can run below 0 or above 1.
    var interval: (low: Double, high: Double) {
        guard games > 0 else { return (0, 1) }
        let z = 1.96, n = Double(games), p = rate
        let centre = (p + z * z / (2 * n)) / (1 + z * z / n)
        let half = z * sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / (1 + z * z / n)
        return (centre - half, centre + half)
    }

    var summary: String {
        let (low, high) = interval
        return "\(wins)/\(games) = " + number(rate) + "  95% CI [" + number(low) + ", " + number(high) + "]"
    }
}

/// The ghost in every chair of each seed, the other three seats the tier:
/// the bot-strength protocol's rotation, so turn order cancels. Seeds start
/// at 900,000, the held-out range, never the ones anything was fitted on.
func ghostWinRate(person: PersonModel, lambda: Double, tier: Tier, games: Int) throws -> WinRate {
    var wins = 0
    for game in 0..<games {
        let seed = 900_000 + UInt64(game / 4)
        let initial = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        var policies: [PlayerID: any Policy] = [:]
        for player in initial.players { policies[player.id] = tier.policy() }
        let chair = initial.players[game % initial.players.count].id
        policies[chair] = GhostPolicy(person: person, lambda: lambda)
        var session = GameSession(state: initial, policies: policies, policySeed: seed)
        _ = try session.run()
        if case .gameOver(let winner) = session.state.phase, winner == chair { wins += 1 }
    }
    return WinRate(wins: wins, games: games)
}

func readPerson(_ path: String) throws -> PersonModel {
    try JSONDecoder().decode(PersonModel.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
}
