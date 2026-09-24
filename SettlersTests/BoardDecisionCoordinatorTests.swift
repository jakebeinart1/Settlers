import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@Suite("Confirmable board decisions")
struct BoardDecisionCoordinatorTests {
    private let actor = PlayerID(index: 0)
    private let matchID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    @Test func setupSettlementIsMandatoryAndSelectionDoesNotMutateTheGame() throws {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 41)
        var coordinator = BoardDecisionCoordinator()
        coordinator.reconcile(with: context(state))

        let initial = try #require(coordinator.presentation)
        #expect(initial.intent == .initialSettlement)
        #expect(initial.setupRound == 1)
        #expect(!initial.canCancel)
        #expect(!initial.canConfirm)
        let vertex = try #require(initial.legalVertices.first)
        let before = state

        let selectedVertex = coordinator.select(.vertex(vertex))
        #expect(selectedVertex)

        let selected = try #require(coordinator.presentation)
        #expect(state == before)
        #expect(selected.selectedVertex == vertex)
        #expect(selected.canConfirm)
        #expect(coordinator.confirmableMove == .placeInitialSettlement(vertex))
        let cancelledMandatory = coordinator.cancel()
        #expect(!cancelledMandatory)
    }

    @Test func onePieceProposalCanBeReconsideredBeforeConfirmation() throws {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42)
        var coordinator = BoardDecisionCoordinator()
        coordinator.reconcile(with: context(state))
        let legal = try #require(coordinator.presentation?.legalVertices)
        let first = try #require(legal.first)
        let second = try #require(legal.dropFirst().first)

        let selectedFirst = coordinator.select(.vertex(first))
        let selectedSecond = coordinator.select(.vertex(second))
        #expect(selectedFirst)
        #expect(selectedSecond)

        #expect(coordinator.presentation?.selectedVertex == second)
        #expect(coordinator.confirmableMove == .placeInitialSettlement(second))
    }

    @Test func secondSetupRoundUsesTheActualNonzeroActingSeat() throws {
        let actingSeat = PlayerID(index: 2)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_202)
        state.phase = .setupBackward(playerIndex: actingSeat.index)
        var coordinator = BoardDecisionCoordinator()
        coordinator.reconcile(with: BoardDecisionContext(
            matchID: matchID,
            committedMoveCount: 11,
            actor: actingSeat,
            state: state
        ))

        let presentation = try #require(coordinator.presentation)
        #expect(presentation.actor == actingSeat)
        #expect(presentation.intent == .initialSettlement)
        #expect(presentation.setupRound == 2)
        let vertex = try #require(presentation.legalVertices.first)
        let selected = coordinator.select(.vertex(vertex))
        #expect(selected)
        #expect(coordinator.confirmableMove == .placeInitialSettlement(vertex))
    }

    @Test func paidConstructionCanBeClearedOrCancelledWithoutSpending() throws {
        let state = paidBuildState()
        let before = state
        var coordinator = BoardDecisionCoordinator()
        let began = coordinator.begin(.buildRoad, with: context(state))
        #expect(began)
        let edge = try #require(coordinator.presentation?.legalEdges.first)

        let selected = coordinator.select(.edge(edge))
        #expect(selected)
        #expect(coordinator.confirmableMove == .buildRoad(edge))
        coordinator.clearSelection()
        #expect(coordinator.presentation?.selectedEdges.isEmpty == true)
        #expect(coordinator.confirmableMove == nil)
        #expect(state == before)
        let cancelled = coordinator.cancel()
        #expect(cancelled)
        #expect(coordinator.presentation == nil)
        #expect(state == before)
    }

    @Test func roadBuildingStagesTwoOrderedRoadsBeforeOneAtomicMove() throws {
        let state = roadBuildingState()
        var coordinator = BoardDecisionCoordinator()
        let began = coordinator.begin(.roadBuilding, with: context(state))
        #expect(began)
        let first = try #require(coordinator.presentation?.legalEdges.first)

        let selectedFirst = coordinator.select(.edge(first))
        #expect(selectedFirst)
        #expect(coordinator.confirmableMove == nil)
        let second = try #require(coordinator.presentation?.legalEdges.first)
        #expect(second != first)
        let selectedSecond = coordinator.select(.edge(second))
        #expect(selectedSecond)

        #expect(coordinator.presentation?.selectedEdges == [first, second])
        #expect(coordinator.confirmableMove == .playRoadBuilding(first, second))
        #expect(state.players[actor.index].roads.isEmpty)
        #expect(state.players[actor.index].devCards == [.roadBuilding])
        let undid = coordinator.undoSelection()
        #expect(undid)
        #expect(coordinator.presentation?.selectedEdges == [first])
        #expect(coordinator.confirmableMove == nil)
    }

    @Test func robberDestinationWithoutVictimsStillWaitsForConfirmation() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 43)
        state.phase = .movingRobber(playerIndex: actor.index)
        let origin = state.board.robberTile
        var coordinator = BoardDecisionCoordinator()
        coordinator.reconcile(with: context(state))
        let presentation = try #require(coordinator.presentation)
        let emptyTile = try #require(presentation.legalTiles.first { tile in
            Robber.eligibleVictims(for: tile, thief: actor, in: state).isEmpty
        })

        let selected = coordinator.select(.tile(emptyTile))
        #expect(selected)

        #expect(state.board.robberTile == origin)
        #expect(coordinator.presentation?.selectedTile == emptyTile)
        #expect(coordinator.presentation?.legalVictims.isEmpty == true)
        #expect(coordinator.presentation?.canConfirm == true)
        #expect(coordinator.confirmableMove == .moveRobber(emptyTile, stealFrom: nil))
    }

    @Test func robberWithVictimsRequiresAnExplicitVictimAndCanChangeTerritory() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 44)
        let victim = PlayerID(index: 1)
        let tile = state.board.tiles.first { $0.coordinate != state.board.robberTile }!.coordinate
        let vertex = state.board.onBoardVertices.first {
            state.board.neighborTiles(of: $0).contains(tile)
        }!
        state.players[victim.index].settlements.insert(vertex)
        state.players[victim.index].resources = [.ore: 1]
        state.phase = .movingRobber(playerIndex: actor.index)
        var coordinator = BoardDecisionCoordinator()
        coordinator.reconcile(with: context(state))

        let selectedTile = coordinator.select(.tile(tile))
        #expect(selectedTile)
        #expect(coordinator.presentation?.legalVictims == [victim])
        #expect(coordinator.presentation?.canConfirm == false)
        #expect(coordinator.confirmableMove == nil)
        let selectedVictim = coordinator.select(.victim(victim))
        #expect(selectedVictim)
        #expect(coordinator.presentation?.selectedVictim == victim)
        #expect(coordinator.confirmableMove == .moveRobber(tile, stealFrom: victim))

        let another = try #require(coordinator.presentation?.legalTiles.first { $0 != tile })
        let selectedAnother = coordinator.select(.tile(another))
        #expect(selectedAnother)
        #expect(coordinator.presentation?.selectedTile == another)
        #expect(coordinator.presentation?.selectedVictim == nil)
    }

    @Test(arguments: [0, 1, 2, 3])
    func robberSupportsEveryPossibleVictimCardinality(_ victimCount: Int) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_404)
        let destination = state.board.tiles.first {
            $0.coordinate != state.board.robberTile
        }!.coordinate
        let vertices = state.board.onBoardVertices.sorted().filter {
            state.board.neighborTiles(of: $0).contains(destination)
        }
        let victims = state.players.map(\.id).filter { $0 != actor }
        for (victim, vertex) in zip(victims.prefix(victimCount), vertices) {
            state.players[victim.index].settlements.insert(vertex)
            state.players[victim.index].resources = [.ore: 1]
            state.bank[.ore, default: 0] -= 1
        }
        state.phase = .movingRobber(playerIndex: actor.index)
        var coordinator = BoardDecisionCoordinator()
        coordinator.reconcile(with: context(state))

        let selected = coordinator.select(.tile(destination))
        #expect(selected)

        let presentation = try #require(coordinator.presentation)
        #expect(presentation.legalVictims.count == victimCount)
        #expect(Set(presentation.legalVictims) == Set(victims.prefix(victimCount)))
        #expect(presentation.canConfirm == (victimCount == 0))

        let chosenVictim = presentation.legalVictims.last
        if let chosenVictim {
            let selectedVictim = coordinator.select(.victim(chosenVictim))
            #expect(selectedVictim)
        }
        let move = try #require(coordinator.confirmableMove)
        try RulesEngine.apply(move, by: actor, to: &state)

        #expect(state.board.robberTile == destination)
        if let chosenVictim {
            #expect(state.players[chosenVictim.index].resources[.ore] == 0)
            #expect(state.players[actor.index].resources[.ore] == 1)
        }
    }

    @Test func knightIsCancellableAndItsCardIsNotConsumedBySelection() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 45)
        state.phase = .rollDice(playerIndex: actor.index)
        state.players[actor.index].devCards = [.knight]
        let before = state
        var coordinator = BoardDecisionCoordinator()

        let began = coordinator.begin(.knight, with: context(state))
        #expect(began)
        let tile = try #require(coordinator.presentation?.legalTiles.first)
        let selected = coordinator.select(.tile(tile))
        #expect(selected)
        #expect(state == before)
        let cancelled = coordinator.cancel()
        #expect(cancelled)
        #expect(state.players[actor.index].devCards == [.knight])
    }

    @Test func contextChangeDropsOptionalThoughtsAndRebuildsMandatoryOnesBlank() throws {
        let state = paidBuildState()
        var coordinator = BoardDecisionCoordinator()
        let began = coordinator.begin(.buildSettlement, with: context(state))
        #expect(began)
        let vertex = try #require(coordinator.presentation?.legalVertices.first)
        let selected = coordinator.select(.vertex(vertex))
        #expect(selected)

        coordinator.reconcile(with: context(state, moveCount: 8))
        #expect(coordinator.presentation == nil)

        var mandatory = GameSetup.newGame(board: BoardGenerator.standard(), seed: 46)
        mandatory.phase = .movingRobber(playerIndex: actor.index)
        coordinator.reconcile(with: context(mandatory, moveCount: 9))
        #expect(coordinator.presentation?.intent == .robberAfterSeven)
        #expect(coordinator.presentation?.selectedTile == nil)
    }

    private func conquestTurn(hand: [Int]) -> (GameState, HexCoordinate) {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310, variant: .conquest)
        let six = state.board.tiles.sorted { $0.coordinate < $1.coordinate }.first { $0.numberToken == 6 }!
        state.players[0].settlements.insert(state.board.corners(of: six.coordinate)[0])
        state.armyHands[actor] = hand
        state.phase = .mainTurn(playerIndex: 0)
        return (state, six.coordinate)
    }

    @Test func deployingIsTapAHexThenChooseCards() throws {
        let (state, six) = conquestTurn(hand: [2, 5])
        var coordinator = BoardDecisionCoordinator()
        let result1 = coordinator.begin(.deployArmy, with: context(state))
        #expect(result1)
        let begun = try #require(coordinator.presentation)
        #expect(begun.legalTiles.contains(six))
        #expect(!begun.canConfirm)

        let result2 = coordinator.select(.tile(six))
        #expect(result2)
        #expect(coordinator.presentation?.legalArmyCards == [2, 5])
        #expect(coordinator.presentation?.canConfirm == false, "a hex alone is not a deploy")

        let result3 = coordinator.select(.armyCards([2, 5]))
        #expect(result3)
        #expect(coordinator.presentation?.selectedArmyCards == [2, 5])
        #expect(coordinator.confirmableMove == .deployArmy(to: six, strengths: [2, 5]))

        let result4 = coordinator.select(.armyCards([]))
        #expect(result4)
        #expect(coordinator.confirmableMove == nil, "deselecting every card un-stages the deploy")
    }

    @Test func aCardSetTheHandCannotMakeIsRefused() {
        let (state, six) = conquestTurn(hand: [2, 5])
        var coordinator = BoardDecisionCoordinator()
        _ = coordinator.begin(.deployArmy, with: context(state))
        _ = coordinator.select(.tile(six))
        let result5 = coordinator.select(.armyCards([9]))
        #expect(!result5)
        let result6 = coordinator.select(.armyCards([2, 2]))
        #expect(!result6)
    }

    @Test func aStandardGameCannotBeginADeploy() {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310)
        state.phase = .mainTurn(playerIndex: 0)
        var coordinator = BoardDecisionCoordinator()
        let result7 = coordinator.begin(.deployArmy, with: context(state))
        #expect(!result7)
    }

    private func context(_ state: GameState, moveCount: Int = 7) -> BoardDecisionContext {
        BoardDecisionContext(matchID: matchID, committedMoveCount: moveCount, actor: actor, state: state)
    }

    private func paidBuildState() -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 47)
        let start = state.board.onBoardVertices.sorted().first!
        let first = state.board.edgesTouching(start).sorted().first!
        let middle = state.board.vertices(of: first)
        let middleVertex = middle.0 == start ? middle.1 : middle.0
        let second = state.board.edgesTouching(middleVertex).sorted().first { $0 != first }!
        state.players[actor.index].settlements.insert(start)
        state.players[actor.index].roads.formUnion([first, second])
        state.players[actor.index].resources = [.brick: 5, .lumber: 5, .wool: 5, .grain: 5, .ore: 5]
        state.phase = .mainTurn(playerIndex: actor.index)
        return state
    }

    private func roadBuildingState() -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 48)
        let start = state.board.onBoardVertices.sorted().first!
        state.players[actor.index].settlements.insert(start)
        state.players[actor.index].devCards = [.roadBuilding]
        state.phase = .rollDice(playerIndex: actor.index)
        return state
    }
}
