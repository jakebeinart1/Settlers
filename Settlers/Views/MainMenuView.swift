import SwiftUI
import CatanEngine

/// Title screen: flat colonist.io-style branding for "Settlers", a
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

    private var hasSavedGame: Bool {
        GameStore.shared.load() != nil
    }

    public var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

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

            Text("SETTLERS")
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .tracking(4)

            Text("A Catan-style game")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

#Preview {
    MainMenuView(onStart: { _ in }, onResume: {})
}
