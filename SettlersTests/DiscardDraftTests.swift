import Foundation
import CatanEngine
import Testing
@testable import Settlers

struct DiscardDraftTests {
    @Test func selectionCannotExceedTheRequirementOrCardsOwned() {
        var draft = DiscardDraft()

        draft.select(.brick, owned: 2, required: 3)
        draft.select(.brick, owned: 2, required: 3)
        draft.select(.brick, owned: 2, required: 3)
        draft.select(.grain, owned: 4, required: 3)
        draft.select(.grain, owned: 4, required: 3)

        #expect(draft.counts == [.brick: 2, .grain: 1])
        #expect(draft.selectedCount == 3)
    }

    @Test func reachingTheRequiredCountDoesNotSubmitWithoutTheExplicitAction() {
        var draft = DiscardDraft()
        var submitted = false

        draft.select(.ore, owned: 4, required: 2)
        draft.select(.ore, owned: 4, required: 2)

        #expect(draft.isComplete(requiredCount: 2))
        #expect(!submitted)
        #expect(draft.counts == [.ore: 2])

        #expect(draft.submit(requiredCount: 2) { _ in submitted = true })
        #expect(submitted)
    }

    @Test func aFailedCommitRetainsTheFullDraftForRetry() {
        var draft = DiscardDraft()
        draft.select(.wool, owned: 4, required: 2)
        draft.select(.grain, owned: 4, required: 2)

        let succeeded = draft.submit(requiredCount: 2) { _ in
            throw DraftFailure.writeFailed
        }

        #expect(!succeeded)
        #expect(draft.counts == [.wool: 1, .grain: 1])
        #expect(draft.errorMessage == "The discard could not be saved.")
    }

    @Test func aSuccessfulCommitClearsEphemeralSelectionAndError() {
        var draft = DiscardDraft()
        draft.select(.lumber, owned: 4, required: 2)
        draft.select(.lumber, owned: 4, required: 2)
        _ = draft.submit(requiredCount: 2) { _ in throw DraftFailure.writeFailed }

        var committed: [Resource: Int] = [:]
        let succeeded = draft.submit(requiredCount: 2) { committed = $0 }

        #expect(succeeded)
        #expect(committed == [.lumber: 2])
        #expect(draft.counts.isEmpty)
        #expect(draft.errorMessage == nil)
    }

    @Test func removingASelectionMakesThatCardAvailableAgain() {
        var draft = DiscardDraft()
        draft.select(.brick, owned: 1, required: 2)

        draft.deselect(.brick)
        draft.select(.brick, owned: 1, required: 2)

        #expect(draft.counts == [.brick: 1])
        #expect(draft.selectedCount == 1)
    }
}

private enum DraftFailure: LocalizedError {
    case writeFailed

    var errorDescription: String? { "The discard could not be saved." }
}
