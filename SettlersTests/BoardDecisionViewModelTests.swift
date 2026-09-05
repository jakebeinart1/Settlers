import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct BoardDecisionViewModelTests {
    @Test func confirmingOpeningSettlementCommitsOnceThenRequiresConfirmedRoad() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        let before = model.state
        let revision = model.checkpointDocument?.revision
        let vertex = try #require(model.boardDecisionPresentation?.legalVertices.first)

        let selected = model.selectBoardTarget(.vertex(vertex))
        #expect(selected)
        #expect(model.state == before)
        #expect(model.checkpointDocument?.revision == revision)
        let confirmed = model.confirmBoardDecision()
        #expect(confirmed)

        #expect(model.state.players[model.humanPlayer.index].settlements == [vertex])
        #expect(model.boardDecisionPresentation?.intent == .initialRoad)
        #expect(model.boardDecisionPresentation?.selectedEdges.isEmpty == true)
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func failedCheckpointWriteKeepsTheProposalForAnExactRetry() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        model.startNewGame(setup: fixture.setup)
        let before = model.state
        let revision = model.checkpointDocument?.revision
        let vertex = try #require(model.boardDecisionPresentation?.legalVertices.first)
        let selected = model.selectBoardTarget(.vertex(vertex))
        #expect(selected)
        refuseWrite = true

        let failedConfirmation = model.confirmBoardDecision()
        #expect(!failedConfirmation)

        #expect(model.state == before)
        #expect(model.checkpointDocument?.revision == revision)
        #expect(model.boardDecisionPresentation?.selectedVertex == vertex)
        #expect(model.boardDecisionPresentation?.canConfirm == true)
        #expect(model.boardDecisionPresentation?.errorMessage != nil)

        refuseWrite = false
        let retried = model.retryPersistence()
        #expect(retried)
        #expect(model.boardDecisionPresentation?.selectedVertex == vertex)
        let confirmed = model.confirmBoardDecision()
        #expect(confirmed)
        #expect(model.state.players[model.humanPlayer.index].settlements == [vertex])
    }

    @Test func failedRobberWriteRetainsDestinationVictimAndRetryPath() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        model.startNewGame(setup: fixture.setup)
        let actor = model.humanPlayer
        let victim = PlayerID(index: actor.index == 0 ? 1 : 0)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5_205)
        let tile = state.board.tiles.first { $0.coordinate != state.board.robberTile }!.coordinate
        let vertex = state.board.onBoardVertices.first {
            state.board.neighborTiles(of: $0).contains(tile)
        }!
        state.players[victim.index].settlements.insert(vertex)
        state.players[victim.index].resources = [.ore: 1]
        state.bank[.ore, default: 0] -= 1
        state.phase = .movingRobber(playerIndex: actor.index)
        model.replaceStateForTesting(state, humanSeat: actor)
        let before = model.state
        #expect(model.selectBoardTarget(.tile(tile)))
        #expect(model.selectBoardTarget(.victim(victim)))
        refuseWrite = true

        #expect(!model.confirmBoardDecision())

        #expect(model.state == before)
        #expect(model.boardDecisionPresentation?.selectedTile == tile)
        #expect(model.boardDecisionPresentation?.selectedVictim == victim)
        #expect(model.boardDecisionPresentation?.canConfirm == true)
        #expect(model.boardDecisionPresentation?.errorMessage != nil)

        refuseWrite = false
        #expect(model.retryPersistence())
        #expect(model.boardDecisionPresentation?.selectedTile == tile)
        #expect(model.boardDecisionPresentation?.selectedVictim == victim)
        #expect(model.confirmBoardDecision())
        #expect(model.state.board.robberTile == tile)
    }

    @Test func optionalBuildThoughtDoesNotSurviveColdRelaunch() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        var state = model.state
        let player = model.humanPlayer
        let vertex = state.board.onBoardVertices.sorted().first!
        state.players[player.index].settlements.insert(vertex)
        state.players[player.index].resources = [.brick: 1, .lumber: 1]
        state.bank[.brick, default: 0] -= 1
        state.bank[.lumber, default: 0] -= 1
        state.phase = .mainTurn(playerIndex: player.index)
        model.replaceStateForTesting(state, humanSeat: player)
        let began = model.beginBoardDecision(.buildRoad)
        #expect(began)
        let edge = try #require(model.boardDecisionPresentation?.legalEdges.first)
        let selected = model.selectBoardTarget(.edge(edge))
        #expect(selected)

        let resumed = fixture.makeModel()

        #expect(resumed.boardDecisionPresentation == nil)
        #expect(resumed.state.players[player.index].roads.isEmpty)
        #expect(resumed.state.players[player.index].resources[.brick] == 1)
        #expect(resumed.state.players[player.index].resources[.lumber] == 1)
    }

    @Test func backgroundRoundTripPreservesAnOptionalProposalInMemory() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        let actor = model.humanPlayer
        model.replaceStateForTesting(paidRoadState(actor: actor), humanSeat: actor)
        #expect(model.beginBoardDecision(.buildRoad))
        let edge = try #require(model.boardDecisionPresentation?.legalEdges.first)
        #expect(model.selectBoardTarget(.edge(edge)))
        let before = model.state

        model.appWillResignActive()
        model.appDidBecomeActive()
        model.reconcileBoardDecision()

        #expect(model.state == before)
        #expect(model.boardDecisionPresentation?.selectedEdges == [edge])
        #expect(model.boardDecisionPresentation?.canConfirm == true)
    }

    @Test func coldRelaunchRestoresMandatoryRobberBlankWithoutMovingIt() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        model.startNewGame(setup: fixture.setup)
        let actor = model.humanPlayer
        var state = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 5_204,
            playerCount: model.state.players.count,
            victoryPointTarget: model.state.victoryPointTarget
        )
        state.phase = .movingRobber(playerIndex: actor.index)
        model.replaceStateForTesting(state, humanSeat: actor)
        let origin = model.state.board.robberTile
        let destination = try #require(model.boardDecisionPresentation?.legalTiles.first)
        #expect(model.selectBoardTarget(.tile(destination)))

        let resumed = fixture.makeModel()

        #expect(resumed.state.board.robberTile == origin)
        #expect(resumed.boardDecisionPresentation?.intent == .robberAfterSeven)
        #expect(resumed.boardDecisionPresentation?.selectedTile == nil)
        #expect(resumed.boardDecisionPresentation?.canConfirm == false)
    }

    @Test func hotSeatTurnBoundaryDropsTheOutgoingPlayersProposal() throws {
        let model = isolatedGameViewModel()
        let first = PlayerID(index: 0)
        let second = PlayerID(index: 1)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 52)
        state.phase = .mainTurn(playerIndex: first.index)
        model.replaceStateForTesting(state, humanSeats: [first, second])
        let beganUnavailableKnight = model.beginBoardDecision(.knight)
        #expect(!beganUnavailableKnight)

        let vertex = state.board.onBoardVertices.sorted().first!
        state.players[first.index].settlements.insert(vertex)
        state.players[first.index].resources = [.brick: 1, .lumber: 1]
        state.bank[.brick, default: 0] -= 1
        state.bank[.lumber, default: 0] -= 1
        model.replaceStateForTesting(state, humanSeats: [first, second])
        let beganRoad = model.beginBoardDecision(.buildRoad)
        #expect(beganRoad)
        let edge = try #require(model.boardDecisionPresentation?.legalEdges.first)
        let selected = model.selectBoardTarget(.edge(edge))
        #expect(selected)

        try model.apply(.endTurn)

        #expect(model.needsHandoff)
        #expect(model.boardDecisionPresentation == nil)
        model.claimDeviceForSeatOwedATurn()
        #expect(model.humanPlayer == second)
        #expect(model.boardDecisionPresentation == nil)
    }

    @Test func coldBotTurnHandoffBlocksPolicyMovesUntilItIsClaimed() async {
        let model = isolatedGameViewModel()
        let first = PlayerID(index: 0)
        let second = PlayerID(index: 1)
        let bot = PlayerID(index: 2)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 5_203)
        state.phase = .mainTurn(playerIndex: bot.index)
        model.replaceStateForTesting(state, humanSeats: [first, second])
        model.qaClearSeatAtDeviceForTesting()
        #expect(model.needsHandoff)
        #expect(model.seatOwedATurn == nil)
        let before = model.state
        let revision = model.checkpointDocument?.revision
        let priority = GameInteractionPriority.resolve(GameInteractionPriorityInput(
            needsHandoff: true
        ))
        model.isBlockingSurfaceOpen = priority.blocksBotProgress

        await model.runBotTurnIfNeeded()

        #expect(model.state == before)
        #expect(model.checkpointDocument?.revision == revision)

        model.claimDeviceForSeatOwedATurn()

        #expect(model.seatAtDevice == first)
        #expect(!model.needsHandoff)
    }

    @Test func paidRoadSpendsNothingUntilOneSuccessfulConfirmation() throws {
        let model = isolatedGameViewModel()
        let actor = model.humanPlayer
        var state = paidRoadState(actor: actor)
        model.replaceStateForTesting(state, humanSeat: actor)
        let before = model.state
        let began = model.beginBoardDecision(.buildRoad)
        #expect(began)
        let edge = try #require(model.boardDecisionPresentation?.legalEdges.first)

        let selected = model.selectBoardTarget(.edge(edge))
        #expect(selected)
        #expect(model.state == before)
        model.clearBoardDecisionSelection()
        #expect(model.state == before)
        let selectedAgain = model.selectBoardTarget(.edge(edge))
        #expect(selectedAgain)
        let confirmed = model.confirmBoardDecision()
        #expect(confirmed)

        state = model.state
        #expect(state.players[actor.index].roads.contains(edge))
        #expect(state.players[actor.index].resources[.brick] == 0)
        #expect(state.players[actor.index].resources[.lumber] == 0)
        #expect(model.boardDecisionPresentation == nil)
    }

    @Test func paidSettlementStagesThenCommitsThePieceAndExactCost() throws {
        let model = isolatedGameViewModel()
        let actor = model.humanPlayer
        let state = paidSettlementState(actor: actor)
        model.replaceStateForTesting(state, humanSeat: actor)
        let before = model.state
        #expect(model.beginBoardDecision(.buildSettlement))
        let vertex = try #require(model.boardDecisionPresentation?.legalVertices.first)

        #expect(model.selectBoardTarget(.vertex(vertex)))
        #expect(model.state == before)
        #expect(model.confirmBoardDecision())

        #expect(model.state.players[actor.index].settlements.contains(vertex))
        #expect(model.state.players[actor.index].resources[.brick] == 0)
        #expect(model.state.players[actor.index].resources[.lumber] == 0)
        #expect(model.state.players[actor.index].resources[.wool] == 0)
        #expect(model.state.players[actor.index].resources[.grain] == 0)
    }

    @Test func paidCityStagesThenReplacesOnlyItsSettlementOnConfirm() throws {
        let model = isolatedGameViewModel()
        let actor = model.humanPlayer
        let state = paidCityState(actor: actor)
        let originalSettlement = try #require(state.players[actor.index].settlements.first)
        model.replaceStateForTesting(state, humanSeat: actor)
        let before = model.state
        #expect(model.beginBoardDecision(.buildCity))

        #expect(model.selectBoardTarget(.vertex(originalSettlement)))
        #expect(model.state == before)
        #expect(model.confirmBoardDecision())

        #expect(!model.state.players[actor.index].settlements.contains(originalSettlement))
        #expect(model.state.players[actor.index].cities.contains(originalSettlement))
        #expect(model.state.players[actor.index].resources[.ore] == 0)
        #expect(model.state.players[actor.index].resources[.grain] == 0)
    }

    @Test func roadBuildingKeepsBothRoadsAndCardUncommittedUntilConfirm() throws {
        let model = isolatedGameViewModel()
        let actor = model.humanPlayer
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 53)
        state.phase = .rollDice(playerIndex: actor.index)
        state.players[actor.index].devCards = [.roadBuilding]
        state.players[actor.index].settlements.insert(state.board.onBoardVertices.sorted().first!)
        model.replaceStateForTesting(state, humanSeat: actor)
        let began = model.beginBoardDecision(.roadBuilding)
        #expect(began)
        let first = try #require(model.boardDecisionPresentation?.legalEdges.first)
        let selectedFirst = model.selectBoardTarget(.edge(first))
        #expect(selectedFirst)
        let second = try #require(model.boardDecisionPresentation?.legalEdges.first)
        let selectedSecond = model.selectBoardTarget(.edge(second))
        #expect(selectedSecond)

        #expect(model.state.players[actor.index].roads.isEmpty)
        #expect(model.state.players[actor.index].devCards == [.roadBuilding])
        #expect(model.confirmBoardDecision())
        #expect(model.state.players[actor.index].roads == [first, second])
        #expect(model.state.players[actor.index].devCards.isEmpty)
    }

    @Test func robberDestinationAndVictimRemainAProposalUntilConfirm() throws {
        let model = isolatedGameViewModel()
        let actor = model.humanPlayer
        let victim = PlayerID(index: 1)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 54)
        let tile = state.board.tiles.first { $0.coordinate != state.board.robberTile }!.coordinate
        let vertex = state.board.onBoardVertices.first {
            state.board.neighborTiles(of: $0).contains(tile)
        }!
        state.players[victim.index].settlements.insert(vertex)
        state.players[victim.index].resources = [.ore: 1]
        state.bank[.ore, default: 0] -= 1
        state.phase = .movingRobber(playerIndex: actor.index)
        model.replaceStateForTesting(state, humanSeat: actor)
        let before = model.state

        #expect(model.selectBoardTarget(.tile(tile)))
        #expect(model.boardDecisionPresentation?.canConfirm == false)
        #expect(model.selectBoardTarget(.victim(victim)))
        #expect(model.state == before)
        #expect(model.confirmBoardDecision())

        #expect(model.state.board.robberTile == tile)
        #expect(model.state.players[victim.index].resources[.ore] == 0)
        #expect(model.state.players[actor.index].resources[.ore] == 1)
    }

    @Test func settingsCoverPreservesKnightProposalAndCancelConsumesNothing() throws {
        let model = isolatedGameViewModel()
        let actor = model.humanPlayer
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 55)
        state.phase = .rollDice(playerIndex: actor.index)
        state.players[actor.index].devCards = [.knight]
        model.replaceStateForTesting(state, humanSeat: actor)
        #expect(model.beginBoardDecision(.knight))
        let tile = try #require(model.boardDecisionPresentation?.legalTiles.first)
        #expect(model.selectBoardTarget(.tile(tile)))

        model.isBlockingSurfaceOpen = true
        model.reconcileBoardDecision()
        model.isBlockingSurfaceOpen = false
        model.reconcileBoardDecision()

        #expect(model.boardDecisionPresentation?.selectedTile == tile)
        #expect(model.cancelBoardDecision())
        #expect(model.state.players[actor.index].devCards == [.knight])
        #expect(model.state.board.robberTile != tile)
    }

    private func paidRoadState(actor: PlayerID) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 56)
        let vertex = state.board.onBoardVertices.sorted().first!
        state.players[actor.index].settlements.insert(vertex)
        state.players[actor.index].resources = [.brick: 1, .lumber: 1]
        state.bank[.brick, default: 0] -= 1
        state.bank[.lumber, default: 0] -= 1
        state.phase = .mainTurn(playerIndex: actor.index)
        return state
    }

    private func paidSettlementState(actor: PlayerID) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 57)
        let start = state.board.onBoardVertices.sorted().first!
        let first = state.board.edgesTouching(start).sorted().first!
        let endpoints = state.board.vertices(of: first)
        let middle = endpoints.0 == start ? endpoints.1 : endpoints.0
        let second = state.board.edgesTouching(middle).sorted().first { $0 != first }!
        state.players[actor.index].settlements.insert(start)
        state.players[actor.index].roads.formUnion([first, second])
        state.players[actor.index].resources = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1]
        for resource in [Resource.brick, .lumber, .wool, .grain] {
            state.bank[resource, default: 0] -= 1
        }
        state.phase = .mainTurn(playerIndex: actor.index)
        return state
    }

    private func paidCityState(actor: PlayerID) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 58)
        state.players[actor.index].settlements.insert(state.board.onBoardVertices.sorted().first!)
        state.players[actor.index].resources = [.ore: 3, .grain: 2]
        state.bank[.ore, default: 0] -= 3
        state.bank[.grain, default: 0] -= 2
        state.phase = .mainTurn(playerIndex: actor.index)
        return state
    }
}
