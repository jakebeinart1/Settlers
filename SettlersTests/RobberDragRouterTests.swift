import CoreGraphics
import Testing
import CatanEngine
@testable import Settlers

@MainActor
@Suite("Robber drag coordinates")
struct RobberDragRouterTests {
    private let container = CGSize(width: 402, height: 300)
    private let actor = PlayerID(index: 2)

    @Test(arguments: [BoardDecisionIntent.robberAfterSeven, .knight])
    func currentRobberUsesRenderedCoordinatesAcrossCameras(_ intent: BoardDecisionIntent) throws {
        let (state, decision) = try fixture(intent)
        let fit = BoardView.solvedFit(for: state.board, in: container)
        let center = CGPoint(x: container.width / 2, y: container.height / 2)
        for requested in cameras {
            let camera = requested.clamped(fittedBounds: fit.bounds, container: container)
            let geometry = camera.applied(to: fit.geometry, containerCenter: center)
            let start = geometry.center(of: state.board.robberTile)
            // Position the canonical robber centrally in this coordinate fixture
            // so every transformed disc remains inside the clipped viewport.
            #expect(CGRect(origin: .zero, size: container).contains(start))
            let router = BoardGestureRouter(startLocation: start, state: state,
                decision: decision, geometry: geometry, camera: camera,
                containerSize: container, allowsGameCommands: true)
            #expect(router.origin == .robber)
            #expect(router.pannedCamera(by: CGSize(width: 45, height: -30)) == nil)
            let tile = try #require(decision.legalTiles.first {
                CGRect(origin: .zero, size: container).contains(geometry.center(of: $0))
            })
            #expect(router.dropTarget(at: geometry.center(of: tile), state: state,
                decision: decision, geometry: geometry, containerSize: container,
                allowsGameCommands: true) == .tile(tile))
        }
    }

    @Test func literalTransformedCoordinatesRejectTheUntransformedOriginAndDrop() throws {
        let (state, fullDecision) = try fixture(.robberAfterSeven)
        let tile = HexCoordinate(q: 1, r: 0)
        #expect(fullDecision.legalTiles.contains(tile))
        let decision = singleDestination(tile, from: fullDecision)
        let fit = HexGeometry(origin: CGPoint(x: 180, y: 140), size: 40)
        let camera = BoardCamera(zoom: 2, pan: CGSize(width: 65, height: -35))
        let geometry = camera.applied(to: fit, containerCenter: CGPoint(x: 201, y: 150))
        // Independently calculated similarity transform, not coordinates
        // obtained by calling the same center function as the router.
        let start = CGPoint(x: 224, y: 95)
        let destination = CGPoint(x: 362.5640646055102, y: 95)
        let router = BoardGestureRouter(startLocation: start, state: state,
            decision: decision, geometry: geometry, camera: camera,
            containerSize: container, allowsGameCommands: true)
        #expect(router.origin == .robber)
        #expect(self.router(at: fit.origin, state: state, decision: decision, geometry: geometry).origin == .camera)
        #expect(router.dropTarget(at: destination, state: state, decision: decision,
            geometry: geometry, containerSize: container, allowsGameCommands: true) == .tile(tile))
        #expect(router.dropTarget(at: destination, state: state, decision: decision,
            geometry: fit, containerSize: container, allowsGameCommands: true) == nil)
    }

    @Test func originDiscBoundaryScalesWithZoomAndHasAMinimumTouchSize() throws {
        let (state, decision) = try fixture(.robberAfterSeven)
        for size in [20.0 as CGFloat, 80] {
            let geometry = HexGeometry(origin: CGPoint(x: 201, y: 150), size: size)
            let radius = max(22, size * 0.375)
            let inside = CGPoint(x: 201 + radius - 0.01, y: 150)
            let outside = CGPoint(x: 201 + radius + 0.01, y: 150)
            #expect(router(at: inside, state: state, decision: decision, geometry: geometry).origin == .robber)
            #expect(router(at: outside, state: state, decision: decision, geometry: geometry).origin == .camera)
        }
    }

    @Test func invalidReleasePreservesSelectionAndNeverBecomesAPan() throws {
        let (state, decision) = try fixture(.robberAfterSeven)
        let geometry = HexGeometry(origin: CGPoint(x: 201, y: 150), size: 32)
        let router = router(at: geometry.origin, state: state, decision: decision, geometry: geometry)
        for point in [geometry.origin, CGPoint(x: -1, y: 150), CGPoint(x: 403, y: 150),
                      CGPoint(x: 201, y: -1), CGPoint(x: 201, y: 301)] {
            #expect(router.dropTarget(at: point, state: state, decision: decision,
                geometry: geometry, containerSize: container, allowsGameCommands: true) == nil)
        }
        #expect(router.pannedCamera(by: CGSize(width: 200, height: 0)) == nil)
    }

    @Test(arguments: [BoardDecisionIntent.robberAfterSeven, .knight])
    func releaseInsideCurrentHexCannotSnapToItsLegalNeighbors(_ intent: BoardDecisionIntent) throws {
        let (state, decision) = try fixture(intent)
        let fit = Settlers.HexGeometry(origin: CGPoint(x: 201, y: 150), size: 32)
        let center = CGPoint(x: 201, y: 150)
        for camera in [.fitted, BoardCamera(zoom: 1.5, pan: CGSize(width: 10, height: -6)),
                       BoardCamera(zoom: 2, pan: CGSize(width: -20, height: 12))] {
            let geometry = camera.applied(to: fit, containerCenter: center)
            let origin = geometry.center(of: state.board.robberTile)
            let router = BoardGestureRouter(startLocation: origin, state: state,
                decision: decision, geometry: geometry, camera: camera,
                containerSize: container, allowsGameCommands: true)
            // At size 32, x + 26.9 is inside the current hex's vertical
            // edge (27.7128), yet only 28.5256 from the legal east neighbor.
            for direction in 0..<6 {
                let tile = state.board.robberTile.neighbor(direction)
                #expect(decision.legalTiles.contains(tile))
                let neighbor = geometry.center(of: tile)
                let distance = hypot(neighbor.x - origin.x, neighbor.y - origin.y)
                let fraction = 26.9 * camera.zoom / distance
                let inside = CGPoint(x: origin.x + (neighbor.x - origin.x) * fraction,
                                     y: origin.y + (neighbor.y - origin.y) * fraction)
                #expect(router.dropTarget(at: inside, state: state, decision: decision,
                    geometry: geometry, containerSize: container, allowsGameCommands: true) == nil)
            }
            let outside = CGPoint(x: origin.x + geometry.size * sqrt(3) / 2 + 0.01, y: origin.y)
            #expect(router.dropTarget(at: outside, state: state, decision: decision,
                geometry: geometry, containerSize: container, allowsGameCommands: true)
                    == .tile(HexCoordinate(q: 1, r: 0)))
        }
    }

    @Test func dropRadiusMatchesCradlePolicyButRejectsOffViewportTiles() throws {
        let (state, fullDecision) = try fixture(.robberAfterSeven)
        let tile = try #require(fullDecision.legalTiles.first)
        let decision = singleDestination(tile, from: fullDecision)
        let viewport = CGSize(width: 1_000, height: 1_000)
        for size in [20.0 as CGFloat, 80] {
            let geometry = HexGeometry(origin: CGPoint(x: 500, y: 500), size: size)
            let router = BoardGestureRouter(startLocation: geometry.origin, state: state,
                decision: decision, geometry: geometry, camera: .fitted,
                containerSize: viewport, allowsGameCommands: true)
            let target = geometry.center(of: tile)
            let radius = max(30, size * 0.92)
            let inside = CGPoint(x: target.x + radius - 0.01, y: target.y)
            let outside = CGPoint(x: target.x + radius + 0.01, y: target.y)
            #expect(router.dropTarget(at: inside, state: state, decision: decision,
                geometry: geometry, containerSize: viewport, allowsGameCommands: true) == .tile(tile))
            #expect(router.dropTarget(at: outside, state: state, decision: decision,
                geometry: geometry, containerSize: viewport, allowsGameCommands: true) == nil)
            let offscreen = HexGeometry(origin: CGPoint(x: 2_000, y: 2_000), size: size)
            #expect(router.dropTarget(at: offscreen.center(of: tile), state: state,
                decision: decision, geometry: offscreen, containerSize: viewport,
                allowsGameCommands: true) == nil)
        }
    }

    @Test func inactiveOrWrongSeatOriginUsesNormalCameraPan() throws {
        let (state, decision) = try fixture(.robberAfterSeven)
        let geometry = HexGeometry(origin: CGPoint(x: 201, y: 150), size: 32)
        let camera = BoardCamera(zoom: 2, pan: CGSize(width: 10, height: -5))
        var wrongSeat = state
        wrongSeat.phase = .movingRobber(playerIndex: 0)
        var wrongPhase = state
        wrongPhase.phase = .rollDice(playerIndex: actor.index)
        for (position, presentation, enabled) in [(state, decision, false),
                                                (wrongSeat, decision, true),
                                                (wrongPhase, decision, true)] {
            let router = BoardGestureRouter(startLocation: geometry.origin,
                state: position, decision: presentation, geometry: geometry,
                camera: camera, containerSize: container, allowsGameCommands: enabled)
            #expect(router.origin == .camera)
            #expect(router.pannedCamera(by: CGSize(width: 25, height: 30))
                    == BoardCamera(zoom: 2, pan: CGSize(width: 35, height: 25)))
        }
        let inactive = BoardGestureRouter(startLocation: geometry.origin, state: state,
            decision: nil, geometry: geometry, camera: .fitted,
            containerSize: container, allowsGameCommands: true)
        #expect(inactive.origin == .camera)
        #expect(inactive.pannedCamera(by: CGSize(width: 25, height: 30)) == nil)
    }

    @Test func cradleWinsOverRobberAndSuppressesSimultaneousPan() throws {
        let (state, decision) = try fixture(.knight)
        let cradle = CGPoint(x: container.width - 35, y: container.height - 35)
        let geometry = HexGeometry(origin: cradle, size: 32)
        let router = router(at: cradle, state: state, decision: decision, geometry: geometry)
        #expect(router.origin == .cradle)
        #expect(router.pannedCamera(by: CGSize(width: -50, height: -50)) == nil)
        #expect(router.dropTarget(at: geometry.center(of: decision.legalTiles[0]),
            state: state, decision: decision, geometry: geometry,
            containerSize: container, allowsGameCommands: true) == nil,
            "the existing cradle handler remains the only emitter for cradle drops")
    }

    @Test func cancellationOrChangedContextCannotEmitAStaleDrop() throws {
        let (state, decision) = try fixture(.knight)
        let geometry = HexGeometry(origin: CGPoint(x: 201, y: 150), size: 32)
        var router = router(at: geometry.origin, state: state, decision: decision, geometry: geometry)
        let target = geometry.center(of: decision.legalTiles[0])
        var advanced = state
        advanced.phase = .mainTurn(playerIndex: actor.index)
        for (position, presentation, enabled) in [(advanced, decision, true),
                                                (state, decision, false)] {
            #expect(router.dropTarget(at: target, state: position, decision: presentation,
                geometry: geometry, containerSize: container, allowsGameCommands: enabled) == nil)
        }
        #expect(router.dropTarget(at: target, state: state, decision: nil,
            geometry: geometry, containerSize: container, allowsGameCommands: true) == nil)
        var revised = BoardDecisionCoordinator()
        let beganRevised = revised.begin(.knight, with: context(state))
        #expect(beganRevised)
        let selectedRevised = revised.select(.tile(decision.legalTiles[0]))
        #expect(selectedRevised)
        #expect(router.dropTarget(at: target, state: state, decision: revised.presentation,
            geometry: geometry, containerSize: container, allowsGameCommands: true) == nil)
        router.cancel()
        #expect(router.dropTarget(at: target, state: state, decision: decision,
            geometry: geometry, containerSize: container, allowsGameCommands: true) == nil)
        #expect(router.pannedCamera(by: CGSize(width: 20, height: 20)) == nil)
    }

    private var cameras: [BoardCamera] {
        [.fitted, BoardCamera(zoom: 1.4, pan: .zero),
         BoardCamera(zoom: 2, pan: CGSize(width: 24, height: -18)),
         BoardCamera(zoom: 3, pan: CGSize(width: -35, height: 25))]
    }

    private func router(at point: CGPoint, state: GameState,
                        decision: BoardDecisionPresentation, geometry: HexGeometry) -> BoardGestureRouter {
        BoardGestureRouter(startLocation: point, state: state, decision: decision,
            geometry: geometry, camera: BoardCamera(zoom: 2),
            containerSize: container, allowsGameCommands: true)
    }

    private func fixture(_ intent: BoardDecisionIntent) throws -> (GameState, BoardDecisionPresentation) {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7_401)
        state.board.robberTile = HexCoordinate(q: 0, r: 0)
        state.phase = intent == .knight ? .rollDice(playerIndex: actor.index) : .movingRobber(playerIndex: actor.index)
        state.players[actor.index].devCards = [.knight]
        var coordinator = BoardDecisionCoordinator()
        coordinator.reconcile(with: context(state))
        if intent == .knight {
            let began = coordinator.begin(.knight, with: context(state))
            #expect(began)
        }
        return (state, try #require(coordinator.presentation))
    }

    private func context(_ state: GameState) -> BoardDecisionContext {
        BoardDecisionContext(matchID: nil, committedMoveCount: 0, actor: actor, state: state)
    }

    private func singleDestination(_ tile: HexCoordinate,
                                   from decision: BoardDecisionPresentation) -> BoardDecisionPresentation {
        BoardDecisionPresentation(intent: decision.intent, actor: decision.actor,
            setupRound: nil, legalVertices: [], legalEdges: [], legalTiles: [tile],
            legalVictims: [], selectedVertex: nil, selectedEdges: [], selectedTile: nil,
            selectedVictim: nil, canConfirm: false, canCancel: false, errorMessage: nil)
    }
}
