import CatanEngine
@testable import EmpiresOnline
import Foundation
import Testing

struct OnlineGameplayTests {
    private let host = PlayerID(index: 0)
    private let guest = PlayerID(index: 1)
    private let other = PlayerID(index: 2)

    @Test func actorScopeProtectsSetupAndTracksSnakeRound() throws {
        var game = try makeGame()
        for seat in [host, guest, other] {
            #expect(game.actors == [seat])
            #expect(game.turnOwner == seat)
            #expect(game.deadlineKind == .setup)
            #expect(game.actionScope == "settlement")
            let move = try #require(game.view(for: seat).legalMoves.first)
            let wrongSeat = seat == host ? guest : host
            #expect(game.view(for: wrongSeat).legalMoves.isEmpty)
            #expect(throws: OnlineGameplayError.notActing) { try game.apply(move, by: wrongSeat) }
            try game.apply(move, by: seat)
            #expect(game.actionScope == "road")
            #expect(game.turnGeneration == seat.index)
            try game.resolveTimeout(for: seat)
        }
        #expect(game.actors == [other])
        #expect(game.actionScope == "settlement")
        #expect(game.turnGeneration == 3)
        game = try reopened(game)
        #expect(game.turnGeneration == 3)
        #expect(game.actors == [other])
    }

    @Test func exactCardsAndHiddenPointsStayWithTheirSeat() throws {
        var state = seededState(variant: .conquest)
        state.phase = .mainTurn(playerIndex: host.index)
        deal([.brick: 2], to: host, in: &state)
        deal([.ore: 3], to: guest, in: &state)
        state.players[guest.index].devCards = [.victoryPoint]
        state.armyHands[guest] = [4]
        let game = try restored(state)
        let hostView = game.view(for: host)
        let guestView = game.view(for: guest)
        #expect(hostView.resources == [.brick: 2])
        #expect(hostView.devCards.isEmpty && hostView.armyCards.isEmpty)
        #expect(hostView.players[guest.index].resourceCount == 3)
        #expect(hostView.players[guest.index].devCardCount == 1)
        #expect(hostView.players[guest.index].armyCardCount == 1)
        #expect(hostView.players[guest.index].victoryPoints == 0)
        #expect(guestView.devCards == [.victoryPoint] && guestView.armyCards == [4])
        #expect(guestView.players[guest.index].victoryPoints == 1)
        let wire = try JSONEncoder().encode(hostView)
        let payload = try #require(try JSONSerialization.jsonObject(with: wire) as? [String: Any])
        #expect(payload["rng"] == nil && payload["devCardDeck"] == nil && payload["armyDeck"] == nil)
        #expect(payload["boardPresentationState"] == nil && payload["checkpoint"] == nil)
        #expect(hostView.boardPresentationState.players[guest.index].resources.isEmpty)
    }

    @Test func fogRemainsMaskedThroughRenderingAndRoundTrip() throws {
        let game = try makeGame(mode: .naval)
        let view = try reopened(game).view(for: host)
        #expect(view.board.tiles.contains { $0.kind == .fog })
        #expect(view.board.tiles.filter { $0.kind == .fog }.allSatisfy { $0.numberToken == nil })
        #expect(view.boardPresentationState.naval?.islandByHex.isEmpty == true)
        #expect(view.boardPresentationState.naval?.colonizedIslands.isEmpty == true)
        #expect(view.boardPresentationState.board == view.board)
        #expect(Naval.visibleBoard(in: view.boardPresentationState) == view.board)
    }

    @Test func directedTradeSurvivesRestartAndExpiresForNamedResponder() throws {
        var state = seededState()
        state.phase = .mainTurn(playerIndex: host.index)
        deal([.brick: 2], to: host, in: &state)
        deal([.ore: 2], to: guest, in: &state)
        var game = try restored(state)
        let offer = TradeOffer(from: host, recipient: guest, give: [.brick: 1], want: [.ore: 1])
        try game.apply(.proposeTrade(offer), by: host)
        game = try reopened(game)
        #expect(game.turnOwner == host)
        #expect(game.actors == [guest] && game.deadlineKind == .trade)
        #expect(game.view(for: host).tradeOffer == offer)
        #expect(game.view(for: guest).tradeOffer == offer)
        #expect(game.view(for: other).tradeOffer == nil)
        #expect(game.view(for: other).legalMoves.isEmpty)
        let accept = GameMove.respondToTrade(offerID: offer.id, accept: true)
        #expect(throws: OnlineGameplayError.notActing) { try game.apply(accept, by: other) }
        try game.resolveTimeout(for: guest)
        #expect(game.view(for: host).resources == [.brick: 2])
        #expect(game.actors == [host] && game.turnGeneration == 0)
        #expect(game.view(for: guest).tradeOffer == nil)
    }

