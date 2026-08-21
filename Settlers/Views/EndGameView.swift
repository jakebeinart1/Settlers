import SwiftUI
import CatanEngine

/// Shown once `state.phase` is `.gameOver(winner:)`. Human win gets
/// celebratory framing; a bot win is reported plainly as "Player N wins".
/// Either way, a final VP table (including longest-road/largest-army
/// bonuses, via `GameState.victoryPoints(for:)`) lists all 4 players.
/// "New Game" clears the on-disk save and hands control back to
/// `ContentView` via `onNewGame`.
public struct EndGameView: View {
    public let state: GameState
    public let human: PlayerID
    public let onNewGame: () -> Void

    public init(state: GameState, human: PlayerID, onNewGame: @escaping () -> Void) {
        self.state = state
        self.human = human
        self.onNewGame = onNewGame
    }

    private var winner: PlayerID? {
        if case .gameOver(let winner) = state.phase { return winner }
        return nil
    }

    public var body: some View {
        ZStack {
            Color(white: 0.08).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                headline

                vpTable

                Button {
                    GameStore.shared.clear()
                    CivilizationAssignmentStore.shared.clear()
                    onNewGame()
                } label: {
                    Text("New Game")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(CatanTheme.color(for: Resource.brick))
                .controlSize(.large)
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
            VStack(spacing: 8) {
                if winner == human {
                    Text("🎉")
                        .font(.system(size: 64))
                    Text("You Win!")
                        .font(.system(size: 40, weight: .heavy, design: .serif))
                        .foregroundStyle(CatanTheme.color(for: Resource.grain))
                } else {
                    Text("Game Over")
                        .font(.title2.bold())
                        .foregroundStyle(.white.opacity(0.7))
                    Text(CatanTheme.playerLabel(for: winner) + " wins")
                        .font(.system(size: 36, weight: .heavy, design: .serif))
                        .foregroundStyle(CatanTheme.color(for: winner))
                }
            }
        } else {
            Text("Game Over")
                .font(.system(size: 36, weight: .heavy, design: .serif))
        }
    }

    private var vpTable: some View {
        VStack(spacing: 8) {
            ForEach(state.players, id: \.id) { player in
                HStack {
                    Circle()
                        .fill(CatanTheme.color(for: player.id))
                        .frame(width: 12, height: 12)
                    Text(CatanTheme.playerLabel(for: player.id))
                        .fontWeight(player.id == winner ? .bold : .regular)
                    Spacer()
                    Text("\(state.victoryPoints(for: player.id)) VP")
                        .fontWeight(player.id == winner ? .bold : .regular)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.14))
        )
        .padding(.horizontal, 40)
    }
}

#Preview {
    EndGameView(
        state: GameSetup.newGame(board: BoardGenerator.standard()),
        human: PlayerID(index: 0),
        onNewGame: {}
    )
}
