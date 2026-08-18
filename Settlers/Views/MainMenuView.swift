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

    @State private var randomizedBoard = false
    // Off by default rather than on: always going first is what prompted
    // this toggle, but changing the *default* experience for existing
    // players without asking felt like a bigger call than adding the
    // option - this stays opt-in until there's a reason to flip it.
    @State private var randomizeSeat = false
    @State private var isShowingSettings = false

    private var hasSavedGame: Bool {
        GameStore.shared.load() != nil
    }

    public var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

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
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: Capsule())
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

                    Button {
                        onStart(randomizedBoard, randomizeSeat)
                    } label: {
                        Text("New Game")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CatanTheme.color(for: Resource.brick))
                    .controlSize(.large)
                    .padding(.horizontal, 40)

                    if hasSavedGame {
                        Button {
                            onResume()
                        } label: {
                            Text("Resume Game")
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                        .controlSize(.large)
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
