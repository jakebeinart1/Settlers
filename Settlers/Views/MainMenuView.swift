import SwiftUI
import CatanEngine

/// Title screen: flat colonist.io-style branding for "Empires" (the app's
/// display name - the underlying Xcode project/module is still named
/// `Settlers`, a deliberately untouched implementation detail), "New Game",
/// "Resume Game" (only when a save exists), "Game History" (only when
/// something has been recorded), and the lifetime stats row.
///
/// ## Why there is no Settings button any more
/// There was a gear pill in the top-right opening `SettingsView`, and by
/// 2026-09-08 it had been hollowed out from both ends. Your Name and Your
/// Civilization were prefill preferences for New Game Setup, which is where
/// you now set both directly - and the screen's copies of them were the reason
/// a name or a civilization typed on New Game did not survive to the next one,
/// because opening that screen overwrote the saved setup with the preference.
/// Game Logs became Game History, one tap from here. What was left - a random
/// civilization pool and a stats reset - Jake called irrelevant, so the screen
/// went with them rather than being kept alive as a home for two controls
/// nobody uses. Both preferences are still stored; New Game writes them.
///
/// ## Why "New Game" no longer starts a game
/// It used to start one immediately, from two toggles that lived here:
/// "Randomized Board" and "Randomize Seat". Both are match contract - they
/// change what the board is and who plays when - and the settings spec's rule
/// for where a setting goes puts every such control on New Game Setup, not on
/// menu chrome. They now live on `NewGameSetupView` alongside the rest of the
/// contract (seat composition, names, civilizations, match length), and this
/// button presents that screen. `onStart` receives the finished `MatchSetup`
/// only once the player has pressed Start there.
public struct MainMenuView: View {
    public let onStart: (MatchSetup) -> Void
    public let onResume: () -> Void
    public let canResumeSavedGame: Bool
    public let statistics: GameStats
    public let requiresSaveReplacementConfirmation: Bool
    public let newGameSetupLoadResult: MatchSetupStore.LoadResult

    public init(canResumeSavedGame: Bool, onStart: @escaping (MatchSetup) -> Void,
                onResume: @escaping () -> Void, statistics: GameStats = GameStats(),
                requiresSaveReplacementConfirmation: Bool = false,
                newGameSetupLoadResult: MatchSetupStore.LoadResult = .none) {
        self.canResumeSavedGame = canResumeSavedGame
        self.onStart = onStart
        self.onResume = onResume
        self.statistics = statistics
        self.requiresSaveReplacementConfirmation = requiresSaveReplacementConfirmation
        self.newGameSetupLoadResult = newGameSetupLoadResult
    }

    @State private var isShowingGameHistory = QALaunchFlag.showGameHistory.isSet
        || QALaunchFlag.showReplay.isSet
    @State private var isShowingLeaderboard = false
    /// Whether the archive holds anything worth opening. A directory listing,
    /// not a parse: the count only decides whether to show a button, and
    /// decoding every recording to answer that would make the menu pay for a
    /// screen the player may never open.
    @State private var recordedGameCount = 0
    // The three `-qaShowNewGame*` flags each seed a different state of
    // `NewGameSetupView` (see `QALaunchFlag`).
    @State private var isShowingNewGame = QALaunchFlag.showNewGame.isSet
        || QALaunchFlag.showNewGameInvalid.isSet
        || QALaunchFlag.showNewGameOverwrite.isSet
        || QALaunchFlag.showNewGameCivilizationPicker.isSet

