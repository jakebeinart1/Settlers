import Foundation
import Testing
import CatanEngine
@testable import Settlers

@MainActor
struct GameplayFeedbackCommitTests {
    @Test func stagedCancelledAndFailedRoadsNeverAnnounceAndSuccessfulRetryAnnouncesOnce() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        model.qaPrepareLongestRoadPosition()
        model.isBlockingSurfaceOpen = true
        let original = model.state
        #expect(model.gameplayFeedback.current == nil)
        #expect(model.cancelBoardDecision())
        #expect(model.gameplayFeedback.current == nil)
        model.qaPrepareLongestRoadPosition()
        refuseWrite = true
        #expect(!model.confirmBoardDecision())
        #expect(model.state == original)
        #expect(model.gameplayFeedback.current == nil)
        refuseWrite = false
        #expect(model.retryPersistence())
        #expect(model.confirmBoardDecision())
        #expect(model.state.longestRoadPlayer == model.humanPlayer)
        let receipt = try #require(model.gameplayFeedback.current)
        #expect(receipt.pointChanges[model.humanPlayer] == 2)
        #expect(receipt.pointChanges.values.sorted() == [-2, 2])
        #expect(!model.confirmBoardDecision())
        #expect(model.gameplayFeedback.current?.id == receipt.id)
        #expect(model.gameplayFeedback.pending.isEmpty)
    }

    @Test func backgroundColdResumeAndRestartDoNotReplayNotices() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.qaPrepareLongestRoadPosition()
        model.isBlockingSurfaceOpen = true
        #expect(model.confirmBoardDecision())
        #expect(model.gameplayFeedback.current != nil)
        let resumed = fixture.makeModel()
        #expect(resumed.gameplayFeedback.current == nil)
        #expect(resumed.state == model.state)
        model.appWillResignActive()
        model.appDidBecomeActive()
        #expect(model.gameplayFeedback.current == nil)
        model.qaPrepareLongestRoadPosition()
        #expect(model.confirmBoardDecision())
        model.startNewGame(setup: fixture.setup)
        #expect(model.gameplayFeedback.current == nil)
        #expect(model.gameplayFeedback.pending.isEmpty)
    }

    @Test func privateAcknowledgementDoesNotGenerateASecondPublicCardPlay() throws {
        let model = isolatedGameViewModel()
        model.qaPrepareMixedDevCardHand()
        model.isBlockingSurfaceOpen = true
        try model.apply(.playMonopoly(.ore))
        let first = try #require(model.gameplayFeedback.current)
        #expect(first.kind == .card(model.humanPlayer, .monopoly))
        #expect(model.pendingDevCardResolution != nil)
        #expect(model.dismissDevCardResolution())
        #expect(model.gameplayFeedback.current?.id == first.id)
        #expect(model.gameplayFeedback.pending.isEmpty)
    }
}