    @Test func offTurnDiscardsHaveStableScopeAndRejectHostileQuantities() throws {
        var state = seededState()
        state.phase = .discarding(pending: [host, guest])
        state.robberMoverIndex = other.index
        deal([.brick: 8], to: host, in: &state)
        deal([.ore: 8], to: guest, in: &state)
        var game = try restored(state)
        #expect(game.acceptsIndependentResponses && game.actionScope == "discard")
        #expect(game.turnOwner == other && game.actors == [host, guest])
        #expect(game.view(for: host).discardCount == 4)
        #expect(game.view(for: host).legalMoves.isEmpty)
        #expect(game.view(for: other).discardCount == nil)
        let malicious = GameMove.discard([.brick: Int.max, .ore: Int.max])
        #expect(throws: OnlineGameplayError.illegalMove) { try game.apply(malicious, by: host) }
        try game.apply(.discard([.ore: 4]), by: guest)
        #expect(game.actors == [host] && game.actionScope == "discard")
        try game.resolveTimeout(for: host)
        #expect(game.actors == [other] && game.actionScope == "robber")
        #expect(game.view(for: host).resources == [.brick: 4])
    }

    @Test func replacingASeatPreservesProgressAndBotCanActAfterRestart() throws {
        var game = try makeGame()
        let settlement = try #require(game.view(for: host).legalMoves.first)
        try game.apply(settlement, by: host)
        try game.replaceWithBot(host)
        game = try reopened(game)
        #expect(throws: OnlineGameplayError.unexpectedBot) { try game.advanceBot(for: guest) }
        try game.advanceBot(for: host)
        #expect(game.actors == [guest] && game.turnGeneration == 1)
        let player = game.view(for: guest).players[host.index]
        #expect(player.settlements.count == 1 && player.roads.count == 1)
    }

    @Test func replacingAnExternalSeatAboveTheBotCapRemainsRestorable() throws {
        var state = seededState()
        state.phase = .mainTurn(playerIndex: host.index)
        deal([.brick: 1], to: host, in: &state)
        var session = GameSession(state: state, policies: [:], policySeed: 7)
        for _ in 0...GameSession.actionLimit(in: state) {
            let offer = TradeOffer(from: host, recipient: guest, give: [.brick: 1], want: [.ore: 1])
            try session.applyExternal(.proposeTrade(offer), by: host)
            try session.applyExternal(.respondToTrade(offerID: offer.id, accept: false), by: guest)
        }
        var game = try restored(session)
        try game.replaceWithBot(host)
        game = try reopened(game)
        try game.advanceBot(for: host)
        #expect(game.turnOwner == guest && game.turnGeneration == 1)
    }

    private func makeGame(mode: GameMode = .classic) throws -> OnlineGameplay {
        let configuration = OnlineConfiguration(pace: .timedLive, mode: mode, rules: .standard,
                                                aiSeats: [nil, nil, nil])
        let seats = (0..<3).map {
            OnlineSeat(role: .human, name: "Player \($0)", civilization: nil, ready: true, isYou: false)
        }
        return try OnlineGameplay(configuration: configuration, seats: seats)
    }

    private func seededState(variant: GameVariant = .standard) -> GameState {
        GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, playerCount: 3, variant: variant)
    }

    private func deal(_ cards: [Resource: Int], to seat: PlayerID, in state: inout GameState) {
        for (resource, amount) in cards {
            state.players[seat.index].resources[resource, default: 0] += amount
            state.bank[resource, default: 0] -= amount
        }
    }

    private func restored(_ state: GameState) throws -> OnlineGameplay {
        try restored(GameSession(state: state, policies: [:], policySeed: 7))
    }

    private func restored(_ session: GameSession) throws -> OnlineGameplay {
        let fixture = CheckpointFixture(checkpoint: session.checkpoint)
        return try JSONDecoder().decode(OnlineGameplay.self, from: JSONEncoder().encode(fixture))
    }

    private func reopened(_ gameplay: OnlineGameplay) throws -> OnlineGameplay {
        try JSONDecoder().decode(OnlineGameplay.self, from: JSONEncoder().encode(gameplay))
    }
}

private struct CheckpointFixture: Encodable {
    let version = 1
    let rulesVersion = RulesEngine.currentRulesVersion
    let roles: [OnlineSeatRole] = [.human, .human, .human]
    let turnGeneration = 0
    let checkpoint: GameSession.Checkpoint
}
