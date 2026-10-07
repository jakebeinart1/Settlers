import SwiftUI
import Testing
import CatanEngine
@testable import Settlers

/// Discovery changes the public rendering facts, never the world frame.
/// These cases also exercise inward-facing island ports, which cannot use
/// the single-island renderer's global-center offshore normal.
@MainActor
@Suite struct NavalBoardGeometryTests {
    @Test func discoveringPortsDoesNotChangeTheSolvedWorldGeometry() throws {
        let hidden = Naval.newGame(seed: 42, playerCount: 4, options: .init())
        var revealed = hidden
        var naval = try #require(revealed.naval)
        naval.revealed = Set(revealed.board.tiles.map(\.coordinate))
        revealed.naval = naval
        let publicHidden = Naval.visibleBoard(in: hidden)
        let publicRevealed = Naval.visibleBoard(in: revealed)
        #expect(publicHidden.ports.count < publicRevealed.ports.count)
        let size = view(hidden).worldViewport(in: CGSize(width: 402, height: 382))
        let before = view(hidden).applicableFit(for: publicHidden, in: size)
        let after = view(revealed).applicableFit(for: publicRevealed, in: size)
        #expect(before.geometry.size == after.geometry.size)
        #expect(before.geometry.origin == after.geometry.origin)
        #expect(before.bounds == after.bounds)
    }

    @Test(arguments: [CGSize(width: 402, height: 382), CGSize(width: 320, height: 250)])
    func closerNavalInspectionStillKeepsTheWorldOnScreen(container: CGSize) {
        let state = Naval.newGame(seed: 42, playerCount: 4, options: .init())
        let boardView = view(state)
        let viewport = boardView.worldViewport(in: container)
        let fit = boardView.applicableFit(for: boardView.board, in: viewport)
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        for pan in [CGSize(width: 5_000, height: 5_000), CGSize(width: -5_000, height: -5_000)] {
            let camera = BoardCamera(zoom: 100, pan: pan)
                .clamped(fittedBounds: fit.bounds, container: viewport,
                         maximumZoom: boardView.cameraMaximumZoom)
            let shown = camera.projectedBounds(ofFitted: fit.bounds, containerCenter: center)
            #expect(camera.zoom == BoardView.navalMaximumZoom)
            #expect(shown.minX <= 0.01 && shown.maxX >= viewport.width - 0.01)
            #expect(shown.minY <= 0.01 && shown.maxY >= viewport.height - 0.01)
        }
    }

    @Test(arguments: [UInt64(1), UInt64(17), UInt64(42)])
    func islandPortsFaceWaterRatherThanTheWorldCenter(seed: UInt64) throws {
        let state = Naval.newGame(seed: seed, playerCount: 4, options: .init(fogEnabled: false))
        let board = Naval.visibleBoard(in: state)
        let geometry = HexGeometry(origin: .zero, size: 40)
        let points = TileDrawing.portIconPoints(board: board, geometry: geometry, boardCenter: .zero)
        for (index, port) in board.ports.enumerated() {
            let shared = Set(port.vertexA.touchingTiles).intersection(port.vertexB.touchingTiles)
            let land = try #require(board.tiles.first { shared.contains($0.coordinate) && $0.kind != .sea })
            let a = geometry.vertexPosition(port.vertexA, board: board)
            let b = geometry.vertexPosition(port.vertexB, board: board)
            let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let landward = geometry.center(of: land.coordinate)
            let offshore = points[index]
            let direction = (offshore.x - midpoint.x) * (midpoint.x - landward.x)
                + (offshore.y - midpoint.y) * (midpoint.y - landward.y)
            #expect(direction > 0, "Port badge was placed on the landward side of its coastline")
        }
    }

    @Test(arguments: 0..<6)
    func adjacentWorldShipTargetsAlwaysOfferBothIdentities(direction: Int) {
        let origin = HexCoordinate(q: 0, r: 0)
        let ships = [Ship(id: 8, owner: .init(index: 0), coordinate: origin),
                     Ship(id: 2, owner: .init(index: 1), coordinate: origin.neighbor(direction))]
        let geometry = HexGeometry(origin: CGPoint(x: 200, y: 150), size: 9.6)
        for coordinate in ships.map(\.coordinate) {
            #expect(NavalShipHitTargets.nearbyShips(to: coordinate, ships: ships, geometry: geometry).map(\.id) == [2, 8])
        }
        #expect(NavalShipHitTargets.diameter(geometry: geometry) == 44)
    }

    @Test func stackedAndAdjacentCandidatesAreStableAndExcludeDistantShips() {
        let origin = HexCoordinate(q: 0, r: 0)
        let ships = [Ship(id: 8, owner: .init(index: 0), coordinate: origin),
                     Ship(id: 2, owner: .init(index: 1), coordinate: origin.neighbor(0)),
                     Ship(id: 4, owner: .init(index: 2), coordinate: origin),
                     Ship(id: 1, owner: .init(index: 3), coordinate: .init(q: 7, r: 0))]
        let geometry = HexGeometry(origin: .zero, size: 9.6)
        for ordering in [ships, ships.reversed().map { $0 }] {
            #expect(NavalShipHitTargets.nearbyShips(to: origin, ships: ordering, geometry: geometry).map(\.id) == [2, 4, 8])
        }
    }

