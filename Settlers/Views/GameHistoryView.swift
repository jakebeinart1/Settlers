import SwiftUI
import CatanEngine

/// The archive of finished games, reached from the main menu directly above
/// the statistics row those games produced.
///
/// It replaced `GameLogListView`, a flat dark list that opened a
/// `GameLogDetailView` printing `String(describing:)` for every archived move.
/// Both were built as diagnostics - somewhere to find a file to send - and
/// they looked it: system chrome on `Color(white: 0.08)`, in an app where
/// every other screen is painted. This is the same data on the same painted
/// ground as the menu it is opened from, and a row now opens the board
/// (`GameReplayView`) rather than a transcript.
///
/// Unreadable recordings are still reported rather than skipped: a log that
/// silently vanishes from this list is a log nobody can diagnose.
struct GameHistoryView: View {
    let onDismiss: () -> Void
    var store = GameLogStore.shared

    @State private var summaries: [GameLogSummary] = []
    @State private var failures: [GameLogScan.Failure] = []
    @State private var replaying: GameLogSummary?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            paintedBackground
            VStack(spacing: 14) {
                header
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.gameHistory)
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .task { await load() }
        .fullScreenCover(item: $replaying) { summary in
            GameReplayView(summary: summary, store: store)
        }
    }

    private var paintedBackground: some View {
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

    private var header: some View {
        ZStack {
            Text("Game History")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack {
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityIdentifier(AccessibilityID.GameHistory.close)
                .accessibilityLabel("Close game history")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            Spacer()
            ContentUnavailableView("Couldn't read your games", systemImage: "exclamationmark.triangle",
                                   description: Text(loadError))
            Spacer()
        } else if summaries.isEmpty && failures.isEmpty {
            Spacer()
            ContentUnavailableView("No games yet", systemImage: "hourglass",
                                   description: Text("Finished games are recorded here, and you can replay any of them move by move."))
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(failures) { failure in
                        Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, design: .serif))
                            .foregroundStyle(SettingsChrome.ornamentGold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(PaintedChromeBackground(
                                fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.6))
                    }
                    ForEach(summaries) { summary in
                        Button { replaying = summary } label: { row(summary) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier(AccessibilityID.GameHistory.game(summary.gameID))
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    /// Winner's crest, the date, and the shape of the match. Deliberately not
    /// the file name or the move count alone - the row has to be recognisable
    /// as *a game you played*, which is a result and a day, not a document.
    private func row(_ summary: GameLogSummary) -> some View {
        HStack(spacing: 12) {
            crest(for: summary)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline(summary))
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .lineLimit(1)
                // Two lines, not one: "date at time · 4 seats · 10 VP · 12m"
                // on a single line truncated the duration away on a 6.1"
                // screen, and the duration is the half a player recognises a
                // game by.
                Text(summary.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Text(shape(summary))
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SettingsChrome.ornamentGold.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PaintedChromeBackground(fill: .color(Color(white: 0.16)), cornerRadius: 10))
    }

    @ViewBuilder
    private func crest(for summary: GameLogSummary) -> some View {
        if let winner = summary.winner,
           let name = summary.civilizations[winner.index],
           let civilization = Civilization.allCases.first(where: { $0.displayName == name }) {
            CivilizationCrest(civilization: civilization, size: 34)
        } else {
            Image(systemName: summary.isComplete ? "flag.checkered" : "hourglass")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 34, height: 34)
        }
    }

    private func headline(_ summary: GameLogSummary) -> String {
        guard let winner = summary.winner else { return "Unfinished game" }
        // The archived name, never "You": a hot-seat game has more than one
        // human at the table, and this is the same mistake the engine's own
        // seat labelling made before it was numbered (see `GameEvent`).
        return (summary.playerNames[winner.index] ?? "Player \(winner.index + 1)") + " won"
    }

    private func shape(_ summary: GameLogSummary) -> String {
        "\(summary.playerCount) seats · \(summary.victoryPointTarget) VP · "
            + "\(duration(summary.duration)) · \(summary.moveCount) moves"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds.rounded()) / 60
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// Scanning decodes every archived game - up to `maxKeptLogs` of them,
    /// each one a full `GameState` plus its move list - so it happens off the
    /// main actor. On the main actor it freezes the screen it is filling in,
    /// for longer the more the player has played.
    private func load() async {
        let store = store
        let scan = await Task.detached(priority: .userInitiated) {
            Result { try store.scan() }
        }.value
        switch scan {
        case .success(let scan):
            summaries = scan.summaries
            failures = scan.failures
            #if DEBUG
            if QALaunchFlag.showReplay.isSet { replaying = summaries.first }
            #endif
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }
}
