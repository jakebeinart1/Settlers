import Foundation
import Testing
@testable import CatanEngine

private struct NavalFirstLegalPolicy: Policy {
    let id = "naval-save-first-legal"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove { observation.legalMoves[0] }
}

struct NavalSaveTests {
    @Test func allNewFieldsDecodeDefaultsAndOldModesKeepNilNavalState() throws {
        let state = Naval.newGame(seed: 19)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state.naval)) as? [String: Any])
        for key in object.keys {
            var trimmed = object
            trimmed.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: trimmed)
            #expect(throws: Never.self) { _ = try JSONDecoder().decode(NavalState.self, from: data) }
        }
        let legacy = GameSetup.newGame(board: BoardGenerator.standard(), seed: 19)
        var legacyObject = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        legacyObject.removeValue(forKey: "naval")
        let restored = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        #expect(restored.naval == nil)
        #expect(Naval.validationProblem(in: restored) == nil)
    }

    @Test(arguments: [3, 4])
    func decodedCheckpointContinuesIdenticalTranscriptAndLedger(table: Int) throws {
        let state = Naval.newGame(seed: 93, playerCount: table)
        let policies = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, NavalFirstLegalPolicy() as any Policy) })
        var original = GameSession(state: state, policies: policies, policySeed: 1)
        for _ in 0..<40 { _ = try original.step() }
        let data = try JSONEncoder().encode(original.checkpoint)
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: data)
        var restored = try GameSession(checkpoint: checkpoint, policies: policies)
        for _ in 0..<60 {
            let a = try original.step()
            let b = try restored.step()
            #expect(a?.actor == b?.actor && a?.move == b?.move && a?.events == b?.events)
            #expect(original.checkpoint == restored.checkpoint)
        }
    }

    @Test(arguments: ["nil", "rulesVersion", "mapVersion", "unknownReveal", "duplicateShip", "shipLand", "shipSteps",
                      "shipOwner", "stock", "score", "topology", "choice", "garrison", "armyDeck", "armyHand"])
    func corruptNavalAuthoritativeStateIsRejected(corruption: String) throws {
        var state = try NavalTestSupport.ready()
        let launch = try #require(Naval.launchSites(for: state.players[0].id, in: state).first)
        NavalTestSupport.addShip(at: launch, player: 0, in: &state)
        let firstShip = state.naval!.ships[0]
        switch corruption {
        case "nil": state.naval = nil
        case "rulesVersion": state.naval?.rulesVersion = 999
        case "mapVersion": state.naval?.mapVersion = 999
        case "unknownReveal": state.naval?.revealed.insert(HexCoordinate(q: 99, r: 99))
        case "duplicateShip": state.naval?.ships.append(firstShip)
        case "shipLand": state.naval?.ships[0].coordinate = HexCoordinate(q: 0, r: 0)
        case "shipSteps": state.naval?.ships[0].stepsRemaining = 4
        case "shipOwner": state.naval?.ships[0].owner = PlayerID(index: 9)
        case "stock": state.naval?.hullsBuilt[state.players[0].id] = 7
        case "score": state.naval?.colonyPoints[state.players[0].id] = 3
        case "topology": state.board = Board(tiles: state.board.tiles, ports: state.board.ports,
                                              onBoardVertices: [], onBoardEdges: [], robberTile: state.board.robberTile)
        case "garrison": state.garrisons[state.board.robberTile] = Garrison(owner: state.players[0].id, strength: 3)
        case "armyDeck": state.armyDeck = [3]
        case "armyHand": state.armyHands[state.players[0].id] = [3]
        default: state.phase = .choosingResource(playerIndex: 0)
        }
        let checkpoint = GameSession(state: state, policies: [:], policySeed: 1).checkpoint
        #expect(throws: GameSession.CheckpointError.self) { try checkpoint.validate() }
    }

    @Test func malformedMaximumShipIDCanDecodeAndBeRejectedWithoutOverflow() throws {
        let naval = NavalState(ships: [Ship(id: Int.max, owner: PlayerID(index: 0), coordinate: HexCoordinate(q: 3, r: 0))])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(naval)) as? [String: Any])
        object.removeValue(forKey: "nextShipID")
        let restored = try JSONDecoder().decode(NavalState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.nextShipID == Int.max)
        var state = Naval.newGame(seed: 73)
        state.naval = restored
        #expect(Naval.validationProblem(in: state) != nil)
    }

    @Test func queuedNavalTradeResponseUsesMaskedSnapshotAndValidatesCounts() throws {
        var state = try NavalTestSupport.ready()
        NavalTestSupport.fund([.brick: 1], in: &state)
        NavalTestSupport.fund([.grain: 1], player: 1, in: &state)
        let policies: [PlayerID: any Policy] = [state.players[1].id: NavalFirstLegalPolicy()]
        var session = GameSession(state: state, policies: policies, policySeed: 1)
        let offer = TradeOffer(from: state.players[0].id, give: [.brick: 1], want: [.grain: 1])
        _ = try session.commit(seat: state.players[0].id, move: .proposeTrade(offer))
        let restored = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(session.checkpoint))
        try restored.validate()
        var resumed = try GameSession(checkpoint: restored, policies: policies)
        let a = try session.step()
        let b = try resumed.step()
        #expect(a?.actor == b?.actor && a?.move == b?.move && a?.events == b?.events)
        #expect(session.checkpoint == resumed.checkpoint)
    }
}
