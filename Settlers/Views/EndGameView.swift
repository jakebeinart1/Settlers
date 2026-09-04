import SwiftUI
import CatanEngine

/// Shown once `state.phase` is `.gameOver(winner:)`. Human win gets
/// celebratory framing; every other result names the configured winner.
/// Either way, a final VP table (including longest-road/largest-army
/// bonuses, via `GameState.victoryPoints(for:)`) lists every occupied seat.
/// "New Game" clears the on-disk save and hands control back to
/// `ContentView` via `onNewGame`.
public struct EndGameView: View {
    public let state: GameState
    public let humanSeats: Set<PlayerID>
    public let playerIdentity: (PlayerID) -> PlayerIdentity
    public let onNewGame: () -> Void

    public init(state: GameState, humanSeats: Set<PlayerID>,
                playerIdentity: @escaping (PlayerID) -> PlayerIdentity = CatanTheme.playerIdentity,
                onNewGame: @escaping () -> Void) {
        self.state = state
        precondition(!humanSeats.isEmpty, "An end screen needs at least one human seat")
        self.humanSeats = humanSeats
        self.playerIdentity = playerIdentity
        self.onNewGame = onNewGame
    }

    private var winner: PlayerID? {
        if case .gameOver(let winner) = state.phase { return winner }
        return nil
    }

    public var body: some View {
        ZStack {
            // The same painted world as `MainMenuView`/`GameView`, but a
            // dedicated warm golden-hour grade + a soft glow behind the
            // headline (`win-background`, generated from the same source
            // painting) rather than the menu's cooler blue-water crop - a
            // win screen reusing the exact same backdrop as the title
            // screen would've read as "back at the menu", not a moment of
            // its own.
            GeometryReader { geo in
                Image("win-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.45),
                    Color.black.opacity(0.2),
                    Color.black.opacity(0.6),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                headline

                vpTable

                GoldRowButton(
                    title: "New Game",
                    systemImage: "arrow.counterclockwise",
                    iconColor: CatanTheme.color(for: Resource.brick)
                ) {
                    onNewGame()
                }
                .accessibilityIdentifier(AccessibilityID.GameOver.newGame)
                .padding(.horizontal, 40)

                Spacer()
            }
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
    }

    @ViewBuilder
    private var headline: some View {
        if let winner {
            let identity = playerIdentity(winner)
            VStack(spacing: 8) {
                if humanSeats.count == 1, humanSeats.contains(winner) {
                    Text("🎉")
                        .font(.system(size: 64))
                    // Same serif/black/tracking treatment as the
                    // "EMPIRES" wordmark on `MainMenuView` - a win screen
                    // is the one other moment that deserves that same
                    // weight, not a smaller ad-hoc headline style.
                    Text("YOU WIN!")
                        .font(.system(size: 44, weight: .black, design: .serif))
                        .tracking(3)
                        .foregroundStyle(CatanTheme.color(for: Resource.grain))
                } else {
                    Text("Game Over")
                        .font(.title2.bold())
                        .foregroundStyle(.white.opacity(0.7))
                    Text((identity.displayName + " wins").uppercased())
                        .font(.system(size: 36, weight: .black, design: .serif))
                        .tracking(2)
                        .foregroundStyle(identity.civilization.accentColor)
                }
            }
        } else {
            Text("GAME OVER")
                .font(.system(size: 36, weight: .black, design: .serif))
                .tracking(2)
        }
    }

    private var vpTable: some View {
        VStack(spacing: 8) {
            ForEach(state.players, id: \.id) { player in
                let identity = playerIdentity(player.id)
                HStack(spacing: 9) {
                    CivilizationCrest(civilization: identity.civilization, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(identity.displayName)
                            .fontWeight(player.id == winner ? .bold : .regular)
                        Text(identity.civilization.displayName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Text("\(state.victoryPoints(for: player.id)) VP")
                        .fontWeight(player.id == winner ? .bold : .regular)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(PaintedChromeBackground(fill: .color(Color(white: 0.14)), cornerRadius: 12))
        .padding(.horizontal, 40)
    }
}

#Preview {
    EndGameView(
        state: GameSetup.newGame(board: BoardGenerator.standard()),
        humanSeats: [PlayerID(index: 0)],
        onNewGame: {}
    )
}
