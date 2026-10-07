import CatanAI
import CatanEngine
import Foundation
import Testing
@testable import Settlers

/// A completed checkpoint starts bookkeeping inside the model initializer.
/// Installing a stand-in afterward lets real extraction escape into the shared
/// queue, where later tests wait on work whose fixture may already be deleted.
@MainActor
@Suite(.serialized)
struct GhostCompletionIsolationTests {
    @Test func completionAndColdResumeUseTheInjectedTrainerBeforeRestoration() async throws {
        let fixture = try CheckpointModelFixture()
        let probe = CompletionTrainingProbe()
        let model = fixture.makeModel(makeGhostTrainer: { probe.trainer(store: $0) })
        model.startNewGame(setup: fixture.setup)
        try model.qaPlayToEnd()
        await model.lastFinishedMatchWork?.value

        let resumed = fixture.makeModel(makeGhostTrainer: { probe.trainer(store: $0) })
        await resumed.lastFinishedMatchWork?.value

        let match = try #require(model.checkpointDocument?.activeMatch)
        #expect(resumed.state == model.state)
        #expect(resumed.statistics.gamesPlayed == 1)
        #expect(probe.factoryCalls == 2, "Completion and restoration must both use the injected factory")
        let extractions = probe.extractions
        #expect(extractions.count == 2, "Both bounded tasks must finish before fixture cleanup")
        #expect(extractions.allSatisfy { $0.gameID == match.id.uuidString && $0.moveCount == match.moves.count })
        #expect(extractions.allSatisfy { $0.humanSeats == model.humanSeats })
        #expect(extractions.allSatisfy { $0.moveCount > 100 }, "Use a real completed trajectory")
        #expect(model.ratingStore.load().ratedMatches == [match.id], "Rating stays idempotent on resume")
        #expect(model.seatStatsStore.all().count == 1)
        #expect(model.ghostStore.all().isEmpty, "A stand-in with no decisions must teach nothing")
        #expect(resumed.clearCompletedMatch())
        #expect(fixture.makeModel().statistics.gamesPlayed == 1)
    }
}

/// Records the completion seam across the detached task and its caller without
/// sharing application stores or weakening the production queue's serialization.
private final class CompletionTrainingProbe: @unchecked Sendable {
    struct Extraction: Sendable {
        let gameID: String
        let moveCount: Int
        let humanSeats: Set<PlayerID>
    }

    private let lock = NSLock()
    private var factories = 0
    private var recorded: [Extraction] = []
    var factoryCalls: Int { lock.withLock { factories } }
    var extractions: [Extraction] { lock.withLock { recorded } }

    func trainer(store: GhostStore) -> GhostTrainer {
        lock.withLock { factories += 1 }
        var trainer = GhostTrainer(store: store)
        trainer.extract = { [self] game, _ in
            lock.withLock {
                recorded.append(Extraction(gameID: game.id, moveCount: game.events.count, humanSeats: game.humanSeats))
            }
            return []
        }
        return trainer
    }
}
