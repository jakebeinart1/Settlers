import SwiftUI
import CatanEngine

/// App root: branches between `MainMenuView`, `GameView`, and `EndGameView`
/// based on `viewModel.state.phase` and whether a game is "in progress"
/// (a save exists on disk, or the player tapped New Game/Resume this
/// session — tracked by `hasStartedThisSession` since `GameViewModel.init()`
/// always holds *some* `GameState`, even a fresh unstarted one, so `state`
/// alone can't distinguish "never played" from "played and about to
/// resume").
struct ContentView: View {
    @State private var viewModel = GameViewModel()
    @State private var hasStartedThisSession = GameStore.shared.load() != nil

    var body: some View {
        Group {
            if case .gameOver = viewModel.state.phase, hasStartedThisSession {
                EndGameView(state: viewModel.state) {
                    hasStartedThisSession = false
                }
            } else if hasStartedThisSession {
                GameView(viewModel: viewModel)
            } else {
                MainMenuView(
                    onStart: { randomizedBoard in
                        viewModel.startNewGame(randomizedBoard: randomizedBoard)
                        hasStartedThisSession = true
                    },
                    onResume: {
                        hasStartedThisSession = true
                    }
                )
            }
        }
        .task {
            // Resuming into a save left mid-bot-turn needs the bot loop
            // kicked off explicitly - `GameViewModel.apply(_:)` only spawns
            // it after a *human* move, and a cold launch resuming into a
            // bot's turn never had one.
            await viewModel.runBotTurnIfNeeded()
        }
    }
}

#Preview {
    ContentView()
}
