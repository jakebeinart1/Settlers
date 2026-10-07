import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct NavalMatchFlowTests {
    private let actor = PlayerID(index: 0)

    @Test func launchAndSailAreConfirmedDurableTransactions() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try NavalQAFixture.make(.voyage), humanSeat: actor)
        let before = model.state
        #expect(model.beginBoardDecision(.buildShip))
        let launch = try #require(model.boardDecisionPresentation?.legalTiles.first)
        #expect(model.selectBoardTarget(.tile(launch)))
        #expect(model.state == before)
        #expect(model.cancelBoardDecision())
        #expect(model.state == before)

        #expect(model.beginBoardDecision(.buildShip))
        #expect(model.selectBoardTarget(.tile(launch)))
        #expect(model.confirmBoardDecision())
        let ship = try #require(model.state.naval?.ships.last)
        #expect(ship.coordinate == launch)
        #expect(ship.stepsRemaining == 2)
        for resource in Resource.allCases {
            #expect(model.state.players[0].resources[resource, default: 0]
                == before.players[0].resources[resource, default: 0] - Naval.shipCost[resource, default: 0])
        }
        #expect(model.boardDecisionPresentation?.selectedShip == ship.id)
        let afterLaunch = model.state
        let adjacent = model.boardDecisionPresentation?.sailing?.routes.keys.sorted().first {
            model.boardDecisionPresentation?.sailing?.routes[$0]?.count == 1
        }
        let destination = try #require(adjacent)
        #expect(model.selectBoardTarget(.tile(destination)))
        #expect(model.state == afterLaunch, "A preview must not uncover fog or spend movement")
        #expect(model.confirmBoardDecision())
        #expect(model.state.naval?.ships.last?.coordinate == destination)
        #expect(model.state.naval?.ships.last?.stepsRemaining == 1)
        #expect(model.boardDecisionPresentation?.selectedTile == nil)
        #expect(model.boardDecisionPresentation?.selectedShip == ship.id)
        let restored = fixture.makeModel()
        #expect(restored.state == model.state)
        #expect(restored.boardDecisionPresentation == nil, "Optional travel drafts must not resume")
    }

    @Test func fullDestinationRangeAndOneDurableTwoHexVoyageShareTheEngineRoute() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.replaceStateForTesting(try NavalQAFixture.make(.voyage), humanSeat: actor)
        #expect(model.beginBoardDecision(.buildShip))
        let launch = try #require(model.boardDecisionPresentation?.legalTiles.first)
        #expect(model.selectBoardTarget(.tile(launch)))
        #expect(model.confirmBoardDecision())
        let before = model.state
        let ship = try #require(before.naval?.ships.first)
        let presentation = try #require(model.boardDecisionPresentation)
        let sailing = try #require(presentation.sailing)
        #expect(sailing.remaining == 2 && sailing.allowance == 2)
        #expect(presentation.legalTiles == Naval.sailingDestinations(for: ship, in: before))
        let far = sailing.routes.keys.sorted().first { sailing.routes[$0]?.count == 2 }
        let destination = try #require(far)
        let moves = model.checkpointDocument?.activeMatch?.moves.count
        #expect(model.selectBoardTarget(.tile(destination)))
        #expect(model.boardDecisionPresentation?.sailing?.selectedRoute == sailing.routes[destination])
        #expect(model.state == before, "Choosing a destination cannot reveal terrain or spend travel")
        #expect(model.confirmBoardDecision())
        #expect(model.state.naval?.ships.first?.coordinate == destination)
        #expect(model.state.naval?.ships.first?.stepsRemaining == 0)
        #expect(model.state.players == before.players)
        #expect(model.checkpointDocument?.activeMatch?.moves.count == moves.map { $0 + 1 })
        #expect(model.boardDecisionPresentation == nil)
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func failedSailingWritePreservesFogAndProposalUntilRetry() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        var position = try NavalQAFixture.make(.voyage)
        let launch = try #require(RulesEngine.legalMoves(for: position, seat: actor).first {
            if case .buildShip = $0 { return true }; return false
        })
        try RulesEngine.apply(launch, by: actor, to: &position)
        model.replaceStateForTesting(position, humanSeat: actor)
        let ship = try #require(position.naval?.ships.first)
        #expect(model.selectBoardTarget(.ship(ship.id)))
        let destination = try #require(model.boardDecisionPresentation?.legalTiles.first)
        #expect(model.selectBoardTarget(.tile(destination)))
        let revision = model.checkpointDocument?.revision
        refuseWrite = true
        #expect(!model.confirmBoardDecision())
        #expect(model.state == position)
        #expect(model.checkpointDocument?.revision == revision)
        #expect(model.boardDecisionPresentation?.selectedTile == destination)
        #expect(model.boardDecisionPresentation?.errorMessage != nil)
        refuseWrite = false
        #expect(model.retryPersistence())
        #expect(model.confirmBoardDecision())
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func captureSurvivesColdResumeAndTransfersOnlyTheSelectedHull() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let before = try NavalQAFixture.make(.capture)
        model.replaceStateForTesting(before, humanSeat: actor)
        let selected = try #require(model.boardDecisionPresentation?.legalShips.first)
        #expect(model.selectBoardTarget(.ship(selected)))
        #expect(model.state == before)
        let restored = fixture.makeModel()
        #expect(restored.boardDecisionPresentation?.intent == .captureShip)
        #expect(restored.boardDecisionPresentation?.selectedShip == nil)
        #expect(restored.selectBoardTarget(.ship(selected)))
        #expect(restored.confirmBoardDecision())
        #expect(restored.state.phase == .mainTurn(playerIndex: actor.index))
        let captured = try #require(restored.state.naval?.ships.first { $0.id == selected })
        let original = try #require(before.naval?.ships.first { $0.id == selected })
        #expect(captured.owner == actor)
        #expect(captured.coordinate == original.coordinate)
        #expect(captured.stepsRemaining == 2)
        #expect(restored.state.players == before.players)
        #expect(restored.state.naval?.hullsBuilt == before.naval?.hullsBuilt)
        #expect(fixture.makeModel().state == restored.state)
    }

    @Test func captureCanBeSkippedThroughTheProductionPath() throws {
        let model = isolatedGameViewModel()
        let before = try NavalQAFixture.make(.capture)
        model.replaceStateForTesting(before, humanSeat: actor)
        #expect(model.skipShipCapture())
        #expect(model.state.phase == .mainTurn(playerIndex: 0))
        #expect(model.state.naval?.ships == before.naval?.ships)
        #expect(model.boardDecisionPresentation == nil)
    }

    @Test func failedCityHarvestWriteRetainsBothUnitsUntilReconciliation() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        let before = try NavalQAFixture.make(.cityHarvest)
        model.replaceStateForTesting(before, humanSeat: actor)
        let opening = NavalHarvestPresentation(progress: try #require(Naval.harvestProgress(for: actor, in: model.state)))
        #expect(opening.title == "Choose 2 resources")
        #expect(opening.source == "City harvest")
        #expect(opening.collected == "0 of 2 collected")
        let revision = model.checkpointDocument?.revision
        refuseWrite = true
        #expect(throws: MatchPersistenceFailure.self) { try model.apply(.chooseResource(.ore)) }
        #expect(model.state == before)
        #expect(model.checkpointDocument?.revision == revision)
        #expect(model.state.naval?.pendingResourceChoices.first?.remaining == 2)
        refuseWrite = false
        #expect(model.retryPersistence())
        try model.apply(.chooseResource(.ore))
        #expect(model.state.naval?.pendingResourceChoices.first?.remaining == 1)
        let restored = fixture.makeModel()
        #expect(restored.state == model.state)
        let progress = NavalHarvestPresentation(progress: try #require(Naval.harvestProgress(for: actor, in: restored.state)))
        #expect(progress.title == "Choose 2 resources")
        #expect(progress.source == "City harvest")
        #expect(progress.collected == "1 of 2 collected")
        #expect(progress.remaining == "1 remaining")
        try model.apply(.chooseResource(.ore))
        #expect(model.state.phase == .mainTurn(playerIndex: actor.index))
        #expect(model.state.players[0].resources[.ore, default: 0]
            == before.players[0].resources[.ore, default: 0] + 2)
    }

    @Test(arguments: NavalMapFamily.allCases)
    func harvestAndColonyAccountingResumeInEveryFamily(_ family: NavalMapFamily) throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let before = try NavalQAFixture.make(.harvest, options: NavalOptions(mapFamily: family))
        #expect(Naval.colonyPoints(for: actor, in: before) == 1)
        model.replaceStateForTesting(before, humanSeat: actor)
        let restored = fixture.makeModel()
        #expect(restored.state == before)
        #expect(restored.state.phase == .choosingResource(playerIndex: 0))
        let harvest = NavalHarvestPresentation(progress: try #require(Naval.harvestProgress(for: actor, in: restored.state)))
        #expect(harvest.title == "Choose 1 resource")
        #expect(harvest.source == "Settlement harvest")
        try restored.apply(.chooseResource(.ore))
        #expect(restored.state.players[0].resources[.ore, default: 0]
            == before.players[0].resources[.ore, default: 0] + 1)
        #expect(restored.state.bank[.ore, default: 0] == before.bank[.ore, default: 0] - 1)
        let breakdown = VictoryPointBreakdown(seat: actor, state: restored.state)
        #expect(breakdown.lines.reduce(0) { $0 + $1.points } == breakdown.total)
        #expect(breakdown.lines.first { $0.source == .colonies }?.points == 1)
        #expect(fixture.makeModel().state == restored.state)
    }

    @Test(arguments: [false, true])
    func mixedHarvestNamesItsBuildingsInsteadOfCallingEveryTwoUnitsACity(city: Bool) throws {
        var state = try NavalQAFixture.make(.harvest)
        let tile = try #require(state.board.tiles.first {
            $0.kind == .resourceChoice && $0.numberToken == state.lastDiceRoll
        })
        let otherCorner = try #require(state.board.corners(of: tile.coordinate).first {
            !state.players[0].settlements.contains($0)
        })
        if city {
            state.players[0].cities.insert(otherCorner)
        } else {
            state.players[0].settlements.insert(otherCorner)
        }
        state.naval?.pendingResourceChoices[0].remaining = city ? 3 : 2
        let harvest = NavalHarvestPresentation(progress: try #require(Naval.harvestProgress(for: actor, in: state)))
        #expect(harvest.title == (city ? "Choose 3 resources" : "Choose 2 resources"))
        #expect(harvest.source == (city ? "1 settlement + 1 city" : "2 settlements"))
        #expect(harvest.progress.cities == (city ? 1 : 0))
    }

    @Test func navalSettingsAndExpertIdentityPersistAsOneMatch() throws {
        let fixture = try CheckpointModelFixture()
        var setup = fixture.setup
        setup.mode = .naval
        setup.victoryPointTarget = 14
        setup.difficulty = .expert
        setup.expertRevision = setup.newMatchExpertRevision
        setup.navalOptions = NavalOptions(fogEnabled: false, resourceChoiceEnabled: false, mapFamily: .twinIslands)
        let model = fixture.makeModel()
        model.startNewGame(setup: setup)
        #expect(model.persistenceErrorMessage == nil)
        #expect(model.state.naval?.options == setup.navalOptions)
        let restored = fixture.makeModel()
        #expect(restored.state == model.state)
        #expect(restored.checkpointDocument?.activeMatch?.setup.expertRevision == .navalV1)
        #expect(restored.state.naval?.revealed.count == 169)
        #expect(!restored.state.board.tiles.contains { $0.kind == .resourceChoice })
        #expect(restored.session.policies.values.allSatisfy { $0.id == "naval-expert-v1" })
    }
}
