import SwiftUI

/// Elo is an accessory to the existing Leaderboard action, not another home
/// section. Large text gets the whole row for the action's name.
struct LeaderboardMenuButton: View {
    var refreshToken = 0
    let onOpen: () -> Void
    @State private var snapshot = PlayerRatingSnapshot.empty
    @State private var pool = RatingPoolPreference.load()
    @State private var foregroundToken = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GoldRowButton(title: "Leaderboard", systemImage: "trophy.fill",
                      iconColor: SettingsChrome.ornamentGold, trailing: { accessory }, action: onOpen)
            .accessibilityIdentifier(AccessibilityID.MainMenu.leaderboard)
            .task(id: "\(refreshToken):\(foregroundToken)") { await refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { foregroundToken += 1 }
            }
    }

    @ViewBuilder private var accessory: some View {
        if !dynamicTypeSize.isAccessibilitySize && !snapshot.me.isEmpty {
            let standing = snapshot.ratings.standing(for: snapshot.me, in: pool)
            Text(standing.isRated ? "\(standing.displayedRating.formatted()) Elo" : "Unrated")
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(SettingsChrome.ornamentGold)
                .lineLimit(1)
                .accessibilityLabel("\(pool.displayName), \(pool.difficulty.displayName) AI, "
                    + (standing.isRated ? "\(standing.displayedRating.formatted()) Elo" : "Unrated"))
        }
    }

    private func refresh() async {
        while !Task.isCancelled {
            let local = await PlayerRatingSnapshot.load()
            guard !Task.isCancelled else { return }
            snapshot = local
            pool = RatingPoolPreference.load()
            if let liveSync = LiveSync.shared {
                await liveSync.refreshIfDue()
                let synced = await PlayerRatingSnapshot.load()
                guard !Task.isCancelled else { return }
                snapshot = synced
            }
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }
}
