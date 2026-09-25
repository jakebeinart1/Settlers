import Foundation

/// Who holds a rating. A person is keyed by name, because the app knows a
/// player by the name they type; a ghost by its id.
enum RatedEntity: Hashable, Sendable {
    case person(String)
    case ghost(String)
    case classic
    case expert

    /// The key ratings are stored under: "person:Jake", "ghost:jake", "classic".
    var key: String {
        switch self {
        case .person(let name): return "person:\(name)"
        case .ghost(let id): return "ghost:\(id)"
        case .classic: return "classic"
        case .expert: return "expert"
        }
    }
}

/// Elo for four-player Catan, by pairwise decomposition.
///
/// The winner scores 1 against each other seat, and two non-winners score
/// 0.5 against each other. Every pair is an ordinary Elo game at `pairK`,
/// computed from the ratings before the game.
///
/// ## Anchors
/// **Classic is the one fixed point** (1000). A pool where every rating
/// moves has nothing holding it, and the numbers drift together. Expert used
/// to be a second anchor; Jake asked (2026-09-25) that its rating come from
/// human games like a ghost's. So it *starts* at `expertStart` and moves.
///
/// ## Why 1229
/// Expert won 68.4% of 1,248 games against three Classic bots (the
/// `bot-strength` protocol; `BotDifficulty`'s doc comment). Its expected
/// pairwise score against one Classic seat is then
/// 0.684 + 0.5 x (1 - 0.684 - 0.316/3) = 0.789, which is
/// 400 x log10(0.789 / 0.211) = +229 over Classic.
enum Elo {
    static let start = 1000.0
    static let classicAnchor = 1000.0
    static let expertStart = 1229.0
    /// 32 per head-to-head game, spread over the three pairs a seat is in.
    static let pairK = 32.0 / 3.0

    static func rating(of entity: RatedEntity, in ratings: [RatedEntity: Double]) -> Double {
        switch entity {
        case .classic: return classicAnchor
        case .expert: return ratings[.expert] ?? expertStart
        default: return ratings[entity] ?? start
        }
    }

    /// The new rating of every moving entity in the game. Classic is never
    /// returned. Seats of the same entity (three Expert bots) do not rate
    /// each other, and each entity's deltas from all its seats are summed.
    static func update(_ ratings: [RatedEntity: Double], seats: [RatedEntity], winner: Int) -> [RatedEntity: Double] {
        var delta: [RatedEntity: Double] = [:]
        for i in seats.indices {
            for j in seats.indices where j > i && seats[i] != seats[j] {
                let score = i == winner ? 1.0 : j == winner ? 0.0 : 0.5
                let expected = 1 / (1 + pow(10, (rating(of: seats[j], in: ratings) - rating(of: seats[i], in: ratings)) / 400))
                let change = pairK * (score - expected)
                delta[seats[i], default: 0] += change
                delta[seats[j], default: 0] -= change
            }
        }
        var result: [RatedEntity: Double] = [:]
        for entity in seats where entity != .classic && result[entity] == nil {
            result[entity] = rating(of: entity, in: ratings) + (delta[entity] ?? 0)
        }
        return result
    }
}
