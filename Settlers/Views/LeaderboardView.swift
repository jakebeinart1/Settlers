import CatanAI
import SwiftUI

/// Everyone on the ladder: players, every ghost on the phone, and both AI
/// tiers (Jake, 2026-09-25). Tapping a player or a ghost opens its page.
struct LeaderboardView: View {
    let onDismiss: () -> Void
    var ratingStore = RatingStore.shared
    var ghostStore = GhostStore.shared
    var statsStore = SeatStatsStore.shared

    @State private var rows: [LeaderboardRow] = []
    @State private var selected: EntityDetail?

    var body: some View {
        ZStack {
            PaintedScreenBackground()
            VStack(spacing: 14) {
                header
                if let selected {
                    RatedEntityDetailView(detail: selected, onBack: { self.selected = nil })
                } else {
                    list
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.leaderboard)
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .task {
            #if DEBUG
            if QALaunchFlag.seedLeaderboard.isSet { Self.seedForQA(ratings: ratingStore, stats: statsStore) }
            #endif
            rows = LeaderboardModel.rows(ratings: ratingStore.load(), ghosts: ghostStore.all())
        }
    }

    private var header: some View {
        ZStack {
            Text("Leaderboard")
                .font(.system(size: 26, weight: .bold, design: .serif))
            HStack {
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityIdentifier(AccessibilityID.Leaderboard.close)
                .accessibilityLabel("Close leaderboard")
            }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { rank, row in
                    rowView(row, rank: rank + 1)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func rowView(_ row: LeaderboardRow, rank: Int) -> some View {
        Button { open(row) } label: {
            HStack(spacing: 10) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .lineLimit(1)
                    Text(subtitle(row))
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Text(verbatim: String(Int(row.elo.rounded())))
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(SettingsChrome.ornamentGold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.5))
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that dims the row, and Expert read as unavailable.
        .allowsHitTesting(row.kind != .ai)
        .accessibilityIdentifier(AccessibilityID.Leaderboard.row(row.key))
    }

    private func subtitle(_ row: LeaderboardRow) -> String {
        if row.isFixed { return "AI · fixed reference" }
        let games = row.games == 0 ? "unrated" : "\(row.games) rated game\(row.games == 1 ? "" : "s")"
        return "\(row.kind.rawValue) · \(games)"
    }

    private func open(_ row: LeaderboardRow) {
        let ratings = ratingStore.load()
        let stats = statsStore.all()
        switch row.kind {
        case .ghost:
            let id = String(row.key.dropFirst("ghost:".count))
            guard let ghost = ghostStore.ghost(id: id) else { return }
            selected = EntityDetail.ghost(ghost, ratings: ratings, stats: stats)
        case .player:
            selected = EntityDetail.person(row.name, ratings: ratings, stats: stats)
        case .ai:
            return
        }
    }
}

#if DEBUG
extension LeaderboardView {
    /// `-qaSeedLeaderboard`: three rated games, Jake against his ghost and two
    /// Classic seats, the ghost winning two. Idempotent by fixed match ids.
    static func seedForQA(ratings: RatingStore, stats: SeatStatsStore) {
        let seats: [RatedEntity] = [.person("Jake"), .ghost("jake"), .classic, .classic]
        for game in 0..<3 {
            let match = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(game + 1)")!
            let winner = game == 1 ? 0 : 1
            try? ratings.record(match: match, seats: seats, winner: winner)
            let entries = seats.enumerated().map { index, entity -> SeatStatsRecord.Entry in
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
            try? stats.record(SeatStatsRecord(match: match, date: Date(timeIntervalSince1970: Double(game)), seats: entries))
        }
    }
}
#endif

/// The painted board scene behind a scrim: the chrome `GameHistoryView` uses.
struct PaintedScreenBackground: View {
    var body: some View {
        ZStack {
            GeometryReader { geo in
                Image("board-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            LinearGradient(
                colors: [Color.black.opacity(0.62), Color.black.opacity(0.4), Color.black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}
