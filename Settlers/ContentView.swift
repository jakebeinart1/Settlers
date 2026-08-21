import SwiftUI
import CatanEngine

/// App root: branches between `MainMenuView`, `GameView`, and `EndGameView`
/// based on `viewModel.state.phase` and whether a game is "in progress" this
/// session (the player tapped New Game or Resume) — tracked by
/// `hasStartedThisSession`, which always starts `false` so the app lands on
/// `MainMenuView` on every cold launch, even when a save exists on disk
/// (`GameViewModel.init()` already loaded it into `viewModel.state`, but the
/// player still has to explicitly tap "Resume Game" to enter it - mirrors a
/// typical mobile game always opening to its title screen, and matters
/// because jumping straight into a resumed game would otherwise run its bot
/// turns before the player ever saw the menu).
struct ContentView: View {
    @State private var viewModel = GameViewModel()
    // `-qaAutoStart`: a launch-argument escape hatch so `simctl launch ...
    // -qaAutoStart` can land directly on the board for visual QA
    // (screenshotting UI chrome, etc.) without a real tap on `MainMenuView`
    // - never set in normal use, so this can't change anything for a real
    // player.
    @State private var hasStartedThisSession = ProcessInfo.processInfo.arguments.contains("-qaAutoStart")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if case .gameOver = viewModel.state.phase, hasStartedThisSession {
                EndGameView(state: viewModel.state, human: viewModel.humanPlayer) {
                    hasStartedThisSession = false
                }
            } else if hasStartedThisSession {
                GameView(viewModel: viewModel, onExitToMenu: { hasStartedThisSession = false })
            } else {
                MainMenuView(
                    onStart: { randomizedBoard, randomizeSeat in
                        viewModel.startNewGame(randomizedBoard: randomizedBoard, randomizeSeat: randomizeSeat)
                        hasStartedThisSession = true
                        // With "Randomize Seat" on, seat 0 (where setup
                        // always starts) may now be a bot rather than the
                        // human - without this, nothing would ever kick off
                        // its first move. Harmless when the human *is* seat
                        // 0: `runBotTurnIfNeeded` is a fast no-op whenever
                        // it's already the human's turn.
                        Task { await viewModel.runBotTurnIfNeeded() }
                    },
                    onResume: {
                        hasStartedThisSession = true
                        // Resuming into a save left mid-bot-turn needs the bot
                        // loop kicked off explicitly - `GameViewModel.apply(_:)`
                        // only spawns it after a *human* move, and a resumed
                        // save never had one. A fresh game from "New Game"
                        // always starts on the human's own setup turn, so it
                        // doesn't need this.
                        Task { await viewModel.runBotTurnIfNeeded() }
                    }
                )
            }
        }
        // Drives `GameViewModel`'s active-time tracking for the "average
        // game time" stat - only foreground time should count, not time
        // spent backgrounded/locked while a game sits mid-turn.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active: viewModel.appDidBecomeActive()
            case .inactive, .background: viewModel.appWillResignActive()
            @unknown default: viewModel.appWillResignActive()
            }
        }
    }
}

#Preview {
    ContentView()
}
