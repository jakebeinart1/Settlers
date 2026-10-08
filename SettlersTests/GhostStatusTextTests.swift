import CatanAI
import Testing
@testable import Settlers

/// Jake, 2026-10-08: "clear that the ghost is being trained, when it is done
/// (games remaining)".
@Suite struct GhostStatusTextTests {
    private func ghost(games: Int, paused: Bool = false) -> GhostProfile {
        GhostProfile(id: "me", name: "Me's Ghost", person: .anchored(at: .forMode(.classic)), lambda: 0.01,
                     gamesLearned: games, isTrainingPaused: paused)
    }

    @Test func eachStateReadsAsSpecified() {
        #expect(GhostStatusText.line(for: ghost(games: 3), isTraining: true) == "Training now...")
        #expect(GhostStatusText.line(for: ghost(games: 7), isTraining: false) == "Learning - 3 more games until others can play it")
        #expect(GhostStatusText.line(for: ghost(games: 9), isTraining: false) == "Learning - 1 more game until others can play it")
        #expect(GhostStatusText.line(for: ghost(games: 12), isTraining: false) == "Learning from every game")
        #expect(GhostStatusText.line(for: ghost(games: 12, paused: true), isTraining: false) == "Paused - your games are not being taught")
    }
}
