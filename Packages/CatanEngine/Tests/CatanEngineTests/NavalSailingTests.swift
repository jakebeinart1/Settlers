import Foundation
import Testing
@testable import CatanEngine

struct NavalSailingTests {
    private let origin = HexCoordinate(q: 3, r: 0)
    private let destination = HexCoordinate(q: 4, r: 1)
    private let intermediate = HexCoordinate(q: 3, r: 1)
    private let owner = PlayerID(index: 0)

    @Test func twoHexVoyageUsesCanonicalRouteAndRevealsIntermediateSight() throws {
        var state = seaPosition()
        let before = state
        let ship = try #require(state.naval?.ships.first)
        let route = try #require(Naval.sailingRoute(for: ship, to: destination, in: state))
        #expect(route == [intermediate, destination])
        let passedSight = HexCoordinate(q: 1, r: 3)
        #expect(!before.naval!.revealed.contains(passedSight))
        #expect(passedSight.distance(to: destination) > Naval.viewingRange)
        let events = try RulesEngine.apply(.sailShip(id: ship.id, to: destination), by: owner, to: &state)
        let discoveries = state.board.tiles.map(\.coordinate).filter { coordinate in
            !before.naval!.revealed.contains(coordinate) && route.contains { coordinate.distance(to: $0) <= Naval.viewingRange }
        }.sorted()
        #expect(events == [.sailedShip(owner, shipID: 0, from: origin, to: destination), .discovered(owner, hexes: discoveries)])
        #expect(state.naval?.ships[0].coordinate == destination && state.naval?.ships[0].stepsRemaining == 0)
        #expect(state.naval!.revealed.contains(passedSight))
        #expect(state.rng == before.rng)
        var replay = before
        #expect(try RulesEngine.replay(.sailShip(id: 0, to: destination), by: owner,
                                      rulesVersion: RulesEngine.currentRulesVersion, to: &replay) == events)
        #expect(replay == state)
    }

    @Test func oneHexVoyageRetainsOneHexAndCannotThenReachTwo() throws {
        var state = seaPosition()
        try RulesEngine.apply(.sailShip(id: 0, to: intermediate), by: owner, to: &state)
        let ship = try #require(state.naval?.ships.first)
        #expect(ship.stepsRemaining == 1)
        let destinations = Naval.sailingDestinations(for: ship, in: state)
        #expect(destinations == destinations.sorted())
        #expect(destinations.allSatisfy { ship.coordinate.distance(to: $0) == 1 })
        #expect(!destinations.contains(ship.coordinate))
        #expect(Naval.sailingRoute(for: ship, to: HexCoordinate(q: 5, r: 1), in: state) == nil)
    }

    @Test func geometricRangeCannotCrossKnownLand() throws {
        var state = seaPosition()
        replace([intermediate, HexCoordinate(q: 4, r: 0)], with: .resource(.grain), in: &state)
        let before = state
        let ship = try #require(state.naval?.ships.first)
        #expect(origin.distance(to: destination) == 2)
        #expect(!Naval.sailingDestinations(for: ship, in: state).contains(destination))
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.sailShip(id: 0, to: destination), by: owner, to: &state)
        }
        #expect(state == before)
    }

    @Test func concealedKindsCannotChangeRecomputedRoutesMasksOrObservations() throws {
        let baseline = seaPosition()
        let ship = try #require(baseline.naval?.ships.first)
        let moves = RulesEngine.legalMoves(for: baseline, seat: owner)
        let observation = GameObservation(seat: owner, state: baseline, legalMoves: moves)
        let hidden = Set(baseline.board.tiles.map(\.coordinate)).subtracting(baseline.naval!.revealed)
        for kind in [TileKind.sea, .resource(.ore), .resourceChoice] {
            var changed = baseline
            replace(hidden, with: kind, in: &changed)
            let recomputed = RulesEngine.legalMoves(for: changed, seat: owner)
            #expect(recomputed == moves)
            #expect(GameObservation(seat: owner, state: changed, legalMoves: recomputed) == observation)
            #expect(Naval.sailingDestinations(for: ship, in: changed) == Naval.sailingDestinations(for: ship, in: baseline))
            #expect(Naval.sailingRoute(for: ship, to: destination, in: changed) == [intermediate, destination])
        }
    }

    @Test(arguments: [0, 1, 2, 3])
    func invalidDestinationsLeaveMovementFogAndRandomnessUnchanged(target: Int) throws {
        var state = seaPosition()
        let targets = [origin, HexCoordinate(q: 6, r: 0), HexCoordinate(q: 8, r: 0), intermediate]
        if target == 3 { replace([intermediate], with: .resource(.grain), in: &state) }
        let before = state
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.sailShip(id: 0, to: targets[target]), by: owner, to: &state)
        }
        #expect(state == before)
    }

    @Test(arguments: [1, 2, 3, 4])
    func savedAllowanceSurvivesPurchaseSailingCaptureAndTurnRefresh(version: Int) throws {
        var state = try NavalTestSupport.ready(fog: false, rulesVersion: version)
        let allowance = version < 3 ? 3 : 2
        NavalTestSupport.fund(Naval.shipCost, in: &state)
        let launch = try #require(Naval.launchSites(for: owner, in: state).first)
        try RulesEngine.apply(.buildShip(at: launch), by: owner, to: &state)
        #expect(state.naval?.ships[0].stepsRemaining == allowance)
        let ship = try #require(state.naval?.ships.first)
        let adjacent = try #require(Naval.sailingDestinations(for: ship, in: state).first { launch.distance(to: $0) == 1 })
        try RulesEngine.apply(.sailShip(id: 0, to: adjacent), by: owner, to: &state)
        #expect(state.naval?.ships[0].stepsRemaining == allowance - 1)
        let original = GameSession(state: state, policies: [:], policySeed: 7)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(original.checkpoint))
        let resumed = try GameSession(checkpoint: decoded, policies: [:])
        #expect(resumed.checkpoint == original.checkpoint && resumed.state.naval?.rulesVersion == version)
        try NavalTestSupport.roll(11, player: 1, state: &state)
        try RulesEngine.apply(.captureShip(id: 0), by: PlayerID(index: 1), to: &state)
        #expect(state.naval?.ships[0].stepsRemaining == allowance)
        state.naval?.ships[0].stepsRemaining = 0
        Naval.beginTurn(for: PlayerID(index: 1), in: &state)
        #expect(state.naval?.ships[0].stepsRemaining == allowance)
        #expect(Naval.validationProblem(in: state) == nil)
        #expect(GameSession.actionLimit(in: state) == 25 + 6 * state.players.count * (allowance + 1))
    }

    @Test(arguments: [1, 2])
    func legacySailingReplaysThreeOriginalAdjacentActions(version: Int) throws {
        var state = seaPosition(version: version)
        let initial = state
        var transcript: [(GameMove, [GameEvent])] = []
        for remaining in stride(from: 2, through: 0, by: -1) {
            let ship = try #require(state.naval?.ships.first)
            let destinations = Naval.sailingDestinations(for: ship, in: state)
            #expect(destinations.allSatisfy { ship.coordinate.distance(to: $0) == 1 })
            let move = GameMove.sailShip(id: 0, to: try #require(destinations.last))
            transcript.append((move, try RulesEngine.apply(move, by: owner, to: &state)))
            #expect(state.naval?.ships[0].stepsRemaining == remaining)
        }
        var replay = initial
        for (move, events) in transcript {
            #expect(try RulesEngine.replay(move, by: owner, rulesVersion: 3, to: &replay) == events)
        }
        #expect(replay == state && Naval.sailingDestinations(for: state.naval!.ships[0], in: state).isEmpty)
    }

    @Test func aCommittedTwoHexVoyageSurvivesColdCheckpointAndContinuesExactly() throws {
        var state = try NavalTestSupport.ready()
        NavalTestSupport.fund(Naval.shipCost, in: &state)
        let launch = try #require(Naval.launchSites(for: owner, in: state).first)
        try RulesEngine.apply(.buildShip(at: launch), by: owner, to: &state)
        let ship = try #require(state.naval?.ships.first)
        let target = try #require(Naval.sailingDestinations(for: ship, in: state).first {
            Naval.sailingRoute(for: ship, to: $0, in: state)?.count == 2
        })
        var original = GameSession(state: state, policies: [:], policySeed: 77)
        let voyage = try original.applyExternal(.sailShip(id: ship.id, to: target), by: owner)
        var replay = state
        #expect(try RulesEngine.replay(voyage.move, by: owner, rulesVersion: 3, to: &replay) == voyage.events)
        #expect(replay == original.state && replay.naval?.ships[0].stepsRemaining == 0)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(original.checkpoint))
        var resumed = try GameSession(checkpoint: decoded, policies: [:])
        #expect(resumed.checkpoint == original.checkpoint)
        let first = try original.applyExternal(.endTurn, by: owner)
        let second = try resumed.applyExternal(.endTurn, by: owner)
        #expect(first.events == second.events && original.checkpoint == resumed.checkpoint)
    }

    @Test(arguments: [1, 2, 3, 4])
    func validationRetainsThreeRemainingOnlyForLegacyMatches(version: Int) throws {
        var state = try NavalTestSupport.ready(rulesVersion: version)
        let launch = try #require(Naval.launchSites(for: owner, in: state).first)
        NavalTestSupport.addShip(at: launch, player: 0, steps: 3, in: &state)
        if version >= Naval.destinationSailingRulesVersion {
            #expect(Naval.validationProblem(in: state) == "naval ship position/movement")
        } else {
            #expect(Naval.validationProblem(in: state) == nil)
            let original = GameSession(state: state, policies: [:], policySeed: 7).checkpoint
            let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(original))
            try decoded.validate()
            #expect(decoded == original && decoded.state.naval?.ships[0].stepsRemaining == 3)
        }
    }

    /// A small public sea graph inside the unchanged world envelope isolates route geometry.
    private func seaPosition(version: Int = 3) -> GameState {
        var state = Naval.newGame(seed: 73)
        state.naval?.rulesVersion = version
        replace(Set(state.board.tiles.map(\.coordinate)), with: .sea, in: &state)
        state.phase = .mainTurn(playerIndex: 0)
        state.naval?.revealed = Set(state.board.tiles.filter {
            $0.coordinate.distance(to: origin) <= Naval.viewingRange
                || $0.coordinate.distance(to: HexCoordinate(q: 0, r: 0)) <= Naval.homeRadius
        }.map(\.coordinate))
        NavalTestSupport.addShip(at: origin, player: 0, in: &state)
        return state
    }

    private func replace(_ coordinates: Set<HexCoordinate>, with kind: TileKind, in state: inout GameState) {
        let tiles = state.board.tiles.map {
            coordinates.contains($0.coordinate) ? Tile(coordinate: $0.coordinate, kind: kind, numberToken: nil) : $0
        }
        state.board = Board(tiles: tiles, ports: [], onBoardVertices: [], onBoardEdges: [], robberTile: state.board.robberTile)
    }
}
