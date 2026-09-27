import Foundation

/// Every rating, how many rated games each entity has, which matches were
/// already rated, and every change ever made.
struct Ratings: Codable, Equatable, Sendable {
    struct Change: Codable, Equatable, Sendable {
        let match: UUID
        let entity: String
        let before: Double
        let after: Double
        let date: Date
    }

    var ratings: [String: Double] = [:]
    var games: [String: Int] = [:]
    var ratedMatches: [UUID] = []
    /// Append-only (Jake, 2026-09-25: "All the data needs to be saved").
    var history: [Change] = []

    mutating func rate(match: UUID, seats: [RatedEntity], winner: Int, date: Date) {
        var current: [RatedEntity: Double] = [:]
        for entity in seats { current[entity] = ratings[entity.key] }
        let updated = Elo.update(current.compactMapValues { $0 }, seats: seats, winner: winner)
        for entity in Self.distinct(seats) {
            // Classic's rating is the fixed anchor, but its games still count.
            games[entity.key, default: 0] += 1
            guard entity != .classic, let after = updated[entity] else { continue }
            let before = Elo.rating(of: entity, in: current.compactMapValues { $0 })
            ratings[entity.key] = after
            history.append(Change(match: match, entity: entity.key, before: before, after: after, date: date))
        }
        ratedMatches.append(match)
    }

    /// Seat order, first appearance: deterministic, unlike iterating a Set.
    private static func distinct(_ seats: [RatedEntity]) -> [RatedEntity] {
        var seen: [RatedEntity] = []
        for entity in seats where !seen.contains(entity) { seen.append(entity) }
        return seen
    }
}

/// Elo ratings, persisted.
///
/// ## Why the match-id list
/// A completion can be replayed: a resumed session re-runs the completion of
/// a match whose commit landed but was never acknowledged. Rating it twice
/// would count one game double, so a match already in `ratedMatches` is a
/// no-op.
///
/// ## Why a corrupt file is moved aside
/// Loading it as empty and then writing would erase every rating without a
/// word. The damaged file is kept as `ratings.corrupt.json`.
public struct RatingStore: Sendable {
    public static let shared = RatingStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])

    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("ratings.json") }

    init(directory: URL) {
        self.directory = directory
    }

    func load() -> Ratings {
        guard let data = try? Data(contentsOf: fileURL) else { return Ratings() }
        return (try? JSONDecoder().decode(Ratings.self, from: data)) ?? Ratings()
    }

    /// Rates one finished game. `seats` are in turn order; `winner` indexes them.
    func record(match: UUID, seats: [RatedEntity], winner: Int, date: Date = Date()) throws {
        try preserveIfCorrupt()
        var stored = load()
        guard !stored.ratedMatches.contains(match) else { return }
        stored.rate(match: match, seats: seats, winner: winner, date: date)
        try write(stored)
    }

    /// Every rating recomputed from scratch, oldest game first.
    ///
    /// ## Why a replay rather than applying new games
    /// Elo depends on order. Phones learn about the same games in different
    /// orders - a friend's game played an hour ago arrives after yours played
    /// a minute ago - so applying each as it arrives would leave two phones
    /// with two different ladders forever. Replaying the whole set in
    /// (date, match id) order gives every phone that holds the same games
    /// the same ratings, to the last decimal. A record whose seats cannot be
    /// read, or with no single winner, is skipped rather than guessed at.
    func rebuild(from records: [SeatStatsRecord]) throws {
        try preserveIfCorrupt()
        var rebuilt = Ratings()
        let ordered = records.sorted { ($0.date, $0.match.uuidString) < ($1.date, $1.match.uuidString) }
        for record in ordered where !rebuilt.ratedMatches.contains(record.match) {
            let seats = record.seats.compactMap { RatedEntity(key: $0.entity) }
            let winners = record.seats.indices.filter { record.seats[$0].stats.won }
            guard seats.count == record.seats.count, winners.count == 1 else { continue }
            rebuilt.rate(match: record.match, seats: seats, winner: winners[0], date: record.date)
        }
        try write(rebuilt)
    }

    private func write(_ ratings: Ratings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(ratings).write(to: fileURL, options: .atomic)
    }

    private func preserveIfCorrupt() throws {
        guard let data = try? Data(contentsOf: fileURL),
              (try? JSONDecoder().decode(Ratings.self, from: data)) == nil else { return }
        let aside = directory.appendingPathComponent("ratings.corrupt.json")
        try? FileManager.default.removeItem(at: aside)
        try FileManager.default.moveItem(at: fileURL, to: aside)
    }
}
