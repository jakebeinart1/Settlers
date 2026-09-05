import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

@MainActor
@Suite(.serialized)
struct DevelopmentCardJourneyTests {
    @Test func committedPurchasePublishesBuyerPrivateReveal() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        seedPurchasableCard(.monopoly, in: model)

        try model.apply(.buyDevCard)

        #expect(model.pendingDevCardReveal
                == DevCardReveal(owner: model.humanPlayer, card: .monopoly))
        #expect(model.state.players[model.humanPlayer.index].devCards == [.monopoly])
        let resumed = fixture.makeModel()
        #expect(resumed.state == model.state,
                "the hand and bought-this-turn restriction must survive a cold resume")
        #expect(resumed.pendingDevCardReveal == model.pendingDevCardReveal,
                "an unread private purchase must still be revealed after relaunch")
    }

    @Test func failedPurchaseCommitPublishesNoRevealAndChangesNoHand() throws {
        let fixture = try CheckpointModelFixture()
        var refuseWrite = false
        let model = fixture.makeModel(atCommitStage: { stage in
            if refuseWrite, stage == .beforeReplace { throw CocoaError(.fileWriteNoPermission) }
        })
        seedPurchasableCard(.yearOfPlenty, in: model)
        let before = model.state
        refuseWrite = true

        #expect(throws: MatchPersistenceFailure.self) { try model.apply(.buyDevCard) }

        #expect(model.pendingDevCardReveal == nil)
        #expect(model.state == before)
    }

    @Test func dismissingRevealDoesNotChangeTheCommittedCard() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        seedPurchasableCard(.knight, in: model)
        try model.apply(.buyDevCard)
        let committed = model.state

        model.dismissDevCardReveal()

        #expect(model.pendingDevCardReveal == nil)
        #expect(model.state == committed)
        #expect(fixture.makeModel().pendingDevCardReveal == nil,
                "a dismissed reveal must not return on the next launch")
    }

    @Test func committedResolutionSurvivesUntilAcknowledged() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let human = PlayerID(index: 0)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 19, playerCount: 3)
        state.phase = .mainTurn(playerIndex: human.index)
        state.players[human.index].devCards = [.monopoly]
        state.players[1].resources = [.ore: 2]
        state.players[2].resources = [.ore: 1]
        model.replaceStateForTesting(state, humanSeat: human)
        model.isBlockingSurfaceOpen = true

        try model.apply(.playMonopoly(.ore))

        let expected = DevCardResolution.monopoly(owner: human, resource: .ore, gained: 3)
        #expect(model.pendingDevCardResolution == expected)
        #expect(fixture.makeModel().pendingDevCardResolution == expected)
        let committed = model.state

        #expect(model.dismissDevCardResolution())
        #expect(model.pendingDevCardResolution == nil)
        #expect(model.state == committed)
        #expect(fixture.makeModel().pendingDevCardResolution == nil)
    }

    @Test func zeroCardMonopolyStillProducesATruthfulResult() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let human = PlayerID(index: 0)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 21, playerCount: 3)
        state.phase = .rollDice(playerIndex: human.index)
        state.players[human.index].devCards = [.monopoly]
        model.replaceStateForTesting(state, humanSeat: human)
        model.isBlockingSurfaceOpen = true

        try model.apply(.playMonopoly(.wool))

        #expect(model.pendingDevCardResolution
                == .monopoly(owner: human, resource: .wool, gained: 0))
        #expect(model.state.phase == .rollDice(playerIndex: human.index),
                "playing before the roll must not skip the roll")
    }

    @Test func winningVictoryPointStillOwesItsPrivateReveal() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        seedWinningPurchase(in: model)

        try model.apply(.buyDevCard)

        #expect(model.state.phase == .gameOver(winner: model.humanPlayer))
        #expect(model.pendingDevCardReveal
                == DevCardReveal(owner: model.humanPlayer, card: .victoryPoint))
        #expect(fixture.makeModel().pendingDevCardReveal == model.pendingDevCardReveal,
                "the winning card must survive a cold resume before the standings replace it")
    }

    @Test func inventorySeparatesReadyNewAndPassiveCards() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let human = PlayerID(index: 0)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 23, playerCount: 3)
        state.phase = .mainTurn(playerIndex: human.index)
        state.players[human.index].devCards = [
            .knight, .knight, .roadBuilding, .victoryPoint,
        ]
        state.devCardsBoughtThisTurn[human] = [.knight, .roadBuilding]
        model.replaceStateForTesting(state, humanSeat: human)

        let inventory = DevCardInventoryItem.all(for: human, in: model.state)
        let knight = try #require(inventory.first(where: { $0.type == .knight }))
        let road = try #require(inventory.first(where: { $0.type == .roadBuilding }))
        let point = try #require(inventory.first(where: { $0.type == .victoryPoint }))

        #expect((knight.held, knight.ready, knight.boughtThisTurn, knight.status)
                == (2, 1, 1, .playable))
        #expect((road.held, road.ready, road.boughtThisTurn, road.status)
                == (1, 0, 1, .boughtThisTurn))
        #expect((point.held, point.ready, point.boughtThisTurn, point.status)
                == (1, 1, 0, .passiveVictoryPoint))
    }

    private func seedPurchasableCard(_ card: DevCardType, in model: GameViewModel) {
        let human = PlayerID(index: 0)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 91, playerCount: 3)
        state.phase = .mainTurn(playerIndex: human.index)
        state.players[human.index].resources = [.ore: 1, .wool: 1, .grain: 1]
        state.devCardDeck = [card]
        model.replaceStateForTesting(state, humanSeat: human)
        model.isBlockingSurfaceOpen = true
    }

    private func seedWinningPurchase(in model: GameViewModel) {
        let human = PlayerID(index: 0)
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 92, playerCount: 3)
        let vertices = state.board.onBoardVertices.sorted()
        state.phase = .mainTurn(playerIndex: human.index)
        state.players[human.index].cities = Set(vertices.prefix(3))
        state.players[human.index].settlements = Set(vertices.dropFirst(20).prefix(3))
        state.players[human.index].resources = [.ore: 1, .wool: 1, .grain: 1]
        state.devCardDeck = [.victoryPoint]
        model.replaceStateForTesting(state, humanSeat: human)
        model.isBlockingSurfaceOpen = true
    }
}
