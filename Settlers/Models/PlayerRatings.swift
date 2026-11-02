import CatanEngine
import Foundation

/// Whole-game wins and losses, rather than one result for every opposing seat.
/// A restart is a loss and is also retained separately for its explanation.
struct PlayerRatingRecord: Equatable, Sendable {
    var wins = 0
    var losses = 0
    var forfeits = 0

    var games: Int { wins + losses }
    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) }

    mutating func add(won: Bool, abandoned: Bool) {
        if won { wins += 1 } else { losses += 1 }
        if abandoned { forfeits += 1 }
    }
}

struct PlayerRatingStanding: Equatable, Sendable {
    var rating = PlayerRatings.startingRating
    var record = PlayerRatingRecord()

    var wins: Int { record.wins }
    var losses: Int { record.losses }
    var forfeits: Int { record.forfeits }
    var games: Int { record.games }
    var isRated: Bool { games > 0 }
    var displayedRating: Int { Int(rating.rounded()) }
}

/// A durable match's contribution to its player's selected competition.
/// Rebuilding from the same match set produces the same complete history.
struct PlayerRatingChange: Equatable, Identifiable, Sendable {
    var id: UUID { match }
    let match: UUID
    let playerID: String
    let pool: RatingPool
    let before: Double
    let after: Double
    let date: Date
    let won: Bool
    let abandoned: Bool

    /// The visible numbers must agree: 1000 → 1024 always says +24.
    /// Rounding the fractional delta instead can differ by a point.
    var displayedDelta: Int { Int(after.rounded()) - Int(before.rounded()) }
}

/// The player's record against the computer, independent of the ghost ladder.
///
/// Every pool begins at 1000 for both the person and its one shared AI entry.
/// These are independent starting references, not strength measurements. A
/// four-seat game has one winner, so equal-rated opponents give the person a
/// 1-in-4 expected win probability, not the head-to-head 1-in-2 probability.
/// The opponent's repeated chairs contribute to that probability, but a game
/// changes the AI entry only once, by the opposite of the person's change.
///
/// The ledger is derived from verified per-seat records in (date, match ID)
/// order. Phones receive matches in different orders; applying arrivals
/// incrementally would leave their ratings different permanently. The old
/// multiplayer/ghost Elo remains untouched in RatingStore.
struct PlayerRatings: Equatable, Sendable {
    static let startingRating = 1000.0
    static let gameK = 32.0
    private static let ratingScale = 400.0

    private struct PlayerKey: Hashable, Sendable {
        let playerID: String
        let pool: RatingPool
    }

    private struct RatedGame {
        let record: SeatStatsRecord
        let pool: RatingPool
        let playerID: String
        let won: Bool
    }

    private var players: [PlayerKey: PlayerRatingStanding] = [:]
    private var ais: [RatingPool: PlayerRatingStanding] = [:]
    private(set) var changes: [PlayerRatingChange] = []
    private(set) var pools = RatingPool.available

    var playerIDs: [String] { Set(changes.map(\.playerID)).sorted() }

    init(records: [SeatStatsRecord]) {
        for record in Self.uniqueRecords(records) {
            guard let game = Self.ratedGame(record) else { continue }
            apply(game)
            if !pools.contains(game.pool) { pools.append(game.pool) }
        }
    }

    func standing(for playerID: String, in pool: RatingPool) -> PlayerRatingStanding {
        players[PlayerKey(playerID: playerID, pool: pool)] ?? PlayerRatingStanding()
    }

    func aiStanding(in pool: RatingPool) -> PlayerRatingStanding {
        ais[pool] ?? PlayerRatingStanding()
    }

    /// An overall record can sum outcomes; ratings cannot be averaged across
    /// unrelated competitions, so this deliberately returns no combined Elo.
    func overallRecord(for playerID: String) -> PlayerRatingRecord {
        var record = PlayerRatingRecord()
        for change in changes where change.playerID == playerID {
            record.add(won: change.won, abandoned: change.abandoned)
        }
        return record
    }

    private mutating func apply(_ game: RatedGame) {
        let key = PlayerKey(playerID: game.playerID, pool: game.pool)
        var player = players[key] ?? PlayerRatingStanding()
        var ai = ais[game.pool] ?? PlayerRatingStanding()
        let before = player.rating
        let botCount = Double(game.record.seats.count - 1)
        let expected = 1 / (1 + botCount * pow(10, (ai.rating - before) / Self.ratingScale))
        let change = Self.gameK * ((game.won ? 1.0 : 0.0) - expected)
        let abandoned = game.record.abandoned == true
        player.rating += change
        player.record.add(won: game.won, abandoned: abandoned)
        ai.rating -= change
        ai.record.add(won: !game.won, abandoned: false)
        players[key] = player
        ais[game.pool] = ai
        changes.append(PlayerRatingChange(match: game.record.match, playerID: game.playerID, pool: game.pool,
                                          before: before, after: player.rating, date: game.record.date,
                                          won: game.won, abandoned: abandoned))
    }

    /// Identical duplicate deliveries count once. Conflicting copies of one
    /// match are excluded instead of letting input order choose its result.
    private static func uniqueRecords(_ records: [SeatStatsRecord]) -> [SeatStatsRecord] {
        Dictionary(grouping: records, by: \.match).values.compactMap { copies in
            guard let first = copies.first, copies.allSatisfy({ $0 == first }) else { return nil }
            return first
        }.sorted { ($0.date, $0.match.uuidString) < ($1.date, $1.match.uuidString) }
    }

    private static func ratedGame(_ record: SeatStatsRecord) -> RatedGame? {
        guard GameSetup.supportedPlayerCounts.contains(record.seats.count),
              record.seats.enumerated().allSatisfy({ $0.offset == $0.element.stats.seat }),
              record.seats.filter({ $0.stats.won }).count == 1 else { return nil }
        let people = record.seats.filter { $0.entity.hasPrefix(RatedEntity.personPrefix) }
        guard people.count == 1, let person = people.first,
              case .person(let id) = RatedEntity(key: person.entity), !id.isEmpty,
              !(record.abandoned == true && person.stats.won),
              let difficulty = ordinaryDifficulty(record) else { return nil }
        let pool = record.ratingPool ?? RatingPool(mode: .classic, difficulty: difficulty)
        guard pool.isSupported, pool.difficulty == difficulty else { return nil }
        return RatedGame(record: record, pool: pool, playerID: id, won: person.stats.won)
    }

    /// Records without context predate mode ratings, when only Classic
    /// Standard was recorded. Homogeneous ordinary seats reveal their tier;
    /// ghosts, mixed tiers and malformed identities must never be guessed at.
    private static func ordinaryDifficulty(_ record: SeatStatsRecord) -> BotDifficulty? {
        let bots = record.seats.filter { !$0.entity.hasPrefix(RatedEntity.personPrefix) }
        if bots.allSatisfy({ $0.entity == RatedEntity.classic.key }) { return .classic }
        if bots.allSatisfy({ $0.entity == RatedEntity.expert.key }) { return .expert }
        return nil
    }
}
