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
        let field = try #require(state.board.tiles.first { $0.kind == .resourceChoice && $0.numberToken == state.lastDiceRoll })
        let settlement = try #require(state.players[actor.index].settlements.first { $0.touchingTiles.contains(field.coordinate) })
        let city = try #require(state.players[actor.index].cities.first { $0.touchingTiles.contains(field.coordinate) })
        #expect(Naval.isCoastal(settlement, in: state) && Naval.isCoastal(city, in: state))
        #expect(!state.board.adjacentVertices(of: settlement).contains(city))
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

    @Test func nonzeroHumanCollectsABotRollOnceThenResumesThatBotsTurn() throws {
        let human = PlayerID(index: 2), roller = PlayerID(index: 1)
        let fixture = try CheckpointModelFixture()
        var writes = 0
        let model = fixture.makeModel(atCommitStage: { if $0 == .beforeReplace { writes += 1 } })
        model.replaceStateForTesting(try cityBeforeBotRoll(human: human, roller: roller), humanSeat: human)
        // Stand in for the mandatory popup's hold. The test commits the next
        // actual policy step explicitly, without racing its queued bot task.
        model.isBlockingSurfaceOpen = true
        let rolled = try commitPolicyStep(in: model)
        #expect(rolled.actor == roller && rolled.move == .rollDice)
        #expect(model.humanPlayer == human && model.state.phase == .choosingResource(playerIndex: human.index))
        #expect(model.currentNavalHarvestObligation?.requiredCount == 2)
        let before = model.state
        let document = try #require(model.checkpointDocument)
        #expect(document.activeMatch?.moves.last?.actor == roller)
        #expect(document.activeMatch?.moves.last?.isHumanDecision == false)
        writes = 0
        model.selectForNavalHarvest(.ore)
        #expect(!model.canSubmitNavalHarvest && model.state == before)
        model.selectForNavalHarvest(.grain)
        #expect(model.canSubmitNavalHarvest && model.state == before)
        #expect(model.submitNavalHarvest())
        #expect(writes == 1, "The nonzero human's whole harvest has one checkpoint replacement")
        try assertNonzeroBatch(model, before: before, document: document, human: human, roller: roller)
        #expect(!model.submitNavalHarvest() && writes == 1, "A repeated confirmation cannot collect another batch")
        try assertResumedBotContinuation(model, fixture: fixture, human: human, roller: roller)
    }

    /// Generated terrain and setup are retained. This prepares a real ship,
    /// landing and city for seat two; only the established QA travel refresh
    /// and matching-roll cursor shortcut ordinary intervening rounds.
    private func cityBeforeBotRoll(human: PlayerID, roller: PlayerID) throws -> GameState {
        var state = try NavalQAFixture.make(.voyage)
        let field = try #require(state.board.tiles.filter { tile in
            tile.kind == .resourceChoice && state.board.corners(of: tile.coordinate).contains {
                Naval.isCoastal($0, in: state)
            }
        }.sorted { $0.coordinate < $1.coordinate }.first)
        NavalQAFixture.grant(Naval.shipCost, to: human, in: &state)
        let shipID = try NavalQAFixture.purchase(for: human, in: &state)
        let sea = Set(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        let goals = Set(state.board.corners(of: field.coordinate).flatMap(\.touchingTiles)).intersection(sea)
        _ = try #require(goals.isEmpty ? nil : goals, "The harvest field needs an actual sea approach")
        let index = try #require(state.naval?.ships.firstIndex { $0.id == shipID })
        let origin = try #require(state.naval?.ships[index].coordinate)
        for destination in NavalQAFixture.shortestPath(from: origin, to: goals, sea: sea) {
            let allowance = Naval.movementPerTurn(in: state)
            state.naval?.ships[index].stepsRemaining = allowance
            try RulesEngine.apply(.sailShip(id: shipID, to: destination), by: human, to: &state)
        }
        let coast = try #require(state.board.corners(of: field.coordinate).sorted().first {
            Naval.canFoundColony(at: $0, by: human, in: state)
        })
        NavalQAFixture.grant(Building.settlementCost, to: human, in: &state)
        try RulesEngine.apply(.buildSettlement(coast), by: human, to: &state)
        NavalQAFixture.grant(Building.cityCost, to: human, in: &state)
        try RulesEngine.apply(.buildCity(coast), by: human, to: &state)
        state.phase = .rollDice(playerIndex: roller.index)
        state.rng = NavalQAFixture.rollSource(total: try #require(field.numberToken))
        #expect(Naval.validationProblem(in: state) == nil)
        for resource in Resource.allCases {
            #expect(state.players.reduce(0) { $0 + $1.resources[resource, default: 0] }
                + state.bank[resource, default: 0] == state.rules.bankPerResource)
        }
        return state
    }

    private func commitPolicyStep(in model: GameViewModel) throws -> GameSession.Step {
        var candidate = model.session
        let step = try #require(try candidate.step())
        model.beginEventBatch()
        try model.commitStep(step, candidate: candidate, isHumanDecision: false)
        return step
    }

    private func assertNonzeroBatch(_ model: GameViewModel, before: GameState, document: MatchCheckpointDocument,
                                    human: PlayerID, roller: PlayerID) throws {
        #expect(model.checkpointDocument?.revision == document.revision + 1)
        let moves = try #require(model.checkpointDocument?.activeMatch?.moves.suffix(2))
        #expect(moves.map(\.actor) == [human, human])
        #expect(moves.map(\.move) == [.chooseResource(.ore), .chooseResource(.grain)])
        #expect(moves.allSatisfy { $0.isHumanDecision })
        assertCredit([.ore: 1, .grain: 1], before: before, after: model.state, owner: human)
        for player in before.players where player.id != human {
            #expect(model.state.players[player.id.index].resources == player.resources)
        }
        #expect(model.state.phase == .mainTurn(playerIndex: roller.index))
        #expect(model.session.nextActor() == .seat(roller))
        #expect(model.state.naval?.pendingResourceChoices.isEmpty == true)
        try model.checkpointDocument?.validateAuthority()
    }

    private func assertResumedBotContinuation(_ model: GameViewModel, fixture: CheckpointModelFixture,
                                              human: PlayerID, roller: PlayerID) throws {
        let restored = fixture.makeModel()
        restored.isBlockingSurfaceOpen = true
        #expect(restored.humanPlayer == human && restored.session.checkpoint == model.session.checkpoint)
        #expect(restored.state.phase == .mainTurn(playerIndex: roller.index))
        let step = try commitPolicyStep(in: restored)
        #expect(step.actor == roller, "Collection returns control to the bot whose roll produced the harvest")
        #expect(restored.checkpointDocument?.activeMatch?.moves.last?.actor == roller)
        #expect(restored.checkpointDocument?.activeMatch?.moves.last?.isHumanDecision == false)
        try restored.checkpointDocument?.validateAuthority()
    }

    private func assertCredit(_ cards: [Resource: Int], before: GameState, after: GameState,
                              owner: PlayerID = PlayerID(index: 0),
                              sourceLocation: SourceLocation = #_sourceLocation) {
        for resource in Resource.allCases {
            let amount = cards[resource, default: 0]
            #expect(after.players[owner.index].resources[resource, default: 0]
                == before.players[owner.index].resources[resource, default: 0] + amount, sourceLocation: sourceLocation)
            #expect(after.bank[resource, default: 0] == before.bank[resource, default: 0] - amount,
                    sourceLocation: sourceLocation)
        }
    }
}
