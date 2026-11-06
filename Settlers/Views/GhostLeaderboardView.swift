import CatanAI
import SwiftUI

/// The established Classic Standard ladder inside the shared leaderboard hub.
/// Its fixed AI references and ghost radar use only the original rated matches;
/// ordinary-AI mode records must not change that population or those ratings.
struct GhostLeaderboardView: View {
    var ratingStore = RatingStore.shared
    var ghostStore = GhostStore.shared
    var statsStore = SeatStatsStore.shared
    var players = PlayerDirectory.shared
    var refreshToken = 0
    /// The hub owns navigation identity so a temporary AI-record destination
    /// cannot discard the legacy detail the player expects Back to restore.
    @Binding var selectedRowKey: String?
    let onPersonRatings: (String) -> Void

    private struct DetailSelection {
        let detail: EntityDetail
        let personID: String?
    }

    @State private var rows: [LeaderboardRow] = []
    @State private var selected: DetailSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected {
                RatedEntityDetailView(detail: selected.detail, onBack: clearSelection,
                                      onAIRatings: personalRatingAction)
            } else {
                scopeDescription
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .task(id: refreshToken) {
            #if DEBUG
            if QALaunchFlag.seedLeaderboard.isSet {
                Self.seedForQA(ratings: ratingStore, stats: statsStore, players: players)
            }
            #endif
            reload()
        }
        .onChange(of: selectedRowKey) { _, _ in restoreSelection() }
    }

    private var scopeDescription: some View {
        Text("Classic Standard · includes ghost games")
            .font(.system(.caption, design: .serif))
            .foregroundStyle(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("leaderboard.ghost-scope")
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { rank, row in
                    rowView(row, rank: rank + 1)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func rowView(_ row: LeaderboardRow, rank: Int) -> some View {
        Button { open(row) } label: {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .frame(width: 26)
                rowLabels(row)
                Spacer(minLength: 8)
                Text(verbatim: String(Int(row.elo.rounded())))
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(SettingsChrome.ornamentGold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill),
                                                cornerRadius: 10, notchScale: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityID.Leaderboard.row(row.key))
    }

    private func rowLabels(_ row: LeaderboardRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.name)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .lineLimit(1)
            Text(subtitle(row))
                .font(.system(size: 11, design: .serif))
                .foregroundStyle(.white.opacity(0.65))
        }
    }

    private func subtitle(_ row: LeaderboardRow) -> String {
        if row.isFixed { return "AI · fixed reference" }
        if row.kind == .player { return "Player · Classic & ghost ladder" }
        let games = row.games == 0 ? "unrated" : "\(row.games) rated game\(row.games == 1 ? "" : "s")"
        return "\(row.kind.rawValue) · \(games)"
    }

    private func reload() {
        let players = players
        rows = LeaderboardModel.rows(ratings: ratingStore.load(), ghosts: ghostStore.all()) { players.name(of: $0) }
        restoreSelection()
    }

    private func restoreSelection() {
        guard let key = selectedRowKey else {
            selected = nil
            return
        }
        if let row = rows.first(where: { $0.key == key }) {
            open(row)
        } else {
            clearSelection()
        }
    }

    private func clearSelection() {
        selected = nil
        selectedRowKey = nil
    }

    private func open(_ row: LeaderboardRow) {
        let ratings = ratingStore.load()
        // The original receipt list remains the authority for legacy radar data.
        let ratedMatches = Set(ratings.ratedMatches)
        let stats = statsStore.all().filter { ratedMatches.contains($0.match) }
        guard let detail = selection(for: row, ratings: ratings, stats: stats) else {
            clearSelection()
            return
        }
        selected = detail
        selectedRowKey = row.key
    }

    private func selection(for row: LeaderboardRow, ratings: Ratings,
                           stats: [SeatStatsRecord]) -> DetailSelection? {
        switch row.kind {
        case .ghost:
            let id = String(row.key.dropFirst("ghost:".count))
            // A ghost may have been retired since the row was rendered.
            guard let ghost = ghostStore.ghost(id: id) else { return nil }
            return DetailSelection(
                detail: .ghost(ghost, ratings: ratings, stats: stats, resolve: ghostStore.resolve), personID: nil)
        case .player:
            let id = String(row.key.dropFirst("person:".count))
            return DetailSelection(
                detail: .person(id, name: row.name, ratings: ratings, stats: stats), personID: id)
        case .ai:
            guard let tier = RatedEntity(key: row.key) else { return nil }
            return DetailSelection(
                detail: .ai(tier, name: row.name, elo: row.elo, stats: stats), personID: nil)
        }
    }

    private var personalRatingAction: (() -> Void)? {
        guard let personID = selected?.personID else { return nil }
        return { onPersonRatings(personID) }
    }
}

#if DEBUG
extension GhostLeaderboardView {
    /// Three fixed Classic/ghost games retain the existing legacy UI fixture.
    /// Repeated mounts are idempotent by match id; failed setup must fail the
    /// fixture instead of presenting stale records as a successful seed.
    static func seedForQA(ratings: RatingStore, stats: SeatStatsStore, players: PlayerDirectory) {
        do {
            var contents = players.load()
            contents.names["jake"] = "Jake"
            try players.save(contents)
            let seats: [RatedEntity] = [.person("jake"), .ghost("jake"), .classic, .classic]
            for game in 0..<3 {
                guard let match = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(game + 1)") else {
                    preconditionFailure("The fixed leaderboard fixture must contain valid match identifiers")
                }
                let winner = game == 1 ? 0 : 1
                try ratings.record(match: match, seats: seats, winner: winner)
                try stats.record(SeatStatsRecord(match: match, date: Date(timeIntervalSince1970: Double(game)),
                                                seats: seedEntries(seats, winner: winner)))
            }
        } catch {
            preconditionFailure("The legacy leaderboard fixture could not be saved: \(error)")
        }
    }

    private static func seedEntries(_ seats: [RatedEntity], winner: Int) -> [SeatStatsRecord.Entry] {
        seats.enumerated().map { index, entity in
            var seat = SeatStats(seat: index, target: 10)
            seat.turns = 22
            seat.productionCards = [80, 74, 66, 61][index]
            seat.settlementsBuilt = [3, 4, 2, 2][index]
            seat.citiesBuilt = [2, 1, 1, 2][index]
            seat.tradesCompleted = [4, 5, 3, 2][index]
            seat.devCardsPlayed = [1, 1, 2, 1][index]
            seat.robberMoves = 2
            seat.robberHitsLeader = [2, 1, 1, 1][index]
            seat.won = index == winner
            seat.finalVP = seat.won ? 10 : [8, 7, 5, 6][index]
            return SeatStatsRecord.Entry(entity: entity.key, stats: seat)
        }
    }
}
#endif
