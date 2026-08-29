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
    @State private var isShowingUnreadableSaveAlert = false
    // `-qaAutoStart`: a launch-argument escape hatch so `simctl launch ...
    // -qaAutoStart` can land directly on the board for visual QA
    // (screenshotting UI chrome, etc.) without a real tap on `MainMenuView`
    // - never set in normal use, so this can't change anything for a real
    // player.
    @State private var hasStartedThisSession = QALaunchFlag.autoStart.isSet
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if case .gameOver = viewModel.state.phase, hasStartedThisSession {
                EndGameView(state: viewModel.state, human: viewModel.humanPlayer) {
                    hasStartedThisSession = false
                }
            } else if hasStartedThisSession {
                GameView(viewModel: viewModel, onExitToMenu: { hasStartedThisSession = false })
                    // Rebuild the whole view on a restart so its `@State` goes
                    // with the old game. `GameView` holds sixteen pieces of
                    // per-game interaction state - armed knight targeting, a
                    // half-finished road-building pair, the incoming-offer
                    // queue, the roll-history ring - and `startNewGame` resets
                    // the model but cannot touch any of it. Restarting while a
                    // Knight was armed dropped you into a brand-new board
                    // already in robber-targeting mode with no action row.
                    .id(viewModel.gameGeneration)
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
        // A save that exists but will not decode is reported, not swallowed.
        // Silently starting a fresh game in that case is how a player loses a
        // game in progress and is told nothing at all - which is exactly what
        // happened in the field when a new field was added to `GameState`.
        .alert("Couldn't open your saved game", isPresented: $isShowingUnreadableSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A save was found but couldn't be read, so a new game is ready instead. "
                 + "The file has been left in place.")
        }
        .onAppear {
            isShowingUnreadableSaveAlert = viewModel.saveWasUnreadable
            // `-qaShowEndGame`: same escape-hatch pattern as `-qaAutoStart`
            // - forces a human win via `qaForceHumanWin()` so `EndGameView`
            // can be screenshotted without actually playing a game out to
            // 10 VP. Combine with `-qaAutoStart` (which this alone doesn't
            // imply) so `hasStartedThisSession` is already `true` and the
            // `gameOver` branch above actually renders.
            // The guard has to be here as well as on the method: `isSet` is
            // false in release, but that is a runtime answer and the call
            // still has to compile, and the method it names does not exist
            // outside DEBUG.
            #if DEBUG
            if QALaunchFlag.showEndGame.isSet {
                viewModel.qaForceHumanWin()
            }
            #endif
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
