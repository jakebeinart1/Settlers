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

    static let empty = Self(me: "", names: [:], ratings: PlayerRatings(records: []))

    static func load(stats: SeatStatsStore = .shared, players: PlayerDirectory = .shared) async -> Self {
        await Task.detached(priority: .userInitiated) {
            let directory = players.load()
            var names = directory.names
            names[directory.me] = players.name(of: directory.me)
            return Self(me: directory.me, names: names, ratings: PlayerRatings(records: stats.all()))
        }.value
    }

    func name(for player: String) -> String { names[player] ?? "Player" }

    /// People known online appear even before their first game in this pool.
    /// Ghosts have their own established page and are never mistaken for people.
    var playerIDs: [String] {
        Set(ratings.playerIDs + Array(names.keys) + (me.isEmpty ? [] : [me])).sorted {
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
        case .offline: return "Offline · saved records will sync when connected"
        case .failed: return "Records could not sync. Your saved games remain on this device."
        case .noAccount: return "Sign in to iCloud in Settings to sync across devices"
        case .noName: return "Choose a leaderboard name to sync your records"
        case .nameTaken: return "Choose another leaderboard name to sync your records"
        }
    }
}

/// A single framed standing belongs on the title screen; the chart and every
/// mode's record remain one tap away instead of turning the menu into a dashboard.
struct PlayerRatingMenuPlaque: View {
    var refreshToken = 0
    let onOpen: (String, RatingPool) -> Void

    @State private var snapshot = PlayerRatingSnapshot.empty
    @State private var pool = RatingPoolPreference.load()
    @State private var foregroundToken = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Button { onOpen(snapshot.me, pool) } label: {
            VStack(alignment: .leading, spacing: 9) {
                standingRow
                Rectangle().fill(SettingsChrome.ornamentGold.opacity(0.28)).frame(height: 1)
                overallRow
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(snapshot.me.isEmpty)
        .accessibilityIdentifier("main-menu.ratings")
        .task(id: "\(refreshToken):\(foregroundToken)") { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { foregroundToken += 1 }
        }
    }

    private var standingRow: some View {
        let standing = snapshot.ratings.standing(for: snapshot.me, in: pool)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.me.isEmpty ? "Your rating" : snapshot.name(for: snapshot.me))
                    .font(.system(.headline, design: .serif))
                    .lineLimit(1)
                Text("\(pool.displayName) · \(pool.difficulty.displayName) AI")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 1) {
                Text(standing.isRated ? "\(standing.displayedRating)" : "Unrated")
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(SettingsChrome.ornamentGold)
                Text("Elo").font(.system(.caption2, design: .serif)).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var overallRow: some View {
        let record = snapshot.ratings.overallRecord(for: snapshot.me)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(record.games == 0 ? "Play against AI to begin your record" :
                    "All modes: \(RatingPresentation.record(wins: record.wins, losses: record.losses))")
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(SettingsChrome.ornamentGold)
        }
    }

    private func refresh() async {
        while !Task.isCancelled {
            snapshot = await PlayerRatingSnapshot.load()
            pool = RatingPoolPreference.load()
            if let liveSync = LiveSync.shared {
                await liveSync.refreshIfDue()
                snapshot = await PlayerRatingSnapshot.load()
            }
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }
}
