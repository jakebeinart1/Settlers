import SwiftUI
import CatanEngine

/// Captures which interaction owns a drag when its fingers first move.
///
/// Drawing and hit testing use the same camera-applied geometry. Ownership is
/// retained through an invalid drop or cancellation: a piece drag must never
/// become a camera pan. The cradle keeps its existing target handler; only a
/// canonical robber start can emit a target here, and that target is a proposal.
struct BoardGestureRouter {
    enum Origin: Equatable { case camera, cradle, robber }

    static let panSlop: CGFloat = 12

    let origin: Origin
    private let initialState: GameState
    private let initialDecision: BoardDecisionPresentation?
    private let initialCamera: BoardCamera
    private(set) var isCancelled = false

    init(startLocation: CGPoint, state: GameState, decision: BoardDecisionPresentation?,
         geometry: HexGeometry, camera: BoardCamera, containerSize: CGSize,
         allowsGameCommands: Bool) {
        initialState = state
        initialDecision = decision
        initialCamera = camera
        origin = Self.origin(at: startLocation, state: state, decision: decision,
            geometry: geometry, containerSize: containerSize, allowsGameCommands: allowsGameCommands)
    }

    mutating func cancel() { isCancelled = true }

    func pannedCamera(by translation: CGSize) -> BoardCamera? {
        guard !isCancelled, origin == .camera,
              initialCamera.zoom > BoardCamera.minZoom else { return nil }
        return initialCamera.panned(by: translation)
    }

    /// Reject stale/privacy-boundary releases before resolving a legal tile.
    /// Radius matches the existing cradle's tile-drop policy; the viewport check
    /// also prevents an off-board release from snapping to a nearby legal tile.
    /// Exclude the entire current hex before snapping: its edge can lie within
    /// the minimum drop radius of a legal neighbor even though it is illegal.
    func dropTarget(at location: CGPoint, state: GameState,
                    decision: BoardDecisionPresentation?, geometry: HexGeometry,
                    containerSize: CGSize, allowsGameCommands: Bool) -> BoardTarget? {
        guard !isCancelled, origin == .robber, state == initialState,
              decision == initialDecision,
              Self.canDragRobber(state: state, decision: decision, allowsGameCommands: allowsGameCommands),
              CGRect(origin: .zero, size: containerSize).contains(location), let decision else { return nil }
        guard !TileDrawing.hexPath(for: state.board.robberTile, geometry: geometry).contains(location) else { return nil }
        let destinations = decision.legalTiles.filter { $0 != state.board.robberTile }
        guard let nearest = destinations.min(by: {
            Self.distance(geometry.center(of: $0), location) < Self.distance(geometry.center(of: $1), location)
        }) else { return nil }
        let radius = max(Layout.minimumDropRadius, geometry.size * Layout.tileDropRadiusFactor)
        return Self.distance(geometry.center(of: nearest), location) <= radius ? .tile(nearest) : nil
    }

    private static func origin(at point: CGPoint, state: GameState,
                               decision: BoardDecisionPresentation?, geometry: HexGeometry,
                               containerSize: CGSize, allowsGameCommands: Bool) -> Origin {
        guard CGRect(origin: .zero, size: containerSize).contains(point) else { return .camera }
        if allowsGameCommands, let decision, !decision.intent.usesMaritimePieces {
            let cradle = CGPoint(x: max(Layout.cradleEdgeInset, containerSize.width - Layout.cradleEdgeInset),
                                 y: max(Layout.cradleEdgeInset, containerSize.height - Layout.cradleEdgeInset))
            let bounds = CGRect(x: cradle.x - Layout.cradleEdgeInset, y: cradle.y - Layout.cradleEdgeInset,
                                width: Layout.cradleEdgeInset * 2, height: Layout.cradleEdgeInset * 2)
            if bounds.contains(point) { return .cradle }
        }
        guard canDragRobber(state: state, decision: decision, allowsGameCommands: allowsGameCommands) else { return .camera }
        // drawRobberOrigin's ring reaches 0.34 + half its 0.07 stroke.
        let radius = max(Layout.minimumOriginRadius, geometry.size * Layout.originRadiusFactor)
        return distance(point, geometry.center(of: state.board.robberTile)) <= radius ? .robber : .camera
    }

    private static func canDragRobber(state: GameState, decision: BoardDecisionPresentation?,
                                      allowsGameCommands: Bool) -> Bool {
        // The coordinator supplies the claimed local-human actor; GameView
        // supplies command permission. The engine deliberately has no humans.
        guard allowsGameCommands, let decision, decision.intent.isRobber,
              !decision.legalTiles.isEmpty,
              state.phase.awaitingSeatIndex == decision.actor.index else { return false }
        return switch (decision.intent, state.phase) {
        case (.robberAfterSeven, .movingRobber), (.knight, .rollDice), (.knight, .mainTurn): true
        default: false
        }
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private enum Layout {
        // Existing BoardDecisionCradleLayer's inset; covers its painted tray
        // and shadow so the simultaneous camera drag cannot grab its corners.
        static let cradleEdgeInset: CGFloat = 35
        static let minimumOriginRadius: CGFloat = 22
        static let originRadiusFactor: CGFloat = 0.375
        static let minimumDropRadius: CGFloat = 30
        static let tileDropRadiusFactor: CGFloat = 0.92
    }
}

extension BoardView {
    /// Replaces the unconditional simultaneous pan. The existing cradle drag
    /// continues independently; this recognizer only suppresses its camera pan.
    /// Retain the old board pan threshold so legal-target taps keep their slop.
    func routedDrag(fit: BoardFit, container: CGSize, geometry: HexGeometry) -> some Gesture {
        DragGesture(minimumDistance: BoardGestureRouter.panSlop, coordinateSpace: .named(BoardDecisionCoordinateSpace.name))
            .updating($boardDragLocation) { value, location, _ in location = value.location }
            .onChanged { value in
                if boardDrag == nil {
                    boardDrag = BoardGestureRouter(startLocation: value.startLocation, state: state,
                        decision: decision, geometry: geometry, camera: camera,
                        containerSize: container, allowsGameCommands: allowsGameCommands)
                }
                if gestureAnchor != nil { boardDrag?.cancel() }
                if let panned = boardDrag?.pannedCamera(by: value.translation) {
                    camera = panned.clamped(fittedBounds: fit.bounds, container: container, maximumZoom: cameraMaximumZoom)
                }
            }
            .onEnded { value in
                defer { boardDrag = nil }
                guard gestureAnchor == nil,
                      let target = boardDrag?.dropTarget(at: value.location, state: state,
                        decision: decision, geometry: geometry, containerSize: container,
                        allowsGameCommands: allowsGameCommands) else { return }
                onSelectTarget(target)
            }
    }

    @ViewBuilder
    var robberDragFeedback: some View {
        if boardDrag?.origin == .robber, boardDrag?.isCancelled == false,
           let boardDragLocation, let decision, !reduceMotion {
            BoardDecisionDragToken(piece: .robber,
                civilization: playerIdentity(decision.actor).civilization, roadOrdinal: nil)
                .position(boardDragLocation)
                .allowsHitTesting(false)
        }
    }
}
