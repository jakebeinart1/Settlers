import Foundation
import Testing
@testable import CatanEngine

/// Ship reach is a colony-founding requirement, not a restriction on ordinary land settlement.
struct NavalSettlementScopeTests {
    @Test(arguments: NavalMapFamily.allCases, [false, true])
    func inlandOpeningIsLegalWithEitherFogSetting(family: NavalMapFamily, fog: Bool) throws {
        for count in [3, 4] {
            var state = Naval.newGame(seed: 7501, playerCount: count,
                options: NavalOptions(fogEnabled: fog, mapFamily: family))
            let inland = try #require(state.board.onBoardVertices.sorted().first { vertex in
                vertex.touchingTiles.allSatisfy { state.naval?.islandByHex[$0] == 0 }
            })
            let actor = state.players[0].id
            #expect(!Naval.isCoastal(inland, in: state))
            #expect(RulesEngine.legalMoves(for: state).contains(.placeInitialSettlement(inland)))
            try RulesEngine.apply(.placeInitialSettlement(inland), by: actor, to: &state)
            #expect(state.players[0].settlements == [inland])
            #expect(Naval.launchSites(for: actor, in: state).isEmpty)
            let road = try #require(RulesEngine.legalMoves(for: state).first)
            try RulesEngine.apply(road, by: actor, to: &state)
            #expect(state.phase == .setupForward(playerIndex: 1))
            #expect(Naval.validationProblem(in: state) == nil)
        }
    }

    @Test(arguments: [1, 2])
    func resumedSetupOffersInlandSitesWithoutChangingSavedVision(version: Int) throws {
        var state = Naval.newGame(seed: 7501)
        state.naval?.rulesVersion = version
        let checkpoint = GameSession(state: state, policies: [:], policySeed: 7).checkpoint
        let data = try JSONEncoder().encode(checkpoint)
        let decoded = try JSONDecoder().decode(GameSession.Checkpoint.self, from: data)
        try decoded.validate()
        var resumed = try GameSession(checkpoint: decoded, policies: [:])
        let inland = try #require(state.board.onBoardVertices.sorted().first { vertex in
            vertex.touchingTiles.allSatisfy { state.naval?.islandByHex[$0] == 0 }
        })
        #expect(resumed.state == state)
        _ = try resumed.applyExternal(.placeInitialSettlement(inland), by: state.players[0].id)
        #expect(resumed.state.naval?.rulesVersion == version)
        #expect(state.naval!.revealed.isSubset(of: resumed.state.naval!.revealed))
        #expect(resumed.state.players[0].settlements.contains(inland))
    }

    @Test(arguments: NavalMapFamily.allCases, [3, 4])
    func bothOpeningSettlementsCanBeInland(family: NavalMapFamily, count: Int) throws {
        var state = Naval.newGame(seed: 7501, playerCount: count,
            options: NavalOptions(mapFamily: family))
        while state.phase.isSetup {
            let index = try #require(state.phase.awaitingSeatIndex)
            let legal = RulesEngine.legalMoves(for: state)
            let inland = legal.first { move in
                guard case .placeInitialSettlement(let vertex) = move else { return false }
                return vertex.touchingTiles.allSatisfy { state.naval?.islandByHex[$0] == 0 }
            }
            let move: GameMove
            if index == 0, case .placeInitialSettlement = legal.first {
                move = try #require(inland, "Both setup rounds must retain a legal inland site")
            } else { move = try #require(legal.first) }
            try RulesEngine.apply(move, by: state.players[index].id, to: &state)
        }
        #expect(state.players[0].settlements.count == 2)
        #expect(state.players[0].settlements.allSatisfy { !Naval.isCoastal($0, in: state) })
        #expect(state.players[0].roads.count == 2)
        #expect(state.players[0].resources.values.reduce(0, +) > 0)
        #expect(state.phase == .rollDice(playerIndex: 0))
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test func setupStillCannotSkipToAnOverseasIslandOrIgnoreDistance() throws {
        var state = Naval.newGame(seed: 7501, options: NavalOptions(fogEnabled: false))
        let actor = state.players[0].id
        let overseas = try #require(state.board.onBoardVertices.sorted().first { vertex in
            vertex.touchingTiles.contains { (state.naval?.islandByHex[$0] ?? 0) > 0 }
        })
        #expect(!RulesEngine.legalMoves(for: state).contains(.placeInitialSettlement(overseas)))
        let unchanged = state
        #expect(throws: MoveError.illegalPlacement) {
            try RulesEngine.apply(.placeInitialSettlement(overseas), by: actor, to: &state)
        }
        #expect(state == unchanged)
        let opening = try #require(RulesEngine.legalMoves(for: state).first)
        try RulesEngine.apply(opening, by: actor, to: &state)
        let vertex = try #require(state.players[0].settlements.first)
        try RulesEngine.apply(try #require(RulesEngine.legalMoves(for: state).first), by: actor, to: &state)
        for adjacent in state.board.adjacentVertices(of: vertex) {
            #expect(!RulesEngine.legalMoves(for: state).contains(.placeInitialSettlement(adjacent)))
        }
    }

    @Test func inlandPaidSettlementRequiresOwnRoadAndShipDoesNotSubstitute() throws {
        var state = Naval.newGame(seed: 7501)
        state.phase = .mainTurn(playerIndex: 0)
        let actor = state.players[0].id
        let inland = try #require(state.board.onBoardVertices.sorted().first { vertex in
            vertex.touchingTiles.allSatisfy { state.naval?.islandByHex[$0] == 0 }
        })
        NavalTestSupport.fund(Building.settlementCost, in: &state)
        let sea = try #require(state.board.tiles.first { $0.kind == .sea }?.coordinate)
        NavalTestSupport.addShip(at: sea, player: 0, in: &state)
        #expect(!Naval.canFoundColony(at: inland, by: actor, in: state))
        #expect(!Building.canBuildSettlement(inland, for: actor, in: state))
        let edge = try #require(state.board.edgesTouching(inland).first)
        state.players[1].roads.insert(edge)
        #expect(!Building.canBuildSettlement(inland, for: actor, in: state))
        state.players[1].roads.remove(edge)
        state.players[0].roads.insert(edge)
        #expect(Building.canBuildSettlement(inland, for: actor, in: state))
        try RulesEngine.apply(.buildSettlement(inland), by: actor, to: &state)
        #expect(state.players[0].settlements.contains(inland))
        #expect(Naval.colonyPoints(for: actor, in: state) == 0)
    }

    @Test func foundingNeedsAnOwnedShipAtThatExactCoastalCorner() throws {
        var state = Naval.newGame(seed: 7501, options: NavalOptions(fogEnabled: false))
        state.phase = .mainTurn(playerIndex: 0)
        let actor = state.players[0].id
        let site = try #require(Naval.potentialColonySites(for: actor, in: state).first { vertex in
            vertex.touchingTiles.contains { (state.naval?.islandByHex[$0] ?? 0) > 0 }
        })
        let sea = try #require(site.touchingTiles.first { coordinate in
            state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea }
        })
        NavalTestSupport.fund(Building.settlementCost, in: &state)
        #expect(!Building.canBuildSettlement(site, for: actor, in: state))
        let distant = try #require(state.board.tiles.last { $0.kind == .sea && !site.touchingTiles.contains($0.coordinate) }?.coordinate)
        NavalTestSupport.addShip(at: distant, player: 0, in: &state)
        NavalTestSupport.addShip(at: sea, player: 1, in: &state)
        #expect(!Building.canBuildSettlement(site, for: actor, in: state))
        #expect(state.board.edgesTouching(site).allSatisfy { !Building.canBuildRoad($0, for: actor, in: state) })
        NavalTestSupport.addShip(at: sea, player: 0, in: &state)
        #expect(Building.canBuildSettlement(site, for: actor, in: state))
        try RulesEngine.apply(.buildSettlement(site), by: actor, to: &state)
        #expect(state.board.edgesTouching(site).contains { Building.canBuildRoad($0, for: actor, in: state) })
        #expect(Naval.colonyPoints(for: actor, in: state) == 1)
    }

    @Test func foundedIslandCanExpandInlandByRoadAfterItsShipLeaves() throws {
        var state = Naval.newGame(seed: 7501,
            options: NavalOptions(fogEnabled: false, mapFamily: .twinIslands))
        state.phase = .mainTurn(playerIndex: 0)
        let actor = state.players[0].id
        let interior = state.board.onBoardVertices.sorted().filter { vertex in
            let islands = vertex.touchingTiles.compactMap { state.naval?.islandByHex[$0] }
            return islands.count == 3 && Set(islands).count == 1 && islands[0] > 0
        }
        let landing = try #require(Naval.potentialColonySites(for: actor, in: state).first { coast in
            interior.contains { vertex in
                let path = landPath(from: coast, to: vertex, in: state)
                return (2...4).contains(path.count)
            }
        })
        let target = try #require(interior.first { (2...4).contains(landPath(from: landing, to: $0, in: state).count) })
        let path = landPath(from: landing, to: target, in: state)
        let sea = try #require(landing.touchingTiles.first { coordinate in
            state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea }
        })
        NavalTestSupport.addShip(at: sea, player: 0, in: &state)
        #expect(!Building.canBuildSettlement(target, for: actor, in: state))
        NavalTestSupport.fund(Building.settlementCost.mapValues { $0 * 2 }, in: &state)
        NavalTestSupport.fund(Building.roadCost.mapValues { $0 * path.count }, in: &state)
        try RulesEngine.apply(.buildSettlement(landing), by: actor, to: &state)
        let ship = try #require(state.naval?.ships.first)
        let away = try #require(Naval.sailingDestinations(for: ship, in: state).first { !landing.touchingTiles.contains($0) })
        try RulesEngine.apply(.sailShip(id: ship.id, to: away), by: actor, to: &state)
        for edge in path { try RulesEngine.apply(.buildRoad(edge), by: actor, to: &state) }
        try RulesEngine.apply(.buildSettlement(target), by: actor, to: &state)
        #expect(!Naval.isCoastal(target, in: state))
        #expect(state.players[0].settlements == [landing, target])
        #expect(Naval.colonyPoints(for: actor, in: state) == 1)
        #expect(state.naval?.ships.first?.coordinate == away)
        #expect(Naval.validationProblem(in: state) == nil)
    }

    private func landPath(from origin: VertexID, to target: VertexID, in state: GameState) -> [EdgeID] {
        var queue: [(VertexID, [EdgeID])] = [(origin, [])]
        var visited: Set<VertexID> = [origin]
        var index = 0
        while index < queue.count {
            let (vertex, path) = queue[index]
            index += 1
            if vertex == target { return path }
            for edge in state.board.edgesTouching(vertex).sorted() where Naval.roadIsKnownLand(edge, in: state) {
                let next = edge.a == vertex ? edge.b : edge.a
                if visited.insert(next).inserted { queue.append((next, path + [edge])) }
            }
        }
        return []
    }
}
