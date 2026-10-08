import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct NavalShipCaptureReceiptTests {
    private let human = PlayerID(index: 0)
    private let rival = PlayerID(index: 1)

    @Test(arguments: [false, true])
    func transferReceiptSurvivesColdResumeAndBlocksFurtherPlay(loss: Bool) throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let position = try capturePosition(loss: loss)
        model.replaceStateForTesting(position, humanSeat: human)
        model.isBlockingSurfaceOpen = true
        let actor = loss ? rival : human
        let old = try #require(position.naval?.ships.first)
        try commitCapture(id: old.id, by: actor, in: model)
        let receipt = try #require(model.pendingShipCapture)
        #expect(receipt.previousOwner == old.owner && receipt.newOwner == actor)
        #expect(receipt.coordinate == old.coordinate && receipt.reader == human)
        #expect(receipt.title == (loss ? "Your ship was stolen" : "You took control of a ship"))
        #expect(model.boardDecisionPresentation == nil)
        #expect(!model.beginBoardDecision(.sailShip))
        let committed = model.state
        #expect(throws: MoveError.self) { try model.commitHumanMove(.endTurn) }
        #expect(model.state == committed)
        model.gameplayFeedback.advance(now: Date().addingTimeInterval(100))
        #expect(model.pendingShipCapture == receipt, "Ordinary notice age cannot erase an ownership receipt")
        let resumed = fixture.makeModel()
        #expect(resumed.state == committed && resumed.pendingShipCapture == receipt)
        #expect(resumed.seatOwedATurn == human && resumed.boardDecisionPresentation == nil)
        try resumed.acknowledgeShipCapture()
        #expect(resumed.state == committed && resumed.pendingShipCapture == nil)
        #expect(fixture.makeModel().pendingShipCapture == nil)
    }

    @Test func failedCaptureWritePublishesNeitherTransferNorReceipt() throws {
        let fixture = try CheckpointModelFixture()
        var refusesWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refusesWrite, stage == .beforeReplace { throw CocoaError(.fileWriteOutOfSpace) }
        })
        model.replaceStateForTesting(try capturePosition(loss: true), humanSeat: human)
        model.isBlockingSurfaceOpen = true
        let before = model.session.checkpoint
        refusesWrite = true
        #expect(throws: MatchPersistenceFailure.self) {
            try commitCapture(id: 0, by: rival, in: model)
        }
        #expect(model.session.checkpoint == before && model.pendingShipCapture == nil)
        let resumed = fixture.makeModel()
        #expect(resumed.session.checkpoint == before && resumed.pendingShipCapture == nil)
    }

    @Test func failedAcknowledgementKeepsTheCommittedTransferAndExactReceipt() throws {
        let fixture = try CheckpointModelFixture()
        var refusesWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refusesWrite, stage == .beforeReplace { throw CocoaError(.fileWriteOutOfSpace) }
        })
        model.replaceStateForTesting(try capturePosition(loss: true), humanSeat: human)
        model.isBlockingSurfaceOpen = true
        try commitCapture(id: 0, by: rival, in: model)
        let committed = model.session.checkpoint
        let receipt = try #require(model.pendingShipCapture)
        refusesWrite = true
        #expect(throws: MatchPersistenceFailure.self) { try model.acknowledgeShipCapture() }
        #expect(model.pendingShipCapture == receipt && model.session.checkpoint == committed)
        let resumed = fixture.makeModel()
        #expect(resumed.pendingShipCapture == receipt && resumed.session.checkpoint == committed)
        refusesWrite = false
        try model.acknowledgeShipCapture()
        #expect(model.pendingShipCapture == nil && fixture.makeModel().pendingShipCapture == nil)
        #expect(model.session.checkpoint == committed)
    }

    @Test func ownershipReceiptRemainsValidAcrossElapsedTimeWrites() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try capturePosition(loss: true), humanSeat: human)
        model.isBlockingSurfaceOpen = true
        try commitCapture(id: 0, by: rival, in: model)
        let receipt = try #require(model.pendingShipCapture)
        let document = try #require(model.checkpointDocument)
        let elapsed = try #require(document.activeMatch?.elapsedSeconds)
        try model.commitDocument(document.recordingElapsedTime(elapsed + 1))
        #expect(fixture.makeModel().pendingShipCapture == receipt)
    }

    @Test func thirdPartyCaptureHasTableNewsWithoutAReceipt() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var state = try capturePosition(loss: true)
        state.naval?.ships[0].owner = PlayerID(index: 2)
        state.naval?.hullsBuilt = [PlayerID(index: 2): 1]
        model.replaceStateForTesting(state, humanSeat: human)
        model.isBlockingSurfaceOpen = true
        try commitCapture(id: 0, by: rival, in: model)
        #expect(model.pendingShipCapture == nil)
        #expect(model.gameplayFeedback.current?.kind == .captured(rival, 0, PlayerID(index: 2)))
    }

    @Test func aForgedReceiptCannotDescribeADifferentLocationOrOwner() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try capturePosition(loss: true), humanSeat: human)
        model.isBlockingSurfaceOpen = true
        try commitCapture(id: 0, by: rival, in: model)
        let document = try #require(model.checkpointDocument)
        for field in ["coordinate", "newOwner", "reader", "shipID"] {
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
            var receipt = try #require(object["pendingShipCapture"] as? [String: Any])
            switch field {
            case "coordinate": receipt[field] = ["q": 99, "r": 99]
            case "shipID": receipt[field] = 99
            default: receipt[field] = ["index": 2]
            }
            object["pendingShipCapture"] = receipt
            let forged = try JSONDecoder().decode(MatchCheckpointDocument.self,
                from: JSONSerialization.data(withJSONObject: object))
            #expect(throws: MatchCheckpointStore.StoreError.self) { try forged.validateAuthority() }
        }
    }

    @Test func aSavedImplicitCaptureRuleDoesNotChangeOnColdResume() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var position = try capturePosition(loss: true)
        position.naval?.rulesVersion = 4
        position.naval?.options = .legacyDefaults
        model.replaceStateForTesting(position, humanSeat: human)
        let resumed = fixture.makeModel()
        #expect(resumed.state == position && resumed.state.naval?.options.shipStealingEnabled == true)
        #expect(resumed.checkpointDocument?.activeMatch?.setup.navalOptions == position.naval?.options)
        resumed.isBlockingSurfaceOpen = true
        try commitCapture(id: 0, by: rival, in: resumed)
        #expect(fixture.makeModel().pendingShipCapture == resumed.pendingShipCapture)
    }

    @Test func legacyNewGamePrefillDefaultsOffWithoutChangingItsActiveRules() throws {
        var setup = MatchSetup.default(preferredName: "Alex", preferredCivilization: .greece)
        setup.mode = .naval
        setup.victoryPointTarget = 14
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(setup)) as? [String: Any])
        object["navalOptions"] = ["fogEnabled": true, "resourceChoiceEnabled": true]
        let saved = try JSONDecoder().decode(MatchSetup.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(saved.navalOptions.shipStealingEnabled)
        #expect(!saved.normalizedForNewGame().navalOptions.shipStealingEnabled)
        #expect(saved.navalOptions.shipStealingEnabled, "Normalizing the draft must not rewrite its active setup")
        for enabled in [false, true] {
            setup.navalOptions.shipStealingEnabled = enabled
            let restored = try JSONDecoder().decode(MatchSetup.self, from: JSONEncoder().encode(setup))
            #expect(restored.normalizedForNewGame().navalOptions.shipStealingEnabled == enabled)
        }
    }

    @Test(arguments: [1, 2, 3])
    func aNonzeroHumanReceivesTheirActualLossAfterColdResume(index: Int) throws {
        let fixture = try CheckpointModelFixture()
        let reader = PlayerID(index: index)
        var position = try capturePosition(loss: false)
        position.naval?.ships[0].owner = reader
        let model = fixture.makeModel()
        model.replaceStateForTesting(position, humanSeat: reader)
        try commitCapture(id: 0, by: human, in: model)
        let receipt = try #require(model.pendingShipCapture)
        #expect(receipt.previousOwner == reader && receipt.newOwner == human && receipt.reader == reader)
        let resumed = fixture.makeModel()
        #expect(resumed.humanSeats == [reader] && resumed.humanPlayer == reader)
        #expect(resumed.seatOwedATurn == reader && resumed.pendingShipCapture == receipt)
        #expect(resumed.boardDecisionPresentation == nil)
        let committed = resumed.session.checkpoint
        try resumed.acknowledgeShipCapture()
        #expect(resumed.session.checkpoint == committed && resumed.pendingShipCapture == nil)
        #expect(fixture.makeModel().pendingShipCapture == nil)
    }

    @Test func anUnreadReceiptAloneStopsTheLiveBotRunner() async throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try capturePosition(loss: true), humanSeat: human)
        try commitCapture(id: 0, by: rival, in: model)
        #expect(model.pendingShipCapture != nil && model.session.nextActor() == .seat(rival))
        #expect(model.appIsActive && !model.persistenceBlocked)
        model.isBlockingSurfaceOpen = false
        let session = model.session.checkpoint
        let document = model.checkpointDocument
        model.skipBotPauses()
        await model.runBotTurnIfNeeded()
        #expect(model.session.checkpoint == session && model.checkpointDocument == document)
        #expect(fixture.makeModel().session.checkpoint == session)
        #expect(model.pendingShipCapture != nil && !model.isProcessingBotTurns)
    }

    @Test func aNonzeroHumanCanSailTheCapturedHullAfterDurableAcknowledgement() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let position = try capturePosition(loss: true)
        model.replaceStateForTesting(position, humanSeat: rival)
        let original = try #require(position.naval?.ships.first)
        #expect(model.selectBoardTarget(.ship(original.id)) && model.confirmBoardDecision())
        #expect(model.pendingShipCapture?.reader == rival)
        #expect(!model.beginBoardDecision(.sailShip))
        let captured = model.state
        try model.acknowledgeShipCapture()
        #expect(model.state == captured && model.pendingShipCapture == nil)
        #expect(model.selectBoardTarget(.ship(original.id)))
        let sailing = try #require(model.boardDecisionPresentation?.sailing)
        let destination = try #require(sailing.routes.keys.sorted().first { sailing.routes[$0]?.count == 2 })
        #expect(model.selectBoardTarget(.tile(destination)) && model.confirmBoardDecision())
        let sailed = try #require(model.state.naval?.ships.first { $0.id == original.id })
        #expect(sailed.owner == rival && sailed.coordinate == destination && sailed.stepsRemaining == 0)
        #expect(model.checkpointDocument?.activeMatch?.moves.map(\.move) == [
            .captureShip(id: original.id), .sailShip(id: original.id, to: destination)
        ])
        let resumed = fixture.makeModel()
        #expect(resumed.state == model.state && resumed.pendingShipCapture == nil)
    }

    private func commitCapture(id: Int, by actor: PlayerID, in model: GameViewModel) throws {
        var candidate = model.session
        let step = try candidate.applyExternal(.captureShip(id: id), by: actor)
        try model.qaCommitStep(step, candidate: candidate)
    }

    private func capturePosition(loss: Bool) throws -> GameState {
        var state = try NavalQAFixture.make(loss ? .shipLoss : .capture)
        if loss { try RulesEngine.apply(.rollDice, by: rival, to: &state) }
        return state
    }
}
