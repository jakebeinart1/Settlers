import Foundation
import SwiftUI
import Testing
import CatanEngine
@testable import Settlers

/// Public route presentation, physical board targeting and durable ownership
/// must agree. A blocked destination is not a nearby legal destination, and
/// an 11's confirmed capture must open the passage in the saved match itself.
@MainActor
@Suite(.serialized)
struct NavalBlockadePresentationTests {
    private let actor = PlayerID(index: 0)
    private let rival = PlayerID(index: 1)

    @Test(arguments: NavalBlockadeQAFixture.Position.allCases, [false, true])
    func generatedBlockadeBaselinesConserveSupplyAndValidate(position: NavalBlockadeQAFixture.Position, fog: Bool) throws {
        let state = try NavalBlockadeQAFixture.make(position, options: NavalOptions(fogEnabled: fog))
        let rulesVersion = try #require(state.naval?.rulesVersion)
        #expect(rulesVersion == Naval.currentRulesVersion)
        #expect(rulesVersion >= Naval.blockadeRulesVersion)
        #expect(state.players.allSatisfy { $0.settlements.count == 2 && $0.roads.count == 2 })
        #expect(state.naval?.ships.filter { $0.owner == rival }.allSatisfy { $0.stepsRemaining == 0 } == true)
        for resource in Resource.allCases {
            #expect(state.bank[resource, default: 0]
                + state.players.reduce(0) { $0 + $1.resources[resource, default: 0] } == state.rules.bankPerResource)
        }
        try GameSession(state: state, policies: [:], policySeed: 0).checkpoint.validate()
    }

    @Test func blockadeRemovesEntryAndStraightVoyageWithoutTouchSnappingOrStateChanges() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let before = try NavalBlockadeQAFixture.make(.passage)
        model.replaceStateForTesting(before, humanSeat: actor)
        let blocker = try #require(before.naval?.ships.first { $0.id == 1 })
        let destination = NavalBlockadeQAFixture.destination(in: before)
        #expect(model.selectBoardTarget(.ship(0)))
        let decision = try #require(model.boardDecisionPresentation)
        #expect(decision.blockadedTiles == [blocker.coordinate: rival])
        #expect(!decision.legalTiles.contains(blocker.coordinate) && !decision.legalTiles.contains(destination))
        #expect(decision.sailing?.routes[blocker.coordinate] == nil && decision.sailing?.routes[destination] == nil)
        #expect(!model.selectBoardTarget(.tile(blocker.coordinate)))
        #expect(!model.selectBoardTarget(.tile(destination)))
        let board = Naval.visibleBoard(in: before)
        for size in [CGFloat(9.6), 25] {
            let geometry = HexGeometry(origin: CGPoint(x: 200, y: 150), size: size)
            #expect(BoardDropTargetResolver.nearest(to: geometry.center(of: blocker.coordinate),
                decision: decision, board: board, geometry: geometry) == nil)
            for target in decision.legalTiles {
                #expect(BoardDropTargetResolver.nearest(to: geometry.center(of: target),
                    decision: decision, board: board, geometry: geometry) == .tile(target))
            }
        }
        #expect(!model.confirmBoardDecision())
        #expect(model.state == before)
        #expect(fixture.makeModel().state == before)
    }

    @Test func alternateTwoHexRouteStaysAvailableAndConfirmedCostSurvivesResume() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let before = try NavalBlockadeQAFixture.make(.passage)
        model.replaceStateForTesting(before, humanSeat: actor)
        let ship = try #require(before.naval?.ships.first { $0.id == 0 })
        let blocker = try #require(before.naval?.ships.first { $0.id == 1 })
        #expect(model.selectBoardTarget(.ship(ship.id)))
        let decision = try #require(model.boardDecisionPresentation)
        let revealed = try #require(before.naval?.revealed)
        let alternate = try #require(decision.legalTiles.sorted().first { coordinate in
            guard ship.coordinate.distance(to: coordinate) == 2,
                  blocker.coordinate.distance(to: coordinate) == 1,
                  let route = decision.sailing?.routes[coordinate] else { return false }
            return before.board.tiles.contains { tile in
                !revealed.contains(tile.coordinate)
                    && route.contains { $0.distance(to: tile.coordinate) <= Naval.viewingRange }
            }
        })
        let route = try #require(decision.sailing?.routes[alternate])
        #expect(route.count == 2 && !route.contains(blocker.coordinate))
        #expect(model.selectBoardTarget(.tile(alternate)))
        #expect(model.boardDecisionPresentation?.sailing?.selectedRoute == route)
        #expect(model.state == before)
        #expect(model.confirmBoardDecision())
        #expect(model.state.naval?.ships.first { $0.id == ship.id }?.coordinate == alternate)
        #expect(model.state.naval?.ships.first { $0.id == ship.id }?.stepsRemaining == 0)
        let defender = try #require(model.state.naval?.ships.first { $0.id == blocker.id })
        #expect(defender.id == blocker.id && defender.owner == blocker.owner)
        #expect(defender.coordinate == blocker.coordinate && defender.stepsRemaining == blocker.stepsRemaining)
        let revealedAfter = try #require(model.state.naval?.revealed)
        let discoveries = revealedAfter.subtracting(revealed)
        #expect(!discoveries.isEmpty && revealed.isSubset(of: revealedAfter))
        // A real public discovery invalidates every hull's old travel objective,
        // including the stationary defender; its physical blockade stays intact.
        #expect(blocker.previousSailingOrigin != nil && defender.previousSailingOrigin == nil)
        #expect(model.state.naval?.ships.first { $0.id == ship.id }?.previousSailingOrigin == nil)
        #expect(Naval.isBlockaded(blocker.coordinate, by: actor, in: model.state))
        #expect(model.state.players == before.players)
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func confirmedCaptureReopensTheTwoHexVoyageAndPersistsItsActualMoves() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        let before = try NavalBlockadeQAFixture.make(.capture)
        model.replaceStateForTesting(before, humanSeat: actor)
        #expect(model.selectBoardTarget(.ship(1)))
        #expect(model.state == before)
        let resumed = fixture.makeModel()
        #expect(resumed.boardDecisionPresentation?.intent == .captureShip)
        #expect(resumed.boardDecisionPresentation?.selectedShip == nil)
        #expect(resumed.selectBoardTarget(.ship(1)) && resumed.confirmBoardDecision())
        let captured = try #require(resumed.state.naval?.ships.first { $0.id == 1 })
        #expect(captured.owner == actor && captured.stepsRemaining == Naval.movementPerTurn)
        #expect(captured.coordinate == before.naval?.ships.first { $0.id == 1 }?.coordinate)
        #expect(resumed.state.players == before.players && resumed.state.naval?.hullsBuilt == before.naval?.hullsBuilt)
        #expect(resumed.pendingShipCapture != nil && resumed.dismissShipCapture())
        #expect(resumed.selectBoardTarget(.ship(0)))
        let destination = NavalBlockadeQAFixture.destination(in: before)
        #expect(resumed.boardDecisionPresentation?.blockadedTiles.isEmpty == true)
        #expect(resumed.boardDecisionPresentation?.sailing?.routes[destination]?.count == 2)
        #expect(resumed.selectBoardTarget(.tile(destination)) && resumed.confirmBoardDecision())
        #expect(resumed.state.naval?.ships.first { $0.id == 0 }?.coordinate == destination)
        #expect(resumed.state.naval?.ships.first { $0.id == 0 }?.stepsRemaining == 0)
        #expect(resumed.checkpointDocument?.activeMatch?.moves.count == 2)
        #expect(fixture.makeModel().state == resumed.state)
    }

    @Test func movingTheDefenderAwayOpensPassageWithoutOwnershipChanges() throws {
        let fixture = try CheckpointModelFixture()
        let model = fixture.makeModel()
        var before = try NavalBlockadeQAFixture.make(.passage)
        before.phase = .mainTurn(playerIndex: rival.index)
        before.naval!.ships[1].stepsRemaining = Naval.movementPerTurn(in: before)
        // Starting the defender's next turn refreshes both its allowance and
        // its public travel history, as Naval.beginTurn does in real play.
        before.naval!.ships[1].previousSailingOrigin = nil
        try GameSession(state: before, policies: [:], policySeed: 0).checkpoint.validate()
        model.replaceStateForTesting(before, humanSeat: rival)
        #expect(model.selectBoardTarget(.ship(1)))
        let original = try #require(before.naval?.ships.first { $0.id == 0 })
        let destination = NavalBlockadeQAFixture.destination(in: before)
        let retreat = try #require(model.boardDecisionPresentation?.legalTiles.first {
            $0 != destination && original.coordinate.distance(to: $0) > 1
        })
        #expect(model.selectBoardTarget(.tile(retreat)) && model.confirmBoardDecision())
        #expect(model.state.naval?.ships.first { $0.id == 1 }?.owner == rival)
        #expect(Naval.sailingRoute(for: original, to: destination, in: model.state)?.count == 2)
        #expect(model.state.players == before.players)
        #expect(fixture.makeModel().state == model.state)
    }

    @Test func fundedCoastBlockadeExplainsDisabledPurchaseAndRejectedLaunchIsAtomic() throws {
        let before = try NavalBlockadeQAFixture.make(.launch)
        let choices = BuildActionPresentation.menu(in: before, for: actor)
        let ship = try #require(choices.first { $0.kind == .ship })
        #expect(!ship.isEnabled && ship.costs.allSatisfy { $0.missing == 0 })
        #expect(ship.detail == "Your launch coast is blocked by opposing ships")
        let blocked = try #require(Naval.blockadedLaunchSites(for: actor, in: before).first)
        #expect(!RulesEngine.legalMoves(for: before, seat: actor).contains(.buildShip(at: blocked)))
        var session = GameSession(state: before, policies: [:], policySeed: 0)
        #expect(throws: (any Error).self) { try session.applyExternal(.buildShip(at: blocked), by: actor) }
        #expect(session.state == before)
        try session.checkpoint.validate()
    }

    @Test func legacyWaterOverlapKeepsItsOriginalMaskAndHasNoBlockadeDecoration() throws {
        var before = try NavalBlockadeQAFixture.make(.passage)
        before.naval?.rulesVersion = 3
        // A historical v3 baseline never carried v5 voyage history. Downgrading
        // the version alone would produce an impossible saved ship state.
        for index in before.naval!.ships.indices {
            before.naval!.ships[index].previousSailingOrigin = nil
        }
        try GameSession(state: before, policies: [:], policySeed: 0).checkpoint.validate()
        let model = isolatedGameViewModel()
        model.replaceStateForTesting(before, humanSeat: actor)
        #expect(model.selectBoardTarget(.ship(0)))
        let blocker = try #require(before.naval?.ships.first { $0.id == 1 })
        let decision = try #require(model.boardDecisionPresentation)
        #expect(decision.blockadedTiles.isEmpty)
        #expect(decision.legalTiles.contains(blocker.coordinate))
        #expect(decision.sailing?.routes[NavalBlockadeQAFixture.destination(in: before)]?.count == 2)
        #expect(decision.sailing?.detail == "2 hexes left this turn. Numbers show travel cost.")
    }
}
