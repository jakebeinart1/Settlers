import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct NavalHarvestSelectionTests {
    private let actor = PlayerID(index: 0)

    @Test func mixedHarvestStagesEditableQuantitiesAndCommitsOneRevision() throws {
        let fixture = try CheckpointModelFixture()
        var writes = 0
        let model = fixture.makeModel(atCommitStage: { if $0 == .beforeReplace { writes += 1 } })
        model.replaceStateForTesting(try NavalQAFixture.make(.mixedHarvest), humanSeat: actor)
        let before = model.state
        let session = model.session.checkpoint
        let document = try #require(model.checkpointDocument)
        writes = 0
        model.prepareNavalHarvestPresentation()
        #expect(model.currentNavalHarvestObligation?.requiredCount == 3)
        #expect(!model.canSubmitNavalHarvest)
        model.selectForNavalHarvest(.ore)
        #expect(model.navalHarvestDraft.selectedCount == 1 && !model.canSubmitNavalHarvest)
        model.selectForNavalHarvest(.ore)
        #expect(model.navalHarvestDraft.selectedCount == 2 && !model.canSubmitNavalHarvest)
        model.selectForNavalHarvest(.grain)
        #expect(model.navalHarvestDraft.selectedCount == 3 && model.canSubmitNavalHarvest)
        model.selectForNavalHarvest(.brick)
        #expect(model.navalHarvestDraft.counts == [.ore: 2, .grain: 1])
        model.deselectFromNavalHarvest(.ore)
        #expect(model.navalHarvestDraft.selectedCount == 2 && !model.canSubmitNavalHarvest)
        model.selectForNavalHarvest(.ore)
        #expect(model.state == before && model.session.checkpoint == session)
        #expect(model.checkpointDocument == document && writes == 0)
        #expect(model.submitNavalHarvest())
        #expect(writes == 1)
        #expect(model.checkpointDocument?.revision == document.revision + 1)
        #expect(model.checkpointDocument?.activeMatch?.moves.suffix(3).map(\.move)
            == [.chooseResource(.ore), .chooseResource(.ore), .chooseResource(.grain)])
        assertCredit([.ore: 2, .grain: 1], before: before, after: model.state)
        #expect(model.navalHarvestDraft.selectedCount == 0)
        try model.checkpointDocument?.validateAuthority()
        #expect(fixture.makeModel().session.checkpoint == model.session.checkpoint)
        #expect(!model.submitNavalHarvest())
        #expect(writes == 1, "Repeated confirmation cannot collect the same obligation again")
    }

    @Test(arguments: Resource.allCases)
    func threeOfTheSameResourceAreACompleteLegalSelection(_ resource: Resource) throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try NavalQAFixture.make(.mixedHarvest), humanSeat: actor)
        let before = model.state
        for _ in 0..<3 { model.selectForNavalHarvest(resource) }
        #expect(model.navalHarvestDraft.counts == [resource: 3])
        #expect(model.submitNavalHarvest())
        assertCredit([resource: 3], before: before, after: model.state)
    }

    @Test(arguments: NavalMapFamily.allCases)
    func mixedHarvestUsesActualConservedBuildingsInEachWorldFamily(_ family: NavalMapFamily) throws {
        let state = try NavalQAFixture.make(.mixedHarvest, options: NavalOptions(mapFamily: family))
        let progress = try #require(Naval.harvestProgress(for: actor, in: state))
        #expect(progress.settlements == 1 && progress.cities == 1 && progress.total == 3)
        #expect(Naval.validationProblem(in: state) == nil)
        for resource in Resource.allCases {
            let held = state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
            #expect(held + state.bank[resource, default: 0] == state.rules.bankPerResource)
        }
    }

    @Test func unavailableRepeatedCardCannotPartiallyCreditAnEarlierChoice() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var before = try NavalQAFixture.make(.cityHarvest)
        NavalQAFixture.limitHarvestBank(to: [.ore: 1, .grain: 1], in: &before)
        model.replaceStateForTesting(before, humanSeat: actor)
        let document = model.checkpointDocument
        let session = model.session.checkpoint
        model.selectForNavalHarvest(.ore)
        model.selectForNavalHarvest(.ore)
        #expect(model.navalHarvestDraft.counts == [.ore: 1])
        #expect(!model.canSubmitNavalHarvest && !model.submitNavalHarvest())
        #expect(throws: MoveError.self) { try model.commitNavalHarvest([.ore, .ore]) }
        #expect(model.state == before && model.session.checkpoint == session)
        #expect(model.checkpointDocument == document)
        model.selectForNavalHarvest(.grain)
        #expect(model.submitNavalHarvest())
        assertCredit([.ore: 1, .grain: 1], before: before, after: model.state)
    }

    @Test func exhaustedWholeBankCollectsAvailableCardsWithoutDeadlock() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var before = try NavalQAFixture.make(.mixedHarvest)
        NavalQAFixture.limitHarvestBank(to: [.ore: 1, .grain: 1], in: &before)
        model.replaceStateForTesting(before, humanSeat: actor)
        #expect(model.currentNavalHarvestObligation?.progress.remaining == 3)
        #expect(model.currentNavalHarvestObligation?.requiredCount == 2)
        model.selectForNavalHarvest(.ore)
        model.selectForNavalHarvest(.grain)
        #expect(model.submitNavalHarvest())
        #expect(model.state.phase == .mainTurn(playerIndex: actor.index))
        #expect(model.state.naval?.pendingResourceChoices.isEmpty == true)
        #expect(Resource.allCases.allSatisfy { model.state.bank[$0, default: 0] == 0 })
        assertCredit([.ore: 1, .grain: 1], before: before, after: model.state)
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func failedReplacementRetainsTheWholeChoiceUntilAReconciledRetry() throws {
        let fixture = try CheckpointModelFixture()
        var refusesWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refusesWrite && stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        let before = try NavalQAFixture.make(.cityHarvest)
        model.replaceStateForTesting(before, humanSeat: actor)
        let document = model.checkpointDocument
        model.selectForNavalHarvest(.ore)
        model.selectForNavalHarvest(.grain)
        refusesWrite = true
        #expect(!model.submitNavalHarvest())
        #expect(model.state == before && model.checkpointDocument == document)
        #expect(model.navalHarvestDraft.counts == [.ore: 1, .grain: 1])
        #expect(model.navalHarvestDraft.errorMessage != nil)
        #expect(!model.canSubmitNavalHarvest)
        #expect(fixture.makeModel().state == before, "No first card escaped to disk")
        refusesWrite = false
        #expect(model.retryPersistence())
        #expect(model.navalHarvestDraft.counts == [.ore: 1, .grain: 1])
        #expect(model.navalHarvestDraft.errorMessage == nil)
        #expect(model.navalHarvestErrorMessage == nil, "A successful reload removes the obsolete failure caption")
        #expect(model.canSubmitNavalHarvest && model.submitNavalHarvest())
        assertCredit([.ore: 1, .grain: 1], before: before, after: model.state)
    }

    @Test func acknowledgementLostAfterReplacementCannotDuplicateTheHarvest() throws {
        let fixture = try CheckpointModelFixture()
        var losesAcknowledgement = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if losesAcknowledgement && stage == .afterReplace { throw CocoaError(.fileWriteUnknown) }
        })
        let before = try NavalQAFixture.make(.mixedHarvest)
        model.replaceStateForTesting(before, humanSeat: actor)
        let revision = model.checkpointDocument?.revision
        for _ in 0..<3 { model.selectForNavalHarvest(.ore) }
        losesAcknowledgement = true
        #expect(model.submitNavalHarvest(), "Exact readback acknowledges the already-complete replacement")
        assertCredit([.ore: 3], before: before, after: model.state)
        #expect(model.checkpointDocument?.revision == revision.map { $0 + 1 })
        #expect(model.persistenceErrorMessage == nil)
        #expect(!model.submitNavalHarvest())
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func failedReloadShowsItsNewErrorWhileRetainingTheOriginalDraft() throws {
        let fixture = try CheckpointModelFixture()
        var refusesWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refusesWrite && stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        model.replaceStateForTesting(try NavalQAFixture.make(.cityHarvest), humanSeat: actor)
        model.selectForNavalHarvest(.ore)
        model.selectForNavalHarvest(.grain)
        refusesWrite = true
        #expect(!model.submitNavalHarvest())
        let firstError = model.navalHarvestDraft.errorMessage
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("match_checkpoint.json"))
        #expect(!model.retryPersistence())
        #expect(model.navalHarvestErrorMessage == model.persistenceErrorMessage)
        #expect(model.navalHarvestErrorMessage != firstError)
        #expect(model.navalHarvestErrorMessage?.contains("checkpoint is missing") == true)
        #expect(model.navalHarvestDraft.counts == [.ore: 1, .grain: 1])
        #expect(model.navalHarvestDraft.errorMessage == firstError, "A failed reload retains the original draft failure")
    }

    @Test func coldResumeDiscardsOnlyTheDraftAndKeepsLegacyPartialCollection() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let before = try NavalQAFixture.make(.mixedHarvest)
        model.replaceStateForTesting(before, humanSeat: actor)
        model.selectForNavalHarvest(.ore)
        let uncommittedResume = fixture.makeModel()
        uncommittedResume.prepareNavalHarvestPresentation()
        #expect(uncommittedResume.state == before)
        #expect(uncommittedResume.navalHarvestDraft.selectedCount == 0)
        try model.commitHumanMove(.chooseResource(.ore)) // A real legacy one-unit checkpoint.
        let restored = fixture.makeModel()
        let progress = try #require(restored.currentNavalHarvestObligation)
        #expect(progress.progress.collected == 1 && progress.progress.total == 3)
        #expect(progress.requiredCount == 2)
        restored.selectForNavalHarvest(.ore)
        restored.selectForNavalHarvest(.grain)
        #expect(restored.submitNavalHarvest())
        assertCredit([.ore: 2, .grain: 1], before: before, after: restored.state)
        try restored.checkpointDocument?.validateAuthority()
    }

    @Test func realMoveOrDifferentMatchCannotReuseAStaleDraft() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try NavalQAFixture.make(.cityHarvest), humanSeat: actor)
        model.selectForNavalHarvest(.grain)
        try model.commitHumanMove(.chooseResource(.ore))
        #expect(!model.canSubmitNavalHarvest)
        model.prepareNavalHarvestPresentation()
        #expect(model.navalHarvestDraft.selectedCount == 0)
        model.selectForNavalHarvest(.ore)
        model.replaceStateForTesting(try NavalQAFixture.make(.cityHarvest), humanSeat: actor)
        model.prepareNavalHarvestPresentation()
        #expect(model.navalHarvestDraft.selectedCount == 0)
        #expect(!model.canSubmitNavalHarvest)
    }

    @Test func existingTimeAccountingDoesNotClearUncommittedSelections() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try NavalQAFixture.make(.cityHarvest), humanSeat: actor)
        model.selectForNavalHarvest(.ore)
        let document = try #require(model.checkpointDocument)
        try model.commitDocument(document.recordingElapsedTime(0))
        model.prepareNavalHarvestPresentation()
        #expect(model.navalHarvestDraft.counts == [.ore: 1])
    }

    private func assertCredit(_ cards: [Resource: Int], before: GameState, after: GameState,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        for resource in Resource.allCases {
            let amount = cards[resource, default: 0]
            #expect(after.players[actor.index].resources[resource, default: 0]
                == before.players[actor.index].resources[resource, default: 0] + amount, sourceLocation: sourceLocation)
            #expect(after.bank[resource, default: 0] == before.bank[resource, default: 0] - amount,
                    sourceLocation: sourceLocation)
        }
    }
}
