import CatanEngine
import SwiftUI

/// One comparison table for the selected competition. The person rows size to
/// their content when they fit; the table scrolls when the parent offers less
/// space. The shared opponent follows the people inside that same viewport.
/// Data loading, mode selection and navigation belong to the leaderboard host.
struct PlayerRatingStandingsView: View {
    let snapshot: PlayerRatingSnapshot
    let pool: RatingPool
    let onPlayer: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var rankWidth: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var normalRowHeight = Metrics.rowHeight
    @ScaledMetric(relativeTo: .subheadline) private var normalOpponentHeight = Metrics.opponentHeight

    private enum Metrics {
        static let rowHeight: CGFloat = 56
        static let opponentHeight: CGFloat = 60
        static let minimumTargetHeight: CGFloat = 44
        static let frameInset: CGFloat = 4
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let rowSpacing: CGFloat = 10
        static let identitySpacing: CGFloat = 3
        static let expandedSpacing: CGFloat = 6
        static let chevronSize: CGFloat = 12
        static let cornerRadius: CGFloat = 12
    }

    private struct Person: Identifiable {
        let id: String
        let name: String
        let standing: PlayerRatingStanding
        let rank: Int?
        let isMe: Bool
    }

    var body: some View {
        let people = rankedPeople
        boundedTable(people)
        .padding(Metrics.frameInset)
        .frame(maxHeight: normalTableHeight(people: people.count), alignment: .top)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill),
                                            cornerRadius: Metrics.cornerRadius))
        .background(tableFrameMarker)
        .foregroundStyle(.white)
        .fontDesign(.serif)
    }

    /// A parent may offer all remaining space. The ordinary table stops at
    /// its row budget rather than turning that slack into a giant navy panel.
    /// Accessibility rows instead use their natural heights inside the list.
    private func normalTableHeight(people count: Int) -> CGFloat? {
        guard !dynamicTypeSize.isAccessibilitySize else { return nil }
        let rows = max(1, count)
        return CGFloat(rows) * normalRowHeight + CGFloat(rows) + normalOpponentHeight
            + 2 * Metrics.frameInset
    }

    private var rankedPeople: [Person] {
        let ids = snapshot.playerIDs.sorted { first, second in
            let left = snapshot.ratings.standing(for: first, in: pool)
            let right = snapshot.ratings.standing(for: second, in: pool)
            if left.isRated != right.isRated { return left.isRated }
            if left.rating != right.rating { return left.rating > right.rating }
            return (snapshot.name(for: first).lowercased(), first)
                < (snapshot.name(for: second).lowercased(), second)
        }
        return ids.enumerated().map { index, id in
            let standing = snapshot.ratings.standing(for: id, in: pool)
            return Person(id: id, name: snapshot.name(for: id), standing: standing,
                          rank: standing.isRated ? index + 1 : nil, isMe: id == snapshot.me)
        }
    }

    private func boundedTable(_ people: [Person]) -> some View {
        ViewThatFits(in: .vertical) {
            tableRows(people).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                tableRows(people)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.visible)
            .clipped()
        }
    }

    private func tableRows(_ people: [Person]) -> some View {
        VStack(spacing: 0) {
            personRows(people)
            divider
            sharedOpponent.fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func personRows(_ people: [Person]) -> some View {
        if people.isEmpty {
            Text("No player records yet")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
                .padding(Metrics.horizontalPadding)
                .frame(maxWidth: .infinity, minHeight: normalRowHeight, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(people) { person in
                    if person.id != people.first?.id { divider }
                    personRow(person)
                }
            }
        }
    }

    private func personRow(_ person: Person) -> some View {
        Button { onPlayer(person.id) } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize { expandedPerson(person) } else { compactPerson(person) }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: normalRowHeight, alignment: .leading)
            .contentShape(Rectangle())
            .background(person.isMe ? SettingsChrome.ornamentGold.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(personDescription(person))
        .accessibilityHint("Opens this player's rating history and game record")
        .accessibilityIdentifier("ratings.player.\(person.id)")
    }

    private func compactPerson(_ person: Person) -> some View {
        HStack(spacing: Metrics.rowSpacing) {
            rank(person)
            identity(name: displayName(person), detail: compactRecord(person.standing))
                .frame(maxWidth: .infinity, alignment: .leading)
            rating(person.standing, identifier: "ratings.rating.\(person.id)")
            chevron
        }
        .frame(minHeight: Metrics.minimumTargetHeight - 2 * Metrics.verticalPadding)
    }

    private func expandedPerson(_ person: Person) -> some View {
        HStack(alignment: .top, spacing: Metrics.rowSpacing) {
            rank(person)
            VStack(alignment: .leading, spacing: Metrics.expandedSpacing) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.rowSpacing) {
                    // The row's tint and spoken label identify the current
                    // person; repeating "(you)" here needlessly wraps names.
                    name(person.name).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    chevron
                }
                rating(person.standing, identifier: "ratings.rating.\(person.id)")
                Text(compactRecord(person.standing))
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rank(_ person: Person) -> some View {
        Text(person.rank.map(String.init) ?? "—")
            .font(.system(.caption, design: .serif, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: rankWidth, alignment: .center)
            .accessibilityHidden(true)
    }

    private func identity(name title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: Metrics.identitySpacing) {
            name(title).lineLimit(1).truncationMode(.tail)
            Text(detail)
                .font(.system(.caption, design: .serif))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private func name(_ title: String) -> some View {
        Text(title).font(.system(.subheadline, design: .serif, weight: .semibold))
    }

    private func rating(_ standing: PlayerRatingStanding, identifier: String) -> some View {
        Text(standing.isRated ? standing.displayedRating.formatted() : "Unrated")
            .font(.system(.headline, design: .serif, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(SettingsChrome.ornamentGold)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityIdentifier(identifier)
    }

    private var sharedOpponent: some View {
        let standing = snapshot.ratings.aiStanding(in: pool)
        return Group {
            if dynamicTypeSize.isAccessibilitySize { expandedOpponent(standing) } else { compactOpponent(standing) }
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        .padding(.vertical, Metrics.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: normalOpponentHeight, alignment: .leading)
        .background(.white.opacity(0.025))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pool.difficulty.displayName) AI, shared opponent, \(ratingDescription(standing))")
        .accessibilityIdentifier("ratings.ai-standing")
    }

    private func compactOpponent(_ standing: PlayerRatingStanding) -> some View {
        HStack(spacing: Metrics.rowSpacing) {
            opponentMarker
            identity(name: "\(pool.difficulty.displayName) AI", detail: "Shared opponent")
                .frame(maxWidth: .infinity, alignment: .leading)
            rating(standing, identifier: "ratings.ai-rating")
            Color.clear.frame(width: Metrics.chevronSize)
        }
    }

    private func expandedOpponent(_ standing: PlayerRatingStanding) -> some View {
        VStack(alignment: .leading, spacing: Metrics.expandedSpacing) {
            name("\(pool.difficulty.displayName) AI").fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Metrics.expandedSpacing) {
                    Text("Shared").font(.system(.caption2, design: .serif))
                        .foregroundStyle(.white.opacity(0.7)).fixedSize()
                    Spacer(minLength: 0)
                    rating(standing, identifier: "ratings.ai-rating").fixedSize()
                }
                VStack(alignment: .leading, spacing: Metrics.identitySpacing) {
                    rating(standing, identifier: "ratings.ai-rating")
                    Text("Shared opponent").font(.system(.caption2, design: .serif))
                        .foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var opponentMarker: some View {
        Text("AI").font(.system(.caption2, design: .serif, weight: .semibold))
            .foregroundStyle(SettingsChrome.ornamentGold.opacity(0.8))
            .frame(width: rankWidth).accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle().fill(SettingsChrome.ornamentGold.opacity(0.16))
            .frame(height: 1).padding(.horizontal, Metrics.horizontalPadding)
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: Metrics.chevronSize, weight: .semibold))
            .foregroundStyle(SettingsChrome.ornamentGold.opacity(0.8))
            .frame(width: Metrics.chevronSize).accessibilityHidden(true)
    }

    private func displayName(_ person: Person) -> String { person.name + (person.isMe ? " (you)" : "") }

    private func compactRecord(_ standing: PlayerRatingStanding) -> String { "\(standing.wins)W · \(standing.losses)L" }

    private func ratingDescription(_ standing: PlayerRatingStanding) -> String {
        standing.isRated ? "\(standing.displayedRating.formatted()) Elo" : "Unrated"
    }

    private func personDescription(_ person: Person) -> String {
        let place = person.rank.map { "Rank \($0), " } ?? ""
        return place + displayName(person) + ", " + ratingDescription(person.standing) + ", "
            + RatingPresentation.record(wins: person.standing.wins, losses: person.standing.losses)
    }

    /// A Debug sibling leaf measures the actual frame without making the
    /// table an accessibility ancestor that can absorb the row identifiers.
    @ViewBuilder private var tableFrameMarker: some View {
        #if DEBUG
        Color.clear.accessibilityElement()
            .accessibilityIdentifier("leaderboard.table-frame")
            .accessibilityRespondsToUserInteraction(false)
            .allowsHitTesting(false)
        #else
        EmptyView()
        #endif
    }
}
