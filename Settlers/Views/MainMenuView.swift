import SwiftUI
import CatanEngine

/// Title screen: flat colonist.io-style branding for "Empires" (the app's
/// display name - the underlying Xcode project/module is still named
/// `Settlers`, a deliberately untouched implementation detail), a
/// randomized-board toggle, a randomize-seat toggle, "New Game", and (only
/// when a save exists) "Resume Game". `onStart` receives both toggles'
/// values when the player taps "New Game"; `ContentView` is responsible for
/// actually calling
/// `GameViewModel.startNewGame(randomizedBoard:randomizeSeat:)`.
public struct MainMenuView: View {
    public let onStart: (Bool, Bool) -> Void
    public let onResume: () -> Void

    public init(onStart: @escaping (Bool, Bool) -> Void, onResume: @escaping () -> Void) {
        self.onStart = onStart
        self.onResume = onResume
    }

    // `@AppStorage` rather than plain `@State` - Jake plays with both on
    // every game and doesn't want to re-toggle them each launch, so the
    // choice persists (UserDefaults) instead of resetting every time
    // `MainMenuView` appears. Defaulting both to `true` (a change from the
    // toggles' original off-by-default) is exactly that persisted choice
    // for a first launch too, per Jake's ask.
    @AppStorage("randomizedBoardSetting") private var randomizedBoard = true
    @AppStorage("randomizeSeatSetting") private var randomizeSeat = true
    // `-qaShowSettings`: same escape-hatch pattern as `-qaShowPauseMenu` -
    // opens straight to `SettingsView` for screenshotting it, no real tap on
    // the gear icon needed.
    @State private var isShowingSettings = QALaunchFlag.showSettings.isSet

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
                    Toggle(isOn: $randomizedBoard) {
                        Text("Randomized Board")
                            .foregroundStyle(.white)
                    }
                    .tint(CatanTheme.color(for: Resource.wool))
                    .padding(.horizontal, 40)

                    Toggle(isOn: $randomizeSeat) {
                        Text("Randomize Seat")
                            .foregroundStyle(.white)
                    }
                    .tint(CatanTheme.color(for: Resource.wool))
                    .padding(.horizontal, 40)

                    GoldRowButton(
                        title: "New Game",
                        systemImage: "plus.circle.fill",
                        iconColor: CatanTheme.color(for: Resource.brick)
                    ) {
                        onStart(randomizedBoard, randomizeSeat)
                    }
                    .padding(.horizontal, 40)

                    if hasSavedGame {
                        GoldRowButton(title: "Resume Game", systemImage: "play.fill") {
                            onResume()
                        }
                        .padding(.horizontal, 40)
                    }
                }

                statsRow

                Spacer()
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onDismiss: { isShowingSettings = false })
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
    MainMenuView(onStart: { _, _ in }, onResume: {})
}
