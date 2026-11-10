import CatanEngine
import Foundation
import SwiftUI

/// A phone remembers which ladder the player last inspected. The preference
/// selects a view only; it never changes a match's saved rules or opponents.
enum RatingPoolPreference {
    private static let storageKey = "playerRatingPool"

    static func load(defaults: UserDefaults = .standard) -> RatingPool {
        if let data = defaults.data(forKey: storageKey),
           let pool = try? JSONDecoder().decode(RatingPool.self, from: data),
           RatingPool.available.contains(pool) { return pool }
        if let setup = MatchSetupStore.shared.load().value {
            let pool = RatingPool(mode: setup.mode, variant: setup.variant, difficulty: setup.difficulty)
            if RatingPool.available.contains(pool) { return pool }
        }
        return RatingPool(mode: .classic, difficulty: .classic)
    }

    static func save(_ pool: RatingPool, defaults: UserDefaults = .standard) {
        // All fields are raw-value enums, so encoding has no failure path.
        defaults.set(try? JSONEncoder().encode(pool), forKey: storageKey)
    }
}

struct RatingPageSelection: Identifiable {
    let playerID: String
    let pool: RatingPool
    var id: String { "\(playerID):\(pool.id)" }
}

/// Disk reads and rating replay happen away from the main actor. Every screen
/// renders one coherent snapshot rather than reading files during SwiftUI body.
struct PlayerRatingSnapshot: Sendable {
    let me: String
    let names: [String: String]
    let ratings: PlayerRatings
    var localOwnerBindings: [String: String] = [:]

    static let empty = Self(me: "", names: [:], ratings: PlayerRatings(records: []))

    static func load(stats: SeatStatsStore = .shared, players: PlayerDirectory = .shared) async -> Self {
        await Task.detached(priority: .userInitiated) {
            let directory = players.load()
            let bindings = directory.localOwnerBindings ?? [:]
            let me = bindings[directory.me] ?? directory.me
            var names = canonicalNames(directory.names, bindings: bindings)
            if names[me] == nil { names[me] = players.name(of: directory.me) }
            // A durable adoption binding can precede its record refiles. Normalize
            // before replay so split local/account records share one Elo history.
            let records = canonicalRecords(stats.all(), bindings: bindings)
            return Self(me: me, names: names, ratings: PlayerRatings(records: records),
                        localOwnerBindings: bindings)
        }.value
    }

    private static func canonicalNames(_ names: [String: String], bindings: [String: String]) -> [String: String] {
        var canonical = names.filter { bindings[$0.key] == nil }
        for (id, name) in names.sorted(by: { $0.key < $1.key }) {
            let owner = bindings[id] ?? id
            if canonical[owner] == nil { canonical[owner] = name }
        }
        return canonical
    }

    private static func canonicalRecords(_ records: [SeatStatsRecord],
                                         bindings: [String: String]) -> [SeatStatsRecord] {
        records.map { record in
            let seats = record.seats.map { entry in
                guard case .person(let id) = RatedEntity(key: entry.entity),
                      let owner = bindings[id] else { return entry }
                return SeatStatsRecord.Entry(entity: RatedEntity.person(owner).key, stats: entry.stats)
            }
            return SeatStatsRecord(match: record.match, date: record.date, seats: seats,
                                   ratingPool: record.ratingPool, abandoned: record.abandoned)
        }
    }

    func resolvedPlayerID(_ player: String) -> String { localOwnerBindings[player] ?? player }

    func name(for player: String) -> String { names[resolvedPlayerID(player)] ?? names[player] ?? "Player" }

    /// People known online appear even before their first game in this pool.
    /// Ghosts have their own established page and are never mistaken for people.
    var playerIDs: [String] {
        Set((ratings.playerIDs + Array(names.keys) + (me.isEmpty ? [] : [me])).map(resolvedPlayerID)).sorted {
            (name(for: $0).localizedLowercase, $0) < (name(for: $1).localizedLowercase, $1)
        }
    }
}

enum RatingPresentation {
    static let gain = Color(red: 0.63, green: 0.83, blue: 0.60)
    static let loss = Color(red: 1.0, green: 0.65, blue: 0.58)

    static func delta(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    static func record(wins: Int, losses: Int) -> String {
        "\(wins) \(wins == 1 ? "win" : "wins") · \(losses) \(losses == 1 ? "loss" : "losses")"
    }

    static func syncDescription(_ status: LiveSync.Status?) -> String {
        guard let status else { return "Saved on this device" }
        switch status {
        case .never: return "Connecting your records…"
        case .online(let date): return "Synced \(date.formatted(date: .omitted, time: .shortened))"
        case .partiallySynced(let count):
            return count == 1 ? "1 recording couldn’t sync and is still on this device."
                : "\(count) recordings couldn’t sync and are still on this device."
        case .offline: return "Offline · saved records will sync when connected"
        case .failed: return "Records could not sync. Your saved games remain on this device."
        case .noAccount: return "Sign in to iCloud in Settings to sync across devices"
        case .noName: return "Choose a leaderboard name to sync your records"
        case .nameTaken: return "Choose another leaderboard name to sync your records"
        }
    }
}
