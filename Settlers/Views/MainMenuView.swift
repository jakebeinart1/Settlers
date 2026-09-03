import SwiftUI
import CatanEngine

/// Title screen: flat colonist.io-style branding for "Empires" (the app's
/// display name - the underlying Xcode project/module is still named
/// `Settlers`, a deliberately untouched implementation detail), "New Game",
/// and (only when a save exists) "Resume Game".
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

    public init(onStart: @escaping (MatchSetup) -> Void, onResume: @escaping () -> Void) {
        self.onStart = onStart
        self.onResume = onResume
    }

    // `-qaShowSettings`: same escape-hatch pattern as `-qaShowPauseMenu` -
    // opens straight to `SettingsView` for screenshotting it, no real tap on
    // the gear icon needed.
    @State private var isShowingSettings = QALaunchFlag.showSettings.isSet
    // The three `-qaShowNewGame*` flags do the same for `NewGameSetupView`,
    // each seeding a different state of it (see `QALaunchFlag`).
    @State private var isShowingNewGame = QALaunchFlag.showNewGame.isSet
        || QALaunchFlag.showNewGameInvalid.isSet
        || QALaunchFlag.showNewGameOverwrite.isSet
        || QALaunchFlag.showNewGameCivilizationPicker.isSet

    private var hasSavedGame: Bool {
        GameStore.shared.hasSave()
    }

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

            VStack {
                HStack {
                    Spacer()
                    // A labeled pill rather than a bare icon - a lone
                    // gearshape glyph in a dark corner was easy to miss
                    // entirely as the one place to pick your civilization
                    // before starting a game.
                    Button {
                        isShowingSettings = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                            Text("Settings")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(PaintedChromeBackground(fill: .color(Color(white: 0.18)), cornerRadius: 10, notchScale: 0.6))
                    }
                    .accessibilityIdentifier(AccessibilityID.MainMenu.settings)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                Spacer(minLength: 0)
            }

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

                    if hasSavedGame {
                        GoldRowButton(title: "Resume Game", systemImage: "play.fill") {
                            onResume()
                        }
                        .accessibilityIdentifier(AccessibilityID.MainMenu.resume)
                        .padding(.horizontal, 40)
                    }
                }

                statsRow

                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.mainMenu)
        .foregroundStyle(.white)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onDismiss: { isShowingSettings = false })
        }
        // Full screen rather than a sheet: the setup screen is taller than a
        // phone, carries its own bottom action bar, and a sheet's drag-to-
        // dismiss would sit directly over a scroll view full of text fields.
        .fullScreenCover(isPresented: $isShowingNewGame) {
            NewGameSetupView(
                onStart: { setup in
                    // Dismissed first: `onStart` replaces this whole view with
                    // the board, and tearing down a presenter while its cover
                    // is still up leaves the cover orphaned on screen.
                    isShowingNewGame = false
                    onStart(setup)
                },
                onCancel: { isShowingNewGame = false }
            )
        }
    }

    /// A compact row of running personal stats (win rate, average game
    /// length, average final VP) below the New Game/Resume buttons -
    /// hidden entirely before a first game has finished, since there's
    /// nothing meaningful to show yet.
    @ViewBuilder
    private var statsRow: some View {
        let stats = GameStatsStore.shared.load()
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
    MainMenuView(onStart: { _ in }, onResume: {})
}
