import SwiftUI
import CatanEngine

/// Throwaway exploratory wiring to manually confirm `GameViewModel` drives
/// the human/bot turn loop end-to-end (setup placements -> bot turns).
/// Replaced by the real UI in Task 15.
struct ContentView: View {
    @State private var viewModel = GameViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("Settlers")
                .font(.largeTitle.bold())

            Text("Phase: \(String(describing: viewModel.state.phase))")
                .font(.footnote)
                .multilineTextAlignment(.center)

            if viewModel.isBotThinking {
                Text("Bot thinking…")
            }

            Button("New Game") {
                viewModel.startNewGame(randomizedBoard: true)
                print("New game started, phase: \(viewModel.state.phase)")
            }

            Button("Place Human Setup Move") {
                let legal = RulesEngine.legalMoves(for: viewModel.state)
                guard let move = legal.first else {
                    print("No legal moves for human")
                    return
                }
                do {
                    try viewModel.apply(move)
                    print("Applied \(move), phase now: \(viewModel.state.phase)")
                } catch {
                    print("Failed to apply move: \(error)")
                }
                // apply(_:) already spawns its own Task to drive bot turns -
                // calling runBotTurnIfNeeded() again here would race a second
                // driver against it across the same `state`.
            }

            // Verification-only: plays the human's *first* legal move on
            // every human turn (no strategy) so the whole human/bot loop can
            // be watched end-to-end in the console without manual taps.
            Button("Auto-Play (verification)") {
                runAutoPlay()
            }
        }
        .padding()
    }

    private func runAutoPlay() {
        viewModel.startNewGame(randomizedBoard: true)
        print("New game started, phase: \(viewModel.state.phase)")
        Task {
            var iterations = 0
            while true {
                if case .gameOver = viewModel.state.phase { break }
                iterations += 1
                guard iterations < 400 else {
                    print("Stopping after \(iterations) iterations without game over")
                    break
                }
                let legal = RulesEngine.legalMoves(for: viewModel.state)
                guard let move = legal.first else {
                    await viewModel.runBotTurnIfNeeded()
                    continue
                }
                do {
                    try viewModel.apply(move)
                } catch {
                    print("Failed to apply move: \(error)")
                    break
                }
                // apply(_:) already spawns its own Task to drive bot
                // turns; calling runBotTurnIfNeeded() again here
                // would race a second driver against it. Instead,
                // poll isBotThinking so this loop still paces itself
                // to wait for that Task to finish before re-checking
                // phase/legal moves. The first sleep gives the
                // spawned Task a chance to actually start (and flip
                // isBotThinking to true) before we check it.
                repeat {
                    try? await Task.sleep(for: .milliseconds(50))
                } while viewModel.isBotThinking
                print("[\(iterations)] phase now: \(viewModel.state.phase)")
            }
            print("Auto-play finished at phase: \(viewModel.state.phase)")
        }
    }
}

#Preview {
    ContentView()
}
