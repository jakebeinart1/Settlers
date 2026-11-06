import SwiftUI

/// One person's selected competition. Standings and the result feed have their
/// own destinations, so neither can push this record beyond the phone's edge.
struct PlayerRatingsView: View {
    let snapshot: PlayerRatingSnapshot
    let playerID: String
    let pool: RatingPool
    let onGames: () -> Void
    let onTrend: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var standing: PlayerRatingStanding { snapshot.ratings.standing(for: playerID, in: pool) }
    private var changes: [PlayerRatingChange] {
        snapshot.ratings.changes.filter { $0.playerID == playerID && $0.pool == pool }
    }

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 12) {
                    record
                    if !changes.isEmpty {
                        if dynamicTypeSize.isAccessibilitySize {
                            GoldRowButton(title: "Rating history", systemImage: "chart.line.uptrend.xyaxis",
                                          iconColor: SettingsChrome.ornamentGold, action: onTrend)
                                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                                .accessibilityIdentifier("ratings.trend")
                        } else { chart }
                    }
                }
                .padding(3)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(RatingViewportMarker(identifier: "ratings.profile-frame"))
            GoldRowButton(title: "Games", subtitle: "\(standing.games) in this competition",
                          systemImage: "clock.arrow.circlepath", iconColor: SettingsChrome.ornamentGold,
                          action: onGames)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityIdentifier("ratings.games")
        }
        .background(RatingViewportMarker(identifier: "ratings.profile"))
    }

    private var record: some View {
        VStack(alignment: .leading, spacing: 16) {
            ratingHeader
            metrics
            if !standing.isRated {
                Text("The first rated game starts at \(Int(Elo.start).formatted()) Elo.")
                    .font(.system(.subheadline, design: .serif)).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ratings.first-game")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 12))
    }

    private var ratingHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ratingValue
                ratingUnit
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: 4) {
                ratingValue
                ratingUnit
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ratingValue: some View {
        Text(standing.isRated ? standing.displayedRating.formatted() : "Unrated")
            .font(.system(standing.isRated ? .largeTitle : .title2, design: .serif, weight: .bold))
            .foregroundStyle(SettingsChrome.ornamentGold)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("ratings.rating")
    }

    private var ratingUnit: some View {
        Text("Elo").font(.system(.subheadline, design: .serif)).foregroundStyle(.white.opacity(0.7))
            .accessibilityIdentifier("ratings.rating-unit")
    }

    private var metrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading),
                                count: dynamicTypeSize.isAccessibilitySize ? 2 : 4),
                  alignment: .leading, spacing: 12) {
            metric("\(standing.wins)", title: "Wins", id: "ratings.wins")
            metric("\(standing.losses)", title: "Losses", id: "ratings.losses")
            metric(standing.games == 0 ? "—" : "\(Int((standing.record.winRate * 100).rounded()))%",
                   title: "Win rate", id: "ratings.win-rate")
            metric("\(standing.games)", title: "Games", id: "ratings.game-count")
        }
    }

    private func metric(_ value: String, title: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.title3, design: .serif, weight: .semibold)).monospacedDigit()
            Text(title).font(.system(.caption, design: .serif)).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    private var chart: some View {
        PlayerRatingChart(changes: changes)
            .padding(14)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 12))
    }
}

/// Only this deliberate, bounded list scrolls; the hub keeps context and Back
/// visible while the player reads older results.
struct PlayerRatingGamesView: View {
    let changes: [PlayerRatingChange]

    var body: some View {
        Group {
            if changes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "flag").font(.system(size: 28)).foregroundStyle(SettingsChrome.ornamentGold)
                    Text("No games in this competition yet.")
                        .font(.system(.body, design: .serif)).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(Array(changes.reversed())) { PlayerRatingResultRow(change: $0) }
                    }
                    .padding(3)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(RatingViewportMarker(identifier: "ratings.history-frame"))
        .background(RatingViewportMarker(identifier: "ratings.history"))
    }
}

/// Test geometry is a sibling leaf. Making the page an accessibility ancestor
/// can absorb its nested controls and hide real navigation failures.
struct RatingViewportMarker: View {
    let identifier: String

    var body: some View {
        #if DEBUG
        Color.clear.accessibilityElement().accessibilityIdentifier(identifier)
            .accessibilityRespondsToUserInteraction(false)
            .allowsHitTesting(false)
        #else
        Color.clear
        #endif
    }
}
