import Foundation
import Testing
@testable import CatanEngine

struct NavalObservationTests {
    @Test func observationsMaskGeographyAndPrivateCardsWithoutLosingPublicCounts() throws {
        var state = try NavalTestSupport.ready()
        state.players[0].devCards = [.monopoly]
        state.players[1].devCards = [.victoryPoint, .knight]
        NavalTestSupport.fund([.ore: 2], player: 1, in: &state)
        let observation = GameObservation(seat: state.players[0].id, state: state, legalMoves: RulesEngine.legalMoves(for: state))
        #expect(observation.state.players[0].resources == state.players[0].resources)
        #expect(observation.state.players[0].devCards == [.monopoly])
        #expect(observation.state.players[1].resources.isEmpty)
        #expect(observation.state.players[1].devCards.isEmpty)
        #expect(observation.devCardCounts[state.players[1].id] == 2)
        #expect(observation.handCounts[state.players[1].id] == state.players[1].resources.values.reduce(0, +))
        #expect(observation.devCardDeckCount == 50)
        #expect(observation.state.devCardDeck.isEmpty)
        #expect(observation.state.rng == RandomSource(seed: 0))
        #expect(observation.state.naval?.islandByHex.isEmpty == true)
        #expect(observation.state.naval?.colonizedIslands.isEmpty == true)
        for tile in observation.state.board.tiles {
            #expect((tile.kind == .fog) == !state.naval!.revealed.contains(tile.coordinate))
            if tile.kind == .fog { #expect(tile.numberToken == nil) }
        }
        let known = Set(observation.state.board.tiles.filter { $0.kind.isLand }.map(\.coordinate))
        #expect(observation.state.board.onBoardVertices.allSatisfy { $0.touchingTiles.contains(where: known.contains) })
        let restored = try JSONDecoder().decode(GameObservation.self, from: JSONEncoder().encode(observation))
        #expect(restored == observation)
    }

    @Test func unobservedWorldAndFutureRandomnessDoNotChangeAnObservation() throws {
        var state = try NavalTestSupport.ready()
        let seat = state.players[0].id
        let moves = RulesEngine.legalMoves(for: state)
        let baseline = GameObservation(seat: seat, state: state, legalMoves: moves)
        state.rng = RandomSource(seed: 999_999)
        state.devCardDeck.reverse()
        state.players[1].resources = [.brick: state.players[1].resources.values.reduce(0, +)]
        state.players[1].devCards = state.players[1].devCards.map { _ in .monopoly }
        state.naval?.mapFamily = .twinIslands
        state.naval?.generationAttempts = 64
        state.naval?.usedFallback = true
        state.naval?.islandByHex = [:]
        let changed = state.board.tiles.map { tile in
            state.naval!.revealed.contains(tile.coordinate) ? tile : Tile(coordinate: tile.coordinate, kind: .resource(.ore), numberToken: 6)
        }
        state.board = Board(tiles: changed, ports: state.board.ports, onBoardVertices: state.board.onBoardVertices,
                            onBoardEdges: state.board.onBoardEdges, robberTile: state.board.robberTile)
        let altered = GameObservation(seat: seat, state: state, legalMoves: moves)
        #expect(altered == baseline)
    }

    @Test(arguments: [true, false], [true, false])
    func decodedRawInputMasksAndKeepsCounts(fog: Bool, flexible: Bool) throws {
        var state = Naval.newGame(seed: 61, options: NavalOptions(fogEnabled: fog, resourceChoiceEnabled: flexible))
        state.players[1].resources = [.ore: 3]
        state.players[1].devCards = [.victoryPoint, .knight]
        let expected = GameObservation(seat: state.players[0].id, state: state, legalMoves: [.endTurn])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(expected)) as? [String: Any])
        object["state"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state))
        for key in ["handCounts", "devCardCounts", "devCardDeckCount"] { object.removeValue(forKey: key) }
        let decoded = try JSONDecoder().decode(GameObservation.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == expected)
    }

    @Test(arguments: [true, false], [true, false])
    func responseOnlyInformationDoesNotExposePrivateComposition(fog: Bool, flexible: Bool) throws {
        var state = Naval.newGame(seed: 62, options: NavalOptions(fogEnabled: fog, resourceChoiceEnabled: flexible))
        state.phase = .mainTurn(playerIndex: 0)
        NavalTestSupport.fund([.brick: 2], in: &state)
        NavalTestSupport.fund([.grain: 3], player: 1, in: &state)
        NavalTestSupport.fund([.ore: 2], player: 2, in: &state)
        let offer = TradeOffer(from: state.players[0].id, give: [.brick: 1], want: [.grain: 1])
        state.pendingTradeOffers = [offer]
        let responder = state.players[1].id
        let moves: [GameMove] = [.respondToTrade(offerID: offer.id, accept: true), .respondToTrade(offerID: offer.id, accept: false)]
        let before = GameObservation(seat: responder, state: state, legalMoves: moves)
        state.players[0].resources = [.brick: 1, .ore: 1]
        state.players[2].resources = [.brick: 1, .ore: 1]
        state.rng = RandomSource(seed: 8)
        state.devCardDeck.reverse()
        #expect(Trading.bothSidesCanHonour(offer, responder: responder, state: state))
        #expect(GameObservation(seat: responder, state: state, legalMoves: moves) == before)
    }

    @Test func publicTranscriptHidesUninvolvedTheftIdentity() {
        let event = GameEvent.movedRobber(PlayerID(index: 0), from: PlayerID(index: 1), stealing: .ore)
        #expect(event.masked(for: PlayerID(index: 2)) == .movedRobber(PlayerID(index: 0), from: PlayerID(index: 1), stealing: nil))
        #expect(event.masked(for: PlayerID(index: 0)) == event)
        #expect(event.masked(for: PlayerID(index: 1)) == event)
    }
}
