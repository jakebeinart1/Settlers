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
    let viewModel: GameViewModel
    @State private var isShowingUnreadableSaveAlert = false
    @State private var isShowingPersistenceError = false
    @State private var isShowingGameLogWarning = false
    // `-qaAutoStart`: a launch-argument escape hatch so `simctl launch ...
    // -qaAutoStart` can land directly on the board for visual QA
    // (screenshotting UI chrome, etc.) without a real tap on `MainMenuView`
    // - never set in normal use, so this can't change anything for a real
    // player.
    //
    // Starts `false`, set `true` inside `.onAppear` below - NOT seeded
    // directly from the flag here. Both real entry points (`startNewGame(_:)`
    // below, `onResume`) call `viewModel.startNewGame`/set state fully
    // *before* setting this true, so `GameView` only ever mounts once
    // `gameGeneration` has already reached its final value for the game
    // being shown. Seeding this true up front skipped that ordering:
    // `GameView` mounted immediately (against whatever `state` happened to
    // be, mid-turn or default), and the *later* `startNewGame` call inside
    // `.onAppear` bumped `gameGeneration` out from under it, tearing down
    // and remounting `GameView` - cancelling its `.task` (and any bot-loop
    // work in flight) mid-run, repeatedly, since a torn-down `.task`
    // orphans whatever `await` chain it was in. Measured: a fresh
    // `-qaAutoStart -qaFastForwardToRollDice` launch got permanently stuck
    // after the first round of setup placements, every time.
    @State private var hasStartedThisSession = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if case .gameOver = viewModel.state.phase, hasStartedThisSession,
               viewModel.pendingDevCardReveal == nil,
               viewModel.pendingDevCardResolution == nil,
               viewModel.savedGameAvailability.recoveryMessage == nil {
                EndGameView(state: viewModel.state, humanSeats: viewModel.humanSeats,
                            playerIdentity: viewModel.playerIdentity,
                            replayGameID: viewModel.currentGameLogID) {
                    if viewModel.clearCompletedMatch() { hasStartedThisSession = false }
                }
            } else if hasStartedThisSession, viewModel.savedGameAvailability.recoveryMessage == nil {
                GameView(viewModel: viewModel, onExitToMenu: { hasStartedThisSession = false })
                #if DEBUG
                    .task {
                        if QALaunchFlag.playToEnd.isSet {
                            viewModel.qaPlayToEnd()
                            return
                        }
                        // `-qaTwoHumans`: turns the loaded game into a hot-seat
                        // one so the handoff cover is deterministic for visual
                        // QA and native interaction tests.
                        guard QALaunchFlag.twoHumans.isSet else { return }
                        // The card-reveal fixture creates and persists its own
                        // two-human roster before buying the card, then drops
                        // the device claim. Replacing that match here would
                        // correctly clear the private receipt we are testing.
                        guard !QALaunchFlag.showDevCardReveal.isSet else { return }
                        viewModel.qaMakeHotSeat()
                    }
                #endif
                    // Rebuild the whole view on restart so presentation-only
                    // state such as open popups, the incoming-offer queue, and
                    // roll history cannot cross games. Spatial proposals now
                    // live in the model's shared coordinator and are cleared
                    // by `startNewGame`; this identity still resets the rest.
                    .id(viewModel.gameGeneration)
            } else {
                MainMenuView(
                    canResumeSavedGame: viewModel.savedGameAvailability.canResume,
                    onStart: startNewGame,
                    onResume: {
                        guard viewModel.savedGameAvailability.canResume else { return }
                        hasStartedThisSession = true
                        // Resuming into a save left mid-bot-turn needs the bot
                        // loop kicked off explicitly - `GameViewModel.apply(_:)`
                        // only spawns it after a *human* move, and a resumed
                        // save never had one. A fresh game from "New Game"
                        // always starts on the human's own setup turn, so it
                        // doesn't need this.
                        Task { await viewModel.runBotTurnIfNeeded() }
                    },
                    statistics: viewModel.statistics,
                    requiresSaveReplacementConfirmation: viewModel.requiresSaveReplacementConfirmation,
                    newGameSetupLoadResult: viewModel.newGameSetupLoadResult
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
            Text(viewModel.savedGameAvailability.recoveryMessage
                 ?? "Your saved game cannot be resumed. The original files have been left in place.")
        }
        .alert("Couldn't save the game", isPresented: $isShowingPersistenceError) {
            Button("Reload saved game") {
                if viewModel.retryPersistence(), hasStartedThisSession {
                    Task { await viewModel.runBotTurnIfNeeded() }
                }
            }
            Button("OK", role: .cancel) { viewModel.dismissPersistenceError() }
        } message: {
            Text(viewModel.persistenceErrorMessage ?? "The game could not be saved.")
        }
        .onChange(of: viewModel.persistenceErrorMessage) { _, message in
            isShowingPersistenceError = message != nil
        }
        .alert("Game recording is unavailable", isPresented: $isShowingGameLogWarning) {
            Button("OK", role: .cancel) { viewModel.dismissGameLogWarning() }
        } message: {
            Text((viewModel.gameLogWarning ?? "The game log could not be updated.")
                + " Gameplay can continue, but this session's diagnostic record may be incomplete.")
        }
        .onChange(of: viewModel.gameLogWarning) { _, message in
            isShowingGameLogWarning = message != nil
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
            if QALaunchFlag.autoStart.isSet {
                if viewModel.savedGameAvailability == .absent {
                    let conquest = QALaunchFlag.conquestMode.isSet
                    if QALaunchFlag.vastMode.isSet {
                        viewModel.qaStartVastGame(variant: conquest ? .conquest : .standard)
                    } else if conquest {
                        viewModel.qaStartClassicConquestGame()
                    } else {
                        viewModel.startNewGame(randomizedBoard: false, randomizeSeat: false)
                    }
                }
                // Set only now that `savedGameAvailability`/`gameGeneration`
                // have already reached whatever they're going to be for this
                // launch - matching the real "New Game"/"Resume" entry
                // points below, which both do the same thing (start the
                // game, then reveal it) rather than the other way around.
                hasStartedThisSession = true
            }
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
            case .active:
                viewModel.appDidBecomeActive()
                if hasStartedThisSession { Task { await viewModel.runBotTurnIfNeeded() } }
            case .inactive, .background: viewModel.appWillResignActive()
            @unknown default: viewModel.appWillResignActive()
            }
        }
    }

    /// Starts the match `NewGameSetupView` handed back.
    ///
    /// The setup screen never touches the game or the stores itself (A6.5 -
    /// leaving it without starting must change nothing), so committing the
    /// contract happens here: `startNewGame(setup:)` writes it to
    /// `MatchSetupStore` as the prefill for next time (A6.4) and to
    /// `GameStore` as the game itself.
    private func startNewGame(_ setup: MatchSetup) {
        viewModel.startNewGame(setup: setup)
        guard viewModel.persistenceErrorMessage == nil else { return }
        rememberPreferredIdentity(from: setup)
        hasStartedThisSession = true
        // With seat order randomized, seat 0 (where setup always starts) may
        // be a bot rather than the human - without this, nothing would ever
        // kick off its first move. Harmless when the human *is* seat 0:
        // `runBotTurnIfNeeded` is a fast no-op whenever it's already the
        // human's turn.
        Task { await viewModel.runBotTurnIfNeeded() }
    }

    /// Keeps the name and civilization the player chose on New Game as the
    /// prefill for the next one, so both are set once rather than once a game.
    ///
    /// It has to happen here, at the same commit point as the rest of the
    /// contract, and it has to be a write to these two preference stores
    /// specifically. The setup screen deliberately touches no store (A6.5:
    /// leaving without starting must change nothing), and the previous setup
    /// *was* already saved in `MatchSetupStore` - but
    /// `NewGameSetupView.applyAppPreferences` overwrites that saved setup's
    /// human name and civilization with these preferences every time the
    /// screen opens, so a choice made there survived exactly until the next
    /// visit and no further. Writing the preferences is what makes the prefill
    /// agree with what the player last did.
    ///
    /// App Settings used to be the only writer of both, which is why this was
    /// not noticed sooner and why it became load-bearing the moment that
    /// screen was deleted: without this, every new game would open on
    /// `CivilizationSettings.default`'s Medieval no matter what was played
    /// last.
    ///
    /// The first human seat only: this is one player's own name and
    /// civilization, not the hot-seat roster, which a running match snapshots
    /// for itself. A seat left on Random is not recorded - the player did not
    /// choose a civilization, so there is nothing to remember.
    private func rememberPreferredIdentity(from setup: MatchSetup) {
        guard let seat = setup.seats.first(where: \.isHuman) else { return }
        PlayerNameStore.shared.save(seat.name)
        guard let civilization = seat.civilization else { return }
        var settings = CivilizationSettingsStore.shared.load()
        guard settings.yourCivilization != civilization else { return }
        settings.yourCivilization = civilization
        CivilizationSettingsStore.shared.save(settings)
    }
}

#Preview {
    ContentView(viewModel: GameViewModel())
}
