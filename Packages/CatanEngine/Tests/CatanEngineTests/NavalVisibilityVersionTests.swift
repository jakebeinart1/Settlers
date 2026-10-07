import Foundation
import Testing
@testable import CatanEngine

struct NavalVisibilityVersionTests {
    private let corner = HexGeometry.corner(of: HexCoordinate(q: 2, r: 0), between: 4)
    private let legacySea: Set<HexCoordinate> = [
        HexCoordinate(q: -1, r: 3), HexCoordinate(q: 0, r: 3),
        HexCoordinate(q: 1, r: 2), HexCoordinate(q: 1, r: 3),
        HexCoordinate(q: 2, r: 1), HexCoordinate(q: 2, r: 2),
        HexCoordinate(q: 3, r: -2), HexCoordinate(q: 3, r: -1), HexCoordinate(q: 3, r: 0), HexCoordinate(q: 3, r: 1),
        HexCoordinate(q: 4, r: -2), HexCoordinate(q: 4, r: -1), HexCoordinate(q: 4, r: 0)
    ]
    private let cornerSea: Set<HexCoordinate> = [
        HexCoordinate(q: 1, r: 2), HexCoordinate(q: 2, r: 1), HexCoordinate(q: 2, r: 2),
        HexCoordinate(q: 3, r: -1), HexCoordinate(q: 3, r: 0), HexCoordinate(q: 3, r: 1)
    ]

    @Test func newGamesUseCornerVisionWithoutChangingOpeningMapOrEngineVersions() throws {
        var state = Naval.newGame(seed: 19)
        let opening = Set(BoardGenerator.spiralCoordinates(radius: 2))
        #expect(state.naval?.rulesVersion == 4)
        #expect(state.naval?.mapVersion == 1)
        #expect(state.schemaVersion == 6)
        #expect(RulesEngine.currentRulesVersion == 3)
        #expect(state.naval?.revealed == opening)
        #expect(RulesEngine.legalMoves(for: state).contains(.placeInitialSettlement(corner)))
        let events = try RulesEngine.apply(.placeInitialSettlement(corner), by: state.players[0].id, to: &state)
        #expect(state.naval?.revealed == opening.union(cornerSea))
        #expect(state.naval?.revealed.count == 25)
        #expect(events.last == .discovered(state.players[0].id, hexes: cornerSea.sorted()))
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test(arguments: 1...3)
    func legacyNavalOneReplaysItsOriginalExactRevealUnderEveryEngineVersion(engineVersion: Int) throws {
        var state = Naval.newGame(seed: 19)
        state.naval?.rulesVersion = 1
        let opening = state
        let player = state.players[0].id
        let events = try RulesEngine.apply(.placeInitialSettlement(corner), by: player, to: &state)
        let home = Set(BoardGenerator.spiralCoordinates(radius: 2))
        #expect(state.naval?.revealed == home.union(legacySea))
        #expect(state.naval?.revealed.count == 32)
        #expect(events.last == .discovered(player, hexes: legacySea.sorted()))
        var replay = opening
        #expect(try RulesEngine.replay(.placeInitialSettlement(corner), by: player, rulesVersion: engineVersion, to: &replay) == events)
        #expect(replay == state)
        #expect(Naval.validationProblem(in: replay) == nil)
    }

    @Test(arguments: [1, 2, 3, 4])
    func coldCheckpointKeepsItsVisionRuleAndPreviouslyDiscoveredTiles(version: Int) throws {
        var state = Naval.newGame(seed: 19)
        state.naval?.rulesVersion = version
        try RulesEngine.apply(.placeInitialSettlement(corner), by: state.players[0].id, to: &state)
        let known = state.naval!.revealed
        var original = GameSession(state: state, policies: [:], policySeed: 71)
        let encoded = try JSONEncoder().encode(original.checkpoint)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: encoded)
        try decoded.validate()
        var resumed = try GameSession(checkpoint: decoded, policies: [:])
        #expect(resumed.checkpoint == original.checkpoint)
        #expect(resumed.state.naval?.rulesVersion == version)
        let road = try #require(RulesEngine.legalMoves(for: state).first)
        let a = try original.applyExternal(road, by: state.players[0].id)
        let b = try resumed.applyExternal(road, by: state.players[0].id)
        #expect(a.actor == b.actor && a.move == b.move && a.events == b.events && a.privateEvents == b.privateEvents)
        #expect(original.checkpoint == resumed.checkpoint)
        #expect(known.isSubset(of: resumed.state.naval!.revealed))
        let nextPlacement = try #require(RulesEngine.legalMoves(for: original.state).first)
        let nextPlayer = original.state.players[1].id
        let nextA = try original.applyExternal(nextPlacement, by: nextPlayer)
        let nextB = try resumed.applyExternal(nextPlacement, by: nextPlayer)
        #expect(nextA.events == nextB.events)
        #expect(original.checkpoint == resumed.checkpoint)
        #expect(known.isSubset(of: resumed.state.naval!.revealed))
    }

    @Test func aMissingNavalVersionAlwaysDecodesAsLegacyOneWithoutRefogging() throws {
        var state = Naval.newGame(seed: 19)
        state.naval?.rulesVersion = 1
        try RulesEngine.apply(.placeInitialSettlement(corner), by: state.players[0].id, to: &state)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var naval = try #require(object["naval"] as? [String: Any])
        naval.removeValue(forKey: "rulesVersion")
        object["naval"] = naval
        let restored = try JSONDecoder().decode(GameState.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored == state)
        #expect(restored.naval?.rulesVersion == 1)
        #expect(restored.naval?.revealed.count == 32)
        try GameSession(state: restored, policies: [:], policySeed: 71).checkpoint.validate()
    }

    @Test(arguments: [1, 2, 3, 4])
    func fogDisabledRetainsTheEntireWorldUnderEitherVisionRule(version: Int) throws {
        var state = Naval.newGame(seed: 19, options: NavalOptions(fogEnabled: false))
        state.naval?.rulesVersion = version
        let revealed = state.naval!.revealed
        let events = try RulesEngine.apply(.placeInitialSettlement(corner), by: state.players[0].id, to: &state)
        #expect(revealed.count == 169)
        #expect(state.naval?.revealed == revealed)
        #expect(events == [.placedInitialSettlement(state.players[0].id)])
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test(arguments: [0, 5, 999])
    func unsupportedNavalVisionVersionsRemainRejected(version: Int) {
        var state = Naval.newGame(seed: 19)
        state.naval?.rulesVersion = version
        #expect(Naval.validationProblem(in: state) == "naval mode/version")
    }
}
