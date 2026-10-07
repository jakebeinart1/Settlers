import Foundation
import Testing
@testable import CatanEngine

struct NavalGameplayTests {
    @Test(arguments: [3, 4])
    func shipsPayExactCostSailAndRefresh(table: Int) throws {
        var state = try NavalTestSupport.ready(playerCount: table)
        let owner = state.players[0].id
        NavalTestSupport.fund(Naval.shipCost, in: &state)
        let before = state.players[0].resources
        let bank = state.bank
        let launch = try #require(Naval.launchSites(for: owner, in: state).first)
        let built = try RulesEngine.apply(.buildShip(at: launch), by: owner, to: &state)
        #expect(built.contains(.builtShip(owner, shipID: 0, at: launch)))
        for resource in Resource.allCases {
            #expect(state.players[0].resources[resource, default: 0] == before[resource, default: 0] - Naval.shipCost[resource, default: 0])
            #expect(state.bank[resource, default: 0] == bank[resource, default: 0] + Naval.shipCost[resource, default: 0])
        }
        for remaining in stride(from: Naval.movementPerTurn(in: state) - 1, through: 0, by: -1) {
            let ship = try #require(state.naval?.ships.first)
            let destination = try #require(Naval.sailingDestinations(for: ship, in: state).last { ship.coordinate.distance(to: $0) == 1 })
            let revealed = state.naval!.revealed
            try RulesEngine.apply(.sailShip(id: ship.id, to: destination), by: owner, to: &state)
            #expect(state.naval?.ships.first?.stepsRemaining == remaining)
            #expect(revealed.isSubset(of: state.naval!.revealed))
            #expect(state.board.tiles.filter { $0.coordinate.distance(to: destination) <= 2 }.allSatisfy { state.naval!.revealed.contains($0.coordinate) })
        }
        let exhausted = state
        #expect(throws: MoveError.self) { try RulesEngine.apply(.sailShip(id: 0, to: launch), by: owner, to: &state) }
        #expect(state == exhausted)
        for index in 0..<table {
            state.phase = .mainTurn(playerIndex: index)
            try RulesEngine.apply(.endTurn, by: state.players[index].id, to: &state)
        }
        #expect(state.naval?.ships.first?.stepsRemaining == Naval.movementPerTurn(in: state))
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test func stockBelongsToBuilderAndSeaHexesAllowStacking() throws {
        var state = try NavalTestSupport.ready()
        let owner = state.players[0].id
        NavalTestSupport.fund(Naval.shipCost.mapValues { $0 * Naval.hullsPerBuilder }, in: &state)
        let launch = try #require(Naval.launchSites(for: owner, in: state).first)
        for _ in 0..<Naval.hullsPerBuilder { try RulesEngine.apply(.buildShip(at: launch), by: owner, to: &state) }
        #expect(state.naval?.ships.count == 6)
        #expect(Naval.launchSites(for: owner, in: state).isEmpty)
        try NavalTestSupport.roll(11, player: 1, state: &state)
        #expect(state.phase == .capturingShip(playerIndex: 1))
        try RulesEngine.apply(.captureShip(id: 0), by: state.players[1].id, to: &state)
        #expect(Naval.shipsBuilt(by: owner, in: state) == 6)
        #expect(Naval.shipsBuilt(by: state.players[1].id, in: state) == 0)
        #expect(Naval.launchSites(for: owner, in: state).isEmpty)
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test func captureIsGlobalOptionalAndLastsUntilRecapture() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let sea = try #require(state.board.tiles.last { $0.kind == .sea }?.coordinate)
        NavalTestSupport.addShip(at: sea, player: 1, steps: 0, in: &state)
        try NavalTestSupport.roll(11, player: 0, state: &state)
        #expect(RulesEngine.legalMoves(for: state).contains(.captureShip(id: 0)))
        #expect(RulesEngine.legalMoves(for: state).contains(.skipShipCapture))
        try RulesEngine.apply(.skipShipCapture, by: state.players[0].id, to: &state)
        #expect(state.naval?.ships[0].owner.index == 1)
        try NavalTestSupport.roll(11, player: 0, state: &state)
        try RulesEngine.apply(.captureShip(id: 0), by: state.players[0].id, to: &state)
        #expect(state.naval?.ships[0].owner.index == 0)
        #expect(state.naval?.ships[0].stepsRemaining == Naval.movementPerTurn(in: state))
        try NavalTestSupport.roll(11, player: 0, state: &state)
        #expect(state.phase == .mainTurn(playerIndex: 0))
        try NavalTestSupport.roll(11, player: 2, state: &state)
        try RulesEngine.apply(.captureShip(id: 0), by: state.players[2].id, to: &state)
        #expect(state.naval?.ships[0].owner.index == 2)
        #expect(state.naval?.ships.count == 1)
    }

    @Test func landingRequiresSettlementBeforeRoadAndScoresDistinctIslands() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let owner = state.players[0].id
        for island in 1...3 {
            let site = try #require(Naval.potentialColonySites(for: owner, in: state).first { vertex in
                vertex.touchingTiles.contains { state.naval?.islandByHex[$0] == island }
            })
            let sea = try #require(site.touchingTiles.first { coordinate in state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea } })
            NavalTestSupport.addShip(at: sea, player: 0, in: &state)
            let edges = state.board.edgesTouching(site)
            #expect(edges.allSatisfy { !Building.canBuildRoad($0, for: owner, in: state) })
            #expect(Building.canBuildSettlement(site, for: owner, in: state))
            NavalTestSupport.fund(Building.settlementCost, in: &state)
            let events = try RulesEngine.apply(.buildSettlement(site), by: owner, to: &state)
            #expect(edges.contains { Building.canBuildRoad($0, for: owner, in: state) })
            #expect(Naval.colonyPoints(for: owner, in: state) == min(island, 2))
            #expect(events.contains(.earnedColonyPoint(owner, total: island)) == (island <= 2))
            #expect(state.naval?.ships.count == island)
        }
        #expect(Naval.validationProblem(in: state) == nil)
    }

    @Test func shipsCannotTeleportCrossLandOrMoveForAnotherSeat() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let launch = try #require(Naval.launchSites(for: state.players[0].id, in: state).first)
        NavalTestSupport.addShip(at: launch, player: 0, in: &state)
        let unchanged = state
        #expect(throws: MoveError.self) { try RulesEngine.apply(.sailShip(id: 0, to: HexCoordinate(q: 0, r: 0)), by: state.players[0].id, to: &state) }
        #expect(state == unchanged)
        #expect(throws: MoveError.self) { try RulesEngine.apply(.sailShip(id: 0, to: launch.neighbor(0)), by: state.players[1].id, to: &state) }
        #expect(state == unchanged)
    }
}

extension NavalGameplayTests {
    @Test func aFirstColonyBonusCanCompleteTheFourteenPointWin() throws {
        var state = try NavalTestSupport.ready(fog: false)
        let owner = state.players[0].id
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 10)
        let site = try #require(Naval.potentialColonySites(for: owner, in: state).first { vertex in
            vertex.touchingTiles.contains { (state.naval?.islandByHex[$0] ?? 0) > 0 }
        })
        let sea = try #require(site.touchingTiles.first { coordinate in state.board.tiles.contains { $0.coordinate == coordinate && $0.kind == .sea } })
        NavalTestSupport.addShip(at: sea, player: 0, in: &state)
        #expect(state.victoryPoints(for: owner) == 12)
        NavalTestSupport.fund(Building.settlementCost, in: &state)
        let events = try RulesEngine.apply(.buildSettlement(site), by: owner, to: &state)
        #expect(state.victoryPoints(for: owner) == 14)
        #expect(state.phase == .gameOver(winner: owner))
        #expect(events.contains(.earnedColonyPoint(owner, total: 1)))
        #expect(events.last == .gameWon(owner))
        #expect(Naval.awardColony(at: site, by: owner, in: &state).isEmpty)
    }
}
