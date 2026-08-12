import SwiftUI
import CatanEngine

/// Title screen: flat colonist.io-style branding for "Empires" (the app's
/// display name - the underlying Xcode project/module is still named
/// `Settlers`, a deliberately untouched implementation detail), a
/// randomized-board toggle, "New Game", and (only when a save exists)
/// "Resume Game". `onStart` receives the randomized-board toggle's value
/// when the player taps "New Game"; `ContentView` is responsible for
/// actually calling `GameViewModel.startNewGame(randomizedBoard:)`.
public struct MainMenuView: View {
    public let onStart: (Bool) -> Void
    public let onResume: () -> Void

    public init(onStart: @escaping (Bool) -> Void, onResume: @escaping () -> Void) {
        self.onStart = onStart
        self.onResume = onResume
    }

    @State private var randomizedBoard = false
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
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
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

                    Button {
                        onStart(randomizedBoard)
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

                Spacer()
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onDismiss: { isShowingSettings = false })
        }
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