    @Test func closerInspectionKeepsIsolatedShipsDirectAndStacksExplicit() {
        let origin = HexCoordinate(q: 0, r: 0)
        let ships = [Ship(id: 0, owner: .init(index: 0), coordinate: origin),
                     Ship(id: 1, owner: .init(index: 1), coordinate: origin.neighbor(0)),
                     Ship(id: 2, owner: .init(index: 2), coordinate: origin)]
        let geometry = HexGeometry(origin: .zero, size: 40)
        #expect(NavalShipHitTargets.nearbyShips(to: origin, ships: ships, geometry: geometry).map(\.id) == [0, 2])
        #expect(NavalShipHitTargets.nearbyShips(to: ships[1].coordinate, ships: ships, geometry: geometry).map(\.id) == [1])
    }

    @Test(arguments: [NavalQAFixture.Position.adjacentShips, .stackedShips])
    func nearbyShipFixturesAreConservedProductionPositions(position: NavalQAFixture.Position) throws {
        let state = try NavalQAFixture.make(position)
        let ships = try #require(state.naval?.ships)
        #expect(ships.count == (position == .stackedShips ? 3 : 2))
        #expect(ships[0].coordinate.distance(to: ships[1].coordinate) == 1)
        #expect(ships[0].stepsRemaining == 2 && ships[1].stepsRemaining == 1)
        for resource in Resource.allCases {
            #expect(state.bank[resource, default: 0]
                + state.players.reduce(0) { $0 + $1.resources[resource, default: 0] } == 38)
        }
        try GameSession(state: state, policies: [:], policySeed: 0).checkpoint.validate()
    }

    @Test func overlappingWorldSeaTargetsResolveTheirActualCentersWithoutRevealingFog() throws {
        let model = isolatedGameViewModel()
        model.replaceStateForTesting(try NavalQAFixture.make(.adjacentShips), humanSeat: .init(index: 0))
        let before = model.state
        #expect(model.selectBoardTarget(.ship(0)))
        let presentation = try #require(model.boardDecisionPresentation)
        let publicBoard = Naval.visibleBoard(in: before)
        let geometry = HexGeometry(origin: CGPoint(x: 200, y: 150), size: 9.6)
        #expect(presentation.legalTiles.count >= 3)
        for coordinate in presentation.legalTiles {
            let resolved = BoardDropTargetResolver.nearest(to: geometry.center(of: coordinate),
                decision: presentation, board: publicBoard, geometry: geometry)
            #expect(resolved == .tile(coordinate))
            #expect(model.selectBoardTarget(try #require(resolved)))
            #expect(model.boardDecisionPresentation?.selectedTile == coordinate)
            #expect(model.state == before, "Previewing an overlapping destination must not commit, reveal or advance RNG")
        }
        #expect(model.cancelBoardDecision())
        #expect(model.state == before)
    }

    @Test func equidistantSeaTouchesHaveStableOrderAndDistantTouchesDoNothing() throws {
        let state = try NavalQAFixture.make(.adjacentShips)
        let model = isolatedGameViewModel()
        model.replaceStateForTesting(state, humanSeat: .init(index: 0))
        #expect(model.selectBoardTarget(.ship(0)))
        var decision = try #require(model.boardDecisionPresentation)
        let tiles = decision.legalTiles.sorted()
        let first = try #require(tiles.first)
        let second = try #require(tiles.first { first.distance(to: $0) == 1 })
        decision = seaDecision(tiles: [second, first])
        let geometry = HexGeometry(origin: .zero, size: 9.6)
        let a = geometry.center(of: first), b = geometry.center(of: second)
        let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let board = Naval.visibleBoard(in: state)
        let reverse = seaDecision(tiles: [first, second])
        #expect(BoardDropTargetResolver.nearest(to: midpoint, decision: decision, board: board, geometry: geometry)
            == BoardDropTargetResolver.nearest(to: midpoint, decision: reverse, board: board, geometry: geometry))
        #expect(BoardDropTargetResolver.nearest(to: CGPoint(x: 1_000, y: 1_000),
            decision: decision, board: board, geometry: geometry) == nil)
    }

    private func seaDecision(tiles: [HexCoordinate]) -> BoardDecisionPresentation {
        BoardDecisionPresentation(intent: .sailShip, actor: .init(index: 0), setupRound: nil,
            legalVertices: [], legalEdges: [], legalTiles: tiles, legalVictims: [],
            selectedVertex: nil, selectedEdges: [], selectedTile: nil, selectedVictim: nil,
            canConfirm: false, canCancel: true, errorMessage: nil)
    }

    private func view(_ state: GameState) -> BoardView {
        BoardView(state: state, decision: nil, onSelectTarget: { _ in })
    }
}
