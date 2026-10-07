import Foundation
import Testing
@testable import CatanEngine

struct NavalBlockadeTests {
    private let origin = HexCoordinate(q: 3, r: 0)
    private let intermediate = HexCoordinate(q: 3, r: 1)
    private let alternative = HexCoordinate(q: 4, r: 0)
    private let destination = HexCoordinate(q: 4, r: 1)
    private let owner = PlayerID(index: 0)

    @Test func enemyDestinationIsUnavailableAndRejectedWithoutMutation() throws {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        let before = state
        let ship = try #require(state.naval?.ships.first)
        #expect(!Naval.sailingDestinations(for: ship, in: state).contains(intermediate))
        #expect(!RulesEngine.legalMoves(for: state).contains(.sailShip(id: ship.id, to: intermediate)))
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.sailShip(id: ship.id, to: intermediate), by: owner, to: &state)
        }
        #expect(state == before)
    }

    @Test func enemyIntermediateCannotBeCrossedInATwoHexVoyage() throws {
        var state = seaPosition()
        replace([alternative], with: .resource(.ore), in: &state)
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        let before = state
        let ship = try #require(state.naval?.ships.first)
        #expect(origin.distance(to: destination) == 2)
        #expect(Naval.sailingRoute(for: ship, to: destination, in: state) == nil)
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.sailShip(id: ship.id, to: destination), by: owner, to: &state)
        }
        #expect(state == before)
    }

    @Test func alternateRouteUsesItsActualCostSightAndStableEvents() throws {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        let before = state
        let ship = try #require(state.naval?.ships.first)
        let route = [alternative, destination]
        let passedSight = HexCoordinate(q: 6, r: -2)
        #expect(!before.naval!.revealed.contains(passedSight))
        #expect(passedSight.distance(to: destination) > Naval.viewingRange)
        #expect(Naval.sailingRoute(for: ship, to: destination, in: state) == route)
        let events = try RulesEngine.apply(.sailShip(id: ship.id, to: destination), by: owner, to: &state)
        let discovered = before.board.tiles.map(\.coordinate).filter { coordinate in
            !before.naval!.revealed.contains(coordinate) && route.contains { coordinate.distance(to: $0) <= Naval.viewingRange }
        }.sorted()
        #expect(events == [.sailedShip(owner, shipID: ship.id, from: origin, to: destination), .discovered(owner, hexes: discovered)])
        #expect(state.naval?.ships[0].stepsRemaining == 0)
        #expect(state.naval!.revealed.contains(passedSight) && state.rng == before.rng)
        var replay = before
        #expect(try RulesEngine.replay(.sailShip(id: ship.id, to: destination), by: owner,
                                      rulesVersion: RulesEngine.currentRulesVersion, to: &replay) == events)
        #expect(replay == state)
    }

    @Test func blockadeDetourBeyondRemainingAllowanceIsUnavailable() throws {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        NavalTestSupport.addShip(at: alternative, player: 2, in: &state)
        let ship = try #require(state.naval?.ships.first)
        #expect(Naval.sailingRoute(for: ship, to: destination, in: state) == nil)
        #expect(!Naval.sailingDestinations(for: ship, in: state).contains(destination))
        let before = state
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.sailShip(id: ship.id, to: destination), by: owner, to: &state)
        }
        #expect(state == before)
    }

    @Test func friendlyShipsAllowEntryAndPassage() throws {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 0, in: &state)
        NavalTestSupport.addShip(at: destination, player: 0, in: &state)
        let ship = try #require(state.naval?.ships.first)
        #expect(!Naval.isBlockaded(intermediate, by: owner, in: state))
        #expect(Naval.sailingRoute(for: ship, to: destination, in: state) == [intermediate, destination])
        try RulesEngine.apply(.sailShip(id: ship.id, to: destination), by: owner, to: &state)
        #expect(state.naval?.ships.filter { $0.coordinate == destination && $0.owner == owner }.count == 2)
    }

    @Test func launchCannotBypassEnemyButFriendlyStackingStillPaysNormally() throws {
        var state = try NavalTestSupport.ready()
        NavalTestSupport.fund(Naval.shipCost, in: &state)
        let launches = Naval.launchSites(for: owner, in: state)
        let launch = try #require(launches.first)
        NavalTestSupport.addShip(at: launch, player: 1, steps: 0, in: &state)
        #expect(Naval.launchSites(for: owner, in: state) == launches.filter { $0 != launch })
        #expect(Naval.blockadedLaunchSites(for: owner, in: state) == [launch])
        #expect(!RulesEngine.legalMoves(for: state).contains(.buildShip(at: launch)))
        let before = state
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.buildShip(at: launch), by: owner, to: &state)
        }
        #expect(state == before)
        try NavalTestSupport.roll(11, player: owner.index, state: &state)
        try RulesEngine.apply(.captureShip(id: 0), by: owner, to: &state)
        #expect(Naval.blockadedLaunchSites(for: owner, in: state).isEmpty)
        #expect(Naval.launchSites(for: owner, in: state).contains(launch))
        let hand = state.players[0].resources
        try RulesEngine.apply(.buildShip(at: launch), by: owner, to: &state)
        #expect(state.naval?.ships.filter { $0.coordinate == launch && $0.owner == owner }.count == 2)
        for resource in Resource.allCases {
            #expect(state.players[0].resources[resource, default: 0] == hand[resource, default: 0] - Naval.shipCost[resource, default: 0])
        }
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test func blockedLaunchReasonsUseTheSameHullSupplyAndCoastCandidates() throws {
        var state = try NavalTestSupport.ready()
        let launch = try #require(Naval.launchSites(for: owner, in: state).first)
        let remote = try #require(state.board.tiles.last { $0.kind == .sea && $0.coordinate != launch }?.coordinate)
        NavalTestSupport.addShip(at: launch, player: 1, in: &state)
        NavalTestSupport.addShip(at: remote, player: 1, in: &state)
        #expect(Naval.blockadedLaunchSites(for: owner, in: state) == [launch])
        for _ in 0..<Naval.hullsPerBuilder { NavalTestSupport.addShip(at: launch, player: 0, in: &state) }
        #expect(Naval.launchSites(for: owner, in: state).isEmpty)
        #expect(Naval.blockadedLaunchSites(for: owner, in: state).isEmpty)
        #expect(Naval.blockadedLaunchSites(for: PlayerID(index: 99), in: state).isEmpty)
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test func exhaustedShipsStillDefendAndTurnRefreshDoesNotChangeTheBlockade() throws {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 1, steps: 0, in: &state)
        let ship = try #require(state.naval?.ships.first)
        let before = Naval.sailingDestinations(for: ship, in: state)
        #expect(Naval.isBlockaded(intermediate, by: owner, in: state))
        Naval.beginTurn(for: PlayerID(index: 1), in: &state)
        #expect(state.naval?.ships[1].stepsRemaining == Naval.movementPerTurn(in: state))
        #expect(Naval.sailingDestinations(for: ship, in: state) == before)
    }

    @Test func captureCreatedMixedStackCanDepartButNotReenterAndColdResumesExactly() throws {
        var state = try NavalTestSupport.ready()
        let launch = try #require(Naval.launchSites(for: owner, in: state).first)
        NavalTestSupport.addShip(at: launch, player: 1, in: &state)
        NavalTestSupport.addShip(at: launch, player: 1, in: &state)
        try NavalTestSupport.roll(11, player: owner.index, state: &state)
        try RulesEngine.apply(.captureShip(id: 0), by: owner, to: &state)
        #expect(Naval.isBlockaded(launch, by: owner, in: state))
        #expect(Naval.isBlockaded(launch, by: PlayerID(index: 1), in: state))
        let captured = try #require(state.naval?.ships.first)
        let departure = try #require(Naval.sailingDestinations(for: captured, in: state).first { launch.distance(to: $0) == 1 })
        var original = GameSession(state: state, policies: [:], policySeed: 7)
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(original.checkpoint))
        try checkpoint.validate()
        var resumed = try GameSession(checkpoint: checkpoint, policies: [:])
        let move = GameMove.sailShip(id: captured.id, to: departure)
        let first = try original.applyExternal(move, by: owner)
        let second = try resumed.applyExternal(move, by: owner)
        #expect(first.actor == second.actor && first.move == second.move && first.events == second.events)
        #expect(first.privateEvents == second.privateEvents)
        #expect(original.checkpoint == resumed.checkpoint)
        #expect(Naval.validationProblem(in: original.state) == nil)
        let moved = try #require(original.state.naval?.ships.first)
        #expect(moved.stepsRemaining == 1)
        #expect(Naval.sailingRoute(for: moved, to: launch, in: original.state) == nil)
    }

    @Test func captureOpensAHexOnlyWhenNoThirdPartyRivalRemains() throws {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        NavalTestSupport.addShip(at: intermediate, player: 2, in: &state)
        try NavalTestSupport.roll(11, player: owner.index, state: &state)
        try RulesEngine.apply(.captureShip(id: 1), by: owner, to: &state)
        #expect(Naval.isBlockaded(intermediate, by: owner, in: state))
        let ship = try #require(state.naval?.ships.first)
        #expect(Naval.sailingRoute(for: ship, to: intermediate, in: state) == nil)
        try NavalTestSupport.roll(11, player: owner.index, state: &state)
        try RulesEngine.apply(.captureShip(id: 2), by: owner, to: &state)
        #expect(!Naval.isBlockaded(intermediate, by: owner, in: state))
        #expect(Naval.sailingRoute(for: ship, to: intermediate, in: state) == [intermediate])
    }

    @Test func theLastRivalsDepartureImmediatelyOpensItsFormerHex() throws {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        #expect(Naval.isBlockaded(intermediate, by: owner, in: state))
        state.phase = .mainTurn(playerIndex: 1)
        try RulesEngine.apply(.sailShip(id: 1, to: destination), by: PlayerID(index: 1), to: &state)
        #expect(!Naval.isBlockaded(intermediate, by: owner, in: state))
        let ship = try #require(state.naval?.ships.first)
        #expect(Naval.sailingRoute(for: ship, to: intermediate, in: state) == [intermediate])
    }

    @Test(arguments: [1, 2, 3])
    func legacyMatchesRetainEnemyOverlapTransitLaunchAndExactReplay(version: Int) throws {
        var state = seaPosition(version: version)
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        let before = state
        let ship = try #require(state.naval?.ships.first)
        #expect(!Naval.isBlockaded(intermediate, by: owner, in: state))
        let move = GameMove.sailShip(id: ship.id, to: intermediate)
        let events = try RulesEngine.apply(move, by: owner, to: &state)
        #expect(state.naval?.ships.filter { $0.coordinate == intermediate }.count == 2)
        let onward = GameMove.sailShip(id: ship.id, to: destination)
        let onwardEvents = try RulesEngine.apply(onward, by: owner, to: &state)
        var replay = before
        #expect(try RulesEngine.replay(move, by: owner, rulesVersion: 3, to: &replay) == events)
        #expect(try RulesEngine.replay(onward, by: owner, rulesVersion: 3, to: &replay) == onwardEvents)
        #expect(replay == state)
        var coast = try NavalTestSupport.ready(rulesVersion: version)
        NavalTestSupport.fund(Naval.shipCost, in: &coast)
        let launch = try #require(Naval.launchSites(for: owner, in: coast).first)
        NavalTestSupport.addShip(at: launch, player: 1, in: &coast)
        #expect(Naval.launchSites(for: owner, in: coast).contains(launch))
        #expect(Naval.blockadedLaunchSites(for: owner, in: coast).isEmpty)
        try RulesEngine.apply(.buildShip(at: launch), by: owner, to: &coast)
        #expect(Naval.validationProblem(in: coast) == nil)
    }

    @Test func maskedRoutesAndActionsDoNotDependOnConcealedTerrain() throws {
        let baseline = blockadedPosition()
        let ship = try #require(baseline.naval?.ships.first)
        let moves = RulesEngine.legalMoves(for: baseline)
        let observation = GameObservation(seat: owner, state: baseline, legalMoves: moves)
        let destinations = Naval.sailingDestinations(for: ship, in: baseline)
        #expect(Naval.sailingDestinations(for: ship, in: observation.state) == destinations)
        #expect(Naval.sailingRoute(for: ship, to: destination, in: observation.state) == [alternative, destination])
        #expect(observation.state.naval?.ships == baseline.naval?.ships)
        let hidden = Set(baseline.board.tiles.map(\.coordinate)).subtracting(baseline.naval!.revealed)
        for kind in [TileKind.sea, .resource(.ore), .resourceChoice] {
            var changed = baseline
            replace(hidden, with: kind, in: &changed)
            let recomputed = RulesEngine.legalMoves(for: changed)
            #expect(recomputed == moves)
            #expect(GameObservation(seat: owner, state: changed, legalMoves: recomputed) == observation)
            #expect(Naval.sailingDestinations(for: ship, in: changed) == destinations)
        }
    }

    @Test func shipArrayOrderCannotChangeCanonicalRoutesMovesOrEvents() throws {
        var forward = blockadedPosition()
        NavalTestSupport.addShip(at: destination, player: 0, in: &forward)
        var reversed = forward
        reversed.naval?.ships.reverse()
        let ship = try #require(forward.naval?.ships.first)
        let destinations = Naval.sailingDestinations(for: ship, in: forward)
        #expect(destinations == destinations.sorted())
        #expect(Naval.sailingDestinations(for: ship, in: reversed) == destinations)
        #expect(Naval.sailingRoute(for: ship, to: destination, in: reversed) == [alternative, destination])
        #expect(RulesEngine.legalMoves(for: forward) == RulesEngine.legalMoves(for: reversed))
        let move = GameMove.sailShip(id: ship.id, to: destination)
        #expect(try RulesEngine.apply(move, by: owner, to: &forward) == RulesEngine.apply(move, by: owner, to: &reversed))
        #expect(forward.rng == reversed.rng && forward.naval?.revealed == reversed.naval?.revealed)
        #expect(forward.naval?.ships.sorted { $0.id < $1.id } == reversed.naval?.ships.sorted { $0.id < $1.id })
    }

    private func blockadedPosition() -> GameState {
        var state = seaPosition()
        NavalTestSupport.addShip(at: intermediate, player: 1, in: &state)
        return state
    }

    /// A public all-sea graph isolates movement while real maps cover durable checkpoint validity.
    private func seaPosition(version: Int = Naval.currentRulesVersion) -> GameState {
        var state = Naval.newGame(seed: 73)
        state.naval?.rulesVersion = version
        replace(Set(state.board.tiles.map(\.coordinate)), with: .sea, in: &state)
        state.phase = .mainTurn(playerIndex: owner.index)
        state.naval?.revealed = Set(state.board.tiles.filter {
            $0.coordinate.distance(to: origin) <= Naval.viewingRange
                || $0.coordinate.distance(to: HexCoordinate(q: 0, r: 0)) <= Naval.homeRadius
        }.map(\.coordinate))
        NavalTestSupport.addShip(at: origin, player: owner.index, in: &state)
        return state
    }

    private func replace(_ coordinates: Set<HexCoordinate>, with kind: TileKind, in state: inout GameState) {
        let tiles = state.board.tiles.map {
            coordinates.contains($0.coordinate) ? Tile(coordinate: $0.coordinate, kind: kind, numberToken: nil) : $0
        }
        state.board = Board(tiles: tiles, ports: [], onBoardVertices: [], onBoardEdges: [], robberTile: state.board.robberTile)
    }
}
