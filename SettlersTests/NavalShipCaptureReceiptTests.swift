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
        try model.applyLogged(.captureShip(id: old.id), by: actor, isHumanDecision: !loss)
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
            try model.applyLogged(.captureShip(id: 0), by: rival, isHumanDecision: false)
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
        try model.applyLogged(.captureShip(id: 0), by: rival, isHumanDecision: false)
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
        try model.applyLogged(.captureShip(id: 0), by: rival, isHumanDecision: false)
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
        try model.applyLogged(.captureShip(id: 0), by: rival, isHumanDecision: false)
        #expect(model.pendingShipCapture == nil)
        #expect(model.gameplayFeedback.current?.kind == .captured(rival, 0, PlayerID(index: 2)))
    }

    @Test func aForgedReceiptCannotDescribeADifferentLocationOrOwner() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try capturePosition(loss: true), humanSeat: human)
        model.isBlockingSurfaceOpen = true
        try model.applyLogged(.captureShip(id: 0), by: rival, isHumanDecision: false)
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
        try resumed.applyLogged(.captureShip(id: 0), by: rival, isHumanDecision: false)
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

    private func capturePosition(loss: Bool) throws -> GameState {
        var state = try NavalQAFixture.make(loss ? .shipLoss : .capture)
        if loss { try RulesEngine.apply(.rollDice, by: rival, to: &state) }
        return state
    }
}
