import Foundation
import Testing
@testable import CatanEngine

@Suite struct NavalSailingHistoryTests {
    @Test func aMissingVoyageOriginDecodesAsAbsent() throws {
        let ship = Ship(id: 0, owner: PlayerID(index: 0), coordinate: HexCoordinate(q: 3, r: 0))
        let encoded = try JSONEncoder().encode(ship)
        let fields = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(fields["previousSailingOrigin"] == nil)
        #expect(try JSONDecoder().decode(Ship.self, from: encoded) == ship)
    }

    @Test func thePublicOriginSurvivesSavingWithoutRestrictingHumanReturns() throws {
        var state = try position()
        let origin = try #require(state.naval?.ships.first?.coordinate)
        let ship = try #require(state.naval?.ships.first)
        let next = try #require(Naval.sailingDestinations(for: ship, in: state).first { origin.distance(to: $0) == 1 })
        try RulesEngine.apply(.sailShip(id: ship.id, to: next), by: ship.owner, to: &state)
        #expect(state.naval?.ships.first?.previousSailingOrigin == origin)
        let session = GameSession(state: state, policies: [:], policySeed: 7)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(session.checkpoint))
        let restored = try GameSession(checkpoint: decoded, policies: [:])
        #expect(restored.checkpoint == session.checkpoint)
        #expect(RulesEngine.legalMoves(for: state, seat: ship.owner).contains(.sailShip(id: ship.id, to: origin)))
        try RulesEngine.apply(.sailShip(id: ship.id, to: origin), by: ship.owner, to: &state)
        #expect(state.naval?.ships.first?.coordinate == origin && state.naval?.ships.first?.stepsRemaining == 0)
    }

    @Test func captureAndTheNextOwnerTurnClearTheVoyageOrigin() throws {
        var state = try position()
        let origin = try #require(state.naval?.ships.first?.coordinate)
        let next = try #require(Naval.sailingDestinations(for: state.naval!.ships[0], in: state).first { origin.distance(to: $0) == 1 })
        try RulesEngine.apply(.sailShip(id: 0, to: next), by: PlayerID(index: 0), to: &state)
        #expect(state.naval?.ships.first?.previousSailingOrigin == origin)
        try NavalTestSupport.roll(11, player: 1, state: &state)
        try RulesEngine.apply(.captureShip(id: 0), by: PlayerID(index: 1), to: &state)
        #expect(state.naval?.ships.first?.previousSailingOrigin == nil)
        state.naval?.ships[0].previousSailingOrigin = origin
        state.naval?.ships[0].stepsRemaining = 1
        Naval.beginTurn(for: PlayerID(index: 1), in: &state)
        #expect(state.naval?.ships.first?.previousSailingOrigin == nil && state.naval?.ships.first?.stepsRemaining == 2)
    }

    @Test(arguments: [1, 2, 3, 4])
    func legacyMovesNeverIntroduceVoyageHistory(version: Int) throws {
        var state = try position(version: version)
        let before = state
        let ship = try #require(state.naval?.ships.first)
        let next = try #require(Naval.sailingDestinations(for: ship, in: state).first { ship.coordinate.distance(to: $0) == 1 })
        let move = GameMove.sailShip(id: ship.id, to: next)
        let events = try RulesEngine.apply(move, by: ship.owner, to: &state)
        #expect(state.naval?.ships.first?.previousSailingOrigin == nil)
        var replay = before
        #expect(try RulesEngine.replay(move, by: ship.owner, rulesVersion: RulesEngine.currentRulesVersion, to: &replay) == events)
        #expect(replay == state)
    }

    @Test func aSettlementReleasesHistoryEvenBeyondTheColonyPointCap() throws {
        var state = try position()
        let seat = PlayerID(index: 0)
        state.naval?.colonyPoints[seat] = 2
        state.naval?.colonizedIslands[seat] = [1, 2]
        let site = try #require(Naval.potentialColonySites(for: seat, in: state).first { vertex in
            vertex.touchingTiles.contains { (state.naval?.islandByHex[$0] ?? 0) >= 3 }
        })
        let sea = try #require(site.touchingTiles.first { coordinate in state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea } })
        let previous = try #require((0..<6).map { sea.neighbor($0) }.first { coordinate in
            state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea }
        })
        state.naval?.ships[0].coordinate = previous
        try RulesEngine.apply(.sailShip(id: 0, to: sea), by: seat, to: &state)
        #expect(state.naval?.ships[0].previousSailingOrigin == previous)
        NavalTestSupport.fund(Building.settlementCost, in: &state)
        let events = try RulesEngine.apply(.buildSettlement(site), by: seat, to: &state)
        #expect(state.naval?.ships[0].previousSailingOrigin == nil)
        #expect(!events.contains { if case .earnedColonyPoint = $0 { return true }; return false })
        #expect(Naval.colonyPoints(for: seat, in: state) == 2)
    }

    @Test func aCityUpgradeRetainsTheVoyageHistory() throws {
        var state = try position()
        let origin = try #require(state.naval?.ships.first?.coordinate)
        let next = try #require(Naval.sailingDestinations(for: state.naval!.ships[0], in: state).first { origin.distance(to: $0) == 1 })
        try RulesEngine.apply(.sailShip(id: 0, to: next), by: PlayerID(index: 0), to: &state)
        let site = try #require(state.players[0].settlements.sorted().first)
        NavalTestSupport.fund(Building.cityCost, in: &state)
        try RulesEngine.apply(.buildCity(site), by: PlayerID(index: 0), to: &state)
        #expect(state.naval?.ships[0].previousSailingOrigin == origin)
    }

    @Test func realDiscoveryClearsTheObsoleteVoyageOrigin() throws {
        var state = try NavalTestSupport.ready(fog: true)
        let launch = try #require(Naval.launchSites(for: PlayerID(index: 0), in: state).first)
        NavalTestSupport.addShip(at: launch, player: 0, in: &state)
        let ship = try #require(state.naval?.ships.first)
        let next = try #require(Naval.sailingDestinations(for: ship, in: state).first { coordinate in
            launch.distance(to: coordinate) == 1 && state.board.tiles.contains { !state.naval!.revealed.contains($0.coordinate)
                && $0.coordinate.distance(to: coordinate) <= Naval.viewingRange }
        })
        let events = try RulesEngine.apply(.sailShip(id: 0, to: next), by: ship.owner, to: &state)
        #expect(events.contains { if case .discovered = $0 { return true }; return false })
        #expect(state.naval?.ships[0].previousSailingOrigin == nil)
    }

    @Test func impossibleHistoryFailsCheckpointValidation() throws {
        var state = try position()
        state.naval?.ships[0].previousSailingOrigin = HexCoordinate(q: 99, r: 99)
        state.naval?.ships[0].stepsRemaining = 1
        #expect(Naval.validationProblem(in: state) == "naval ship position/movement")
        #expect(throws: GameSession.CheckpointError.self) { try GameSession(state: state, policies: [:], policySeed: 7).checkpoint.validate() }
    }

    private func position(version: Int = 5) throws -> GameState {
        var state = try NavalTestSupport.ready(fog: false, rulesVersion: version)
        let launch = try #require(Naval.launchSites(for: PlayerID(index: 0), in: state).first)
        NavalTestSupport.addShip(at: launch, player: 0, in: &state)
        return state
    }
}