    public var body: some View {
        ZStack {
            // The same painted seaside world behind the game board, shown
            // much less cropped than `GameView`'s own 0.90-zoom top-pinned
            // crop - `scaledToFit` here so the whole calm scene (sky,
            // mountains, islands, the ship) is visible at once rather than a
            // tight close-up, which read as too busy/detailed for a title
            // screen that's mostly just two buttons. A dark top-to-bottom
            // scrim over it keeps the wordmark and buttons legible against
            // the painting's own bright sky and water.
            GeometryReader { geo in
                Image("board-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.55),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                titleBlock

                Spacer()

                VStack(spacing: 16) {
                    GoldRowButton(
                        title: "New Game",
                        systemImage: "plus.circle.fill",
                        iconColor: CatanTheme.color(for: Resource.brick)
                    ) {
                        isShowingNewGame = true
                    }
                    .accessibilityIdentifier(AccessibilityID.MainMenu.newGame)
                    .padding(.horizontal, 40)

                    if canResumeSavedGame {
                        GoldRowButton(title: "Resume Game", systemImage: "play.fill") {
                            onResume()
                        }
                        .accessibilityIdentifier(AccessibilityID.MainMenu.resume)
                        .padding(.horizontal, 40)
                    }
                }

                historyButton

                GoldRowButton(title: "Leaderboard", systemImage: "trophy.fill",
                              iconColor: SettingsChrome.ornamentGold) {
                    isShowingLeaderboard = true
                }
                .accessibilityIdentifier(AccessibilityID.MainMenu.leaderboard)
                .padding(.horizontal, 40)

                statsRow

                Spacer()
            }

            // An in-place overlay rather than `.fullScreenCover`, and with no
            // transition - Jake's ask, 2026-09-03: a modal cover always plays
            // UIKit's slide-up presentation animation, which cannot be turned
            // off from the modifier itself. Layering the screen directly into
            // this ZStack (last, so it's on top) instead swaps straight to it
            // with no animation at all. `NewGameSetupView` already draws its
            // own full-bleed background and ignores the safe area, so it
            // still reads as a full screen rather than a sheet.
            if isShowingNewGame {
                NewGameSetupView(
                    hasSavedGame: requiresSaveReplacementConfirmation,
                    setupLoadResult: newGameSetupLoadResult,
                    onStart: { setup in
                        // Dismissed first: `onStart` replaces this whole view
                        // with the board, and tearing down a presenter while
                        // its cover is still up leaves the cover orphaned on
                        // screen.
                        isShowingNewGame = false
                        onStart(setup)
                    },
                    onCancel: { isShowingNewGame = false }
                )
                .transition(.identity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.mainMenu)
        .foregroundStyle(.white)
        .task { recordedGameCount = (try? GameLogStore.shared.logFiles().count) ?? 0 }
        .fullScreenCover(isPresented: $isShowingGameHistory) {
            GameHistoryView(onDismiss: { isShowingGameHistory = false })
        }
        .fullScreenCover(isPresented: $isShowingLeaderboard) {
            LeaderboardView(onDismiss: { isShowingLeaderboard = false })
        }
    }

    /// The way back into games already played, sitting directly above the
    /// statistics those games produced - the two answer the same question at
    /// different resolutions ("how am I doing" and "what happened in that
    /// one"), so they belong next to each other rather than the archive being
    /// buried three taps deep in App Settings, which is where it used to live.
    ///
    /// Hidden until something has been recorded, for the same reason Resume
    /// is: a menu button that can only lead to an empty screen is a button
    /// that teaches the player not to trust the menu.
    @ViewBuilder
    private var historyButton: some View {
        if recordedGameCount > 0 {
            GoldRowButton(title: "Game History", systemImage: "clock.arrow.circlepath",
                          iconColor: SettingsChrome.ornamentGold) {
                isShowingGameHistory = true
            }
            .accessibilityIdentifier(AccessibilityID.MainMenu.gameHistory)
            .padding(.horizontal, 40)
        }
    }

    /// A compact row of running personal stats (win rate, average game
    /// length, average final VP) below the New Game/Resume buttons -
    /// hidden entirely before a first game has finished, since there's
    /// nothing meaningful to show yet.
    @ViewBuilder
    private var statsRow: some View {
        let stats = statistics
        if stats.gamesPlayed > 0 {
            HStack(spacing: 20) {
                statTile(value: "\(stats.gamesPlayed)", label: "Played")
                statTile(value: "\(Int((stats.winRate * 100).rounded()))%", label: "Win Rate")
                statTile(value: formattedDuration(stats.averageDurationSeconds), label: "Avg Time")
                statTile(value: String(format: "%.1f", stats.averageFinalVP), label: "Avg VP")
            }
            .padding(.horizontal, 40)
        }
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(Array(Resource.allCases.enumerated()), id: \.offset) { _, resource in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(CatanTheme.color(for: resource))
                        .frame(width: 18, height: 18)
                }
            }

            // Serif display face for the wordmark - a deliberate swap from
            // the previous rounded/heavy treatment (which read more like a
            // mobile-casual app) toward something with the engraved,
            // empire-building weight the four civilizations call for.
            Text("EMPIRES")
                .font(.system(size: 50, weight: .black, design: .serif))
                .tracking(6)

            Text("Choose your empire. Conquer the board.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

#Preview {
    MainMenuView(canResumeSavedGame: false, onStart: { _ in }, onResume: {})
}
