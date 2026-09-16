import SwiftUI
import CatanEngine

/// Shared coordinate space for tap and drag inputs on the fitted board.
enum BoardDecisionCoordinateSpace {
    static let name = "board-decision-coordinate-space"
}

/// The interactive controls laid beneath canonical roads and buildings.
///
/// `BoardView` owns rendering order; this adapter owns only command targets and
/// translates every tap into the same typed `BoardTarget` used by drag/drop.
struct BoardDecisionTargetLayer: View {
    let board: Board
    let decision: BoardDecisionPresentation
    let geometry: HexGeometry
    let onSelectTarget: (BoardTarget) -> Void

    var body: some View {
        ZStack {
            if decision.intent.isRobber {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(tileTapGesture)
                    .accessibilityHidden(true)
                tileTargets
            }
            edgeTargets
            vertexTargets
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var tileTargets: some View {
        let legalTiles = Set(decision.legalTiles)
        ForEach(board.tiles.filter { legalTiles.contains($0.coordinate) }, id: \.coordinate) { tile in
            let isSelected = tile.coordinate == decision.selectedTile
            TileTapTarget(
                position: geometry.center(of: tile.coordinate),
                diameter: max(44, geometry.size * 1.35),
                isEnabled: true,
                isSelected: isSelected,
                accessibilityIdentifier: AccessibilityID.Board.tile(tile.coordinate),
                accessibilityLabel: tileAccessibilityLabel(tile),
                accessibilityValue: isSelected ? "Selected destination" : "Available destination",
                accessibilityHint: targetAccessibilityHint(isSelected: isSelected),
                onTap: { onSelectTarget(.tile(tile.coordinate)) }
            )
        }
    }

    private var edgeTargets: some View {
        ForEach(Array(decision.legalEdges.enumerated()), id: \.element) { index, edge in
            let (startVertex, endVertex) = board.vertices(of: edge)
            let isSelected = decision.selectedEdges.contains(edge)
            EdgeTapTarget(
                start: geometry.vertexPosition(startVertex, board: board),
                end: geometry.vertexPosition(endVertex, board: board),
                isHighlighted: true,
                isEnabled: true,
                isSelected: isSelected,
                accessibilityIdentifier: AccessibilityID.Board.edge(edge),
                accessibilityLabel: edgeAccessibilityLabel(index: index),
                accessibilityValue: isSelected ? "Selected" : "Available",
                accessibilityHint: targetAccessibilityHint(isSelected: isSelected),
                onTap: { onSelectTarget(.edge(edge)) }
            )
        }
    }

    private var vertexTargets: some View {
        ForEach(Array(decision.legalVertices.enumerated()), id: \.element) { index, vertex in
            let isSelected = vertex == decision.selectedVertex
            VertexTapTarget(
                position: geometry.vertexPosition(vertex, board: board),
                isHighlighted: true,
                isEnabled: true,
                isSelected: isSelected,
                highlightDiameter: VertexTapTarget.highlightDiameter(spacing: geometry.size),
                accessibilityIdentifier: AccessibilityID.Board.vertex(vertex),
                accessibilityLabel: vertexAccessibilityLabel(index: index),
                accessibilityValue: isSelected ? "Selected" : "Available",
                accessibilityHint: targetAccessibilityHint(isSelected: isSelected),
                onTap: { onSelectTarget(.vertex(vertex)) }
            )
        }
    }

    private var tileTapGesture: some Gesture {
        SpatialTapGesture().onEnded { value in
            guard let target = BoardDropTargetResolver.nearest(
                to: value.location,
                decision: decision,
                board: board,
                geometry: geometry
            ), case .tile(let tile) = target else { return }
            onSelectTarget(.tile(tile))
        }
    }

    private func tileAccessibilityLabel(_ tile: Tile) -> String {
        let contents: String
        switch tile.kind {
        case .resource(let resource):
            contents = tile.numberToken.map { "\(resource.rawValue), number \($0)" }
                ?? resource.rawValue
        case .desert:
            contents = "desert"
        }
        let source = decision.intent == .knight ? "Knight" : "rolled seven"
        return "Preview \(source) robber move to \(contents)"
    }

    private func vertexAccessibilityLabel(index: Int) -> String {
        let action = decision.intent == .initialSettlement ? "Preview initial settlement" :
            decision.intent == .buildCity ? "Preview city" : "Preview settlement"
        return "\(action) at legal corner \(index + 1) of \(decision.legalVertices.count)"
    }

    private func edgeAccessibilityLabel(index: Int) -> String {
        let action: String
        switch decision.intent {
        case .initialRoad: action = "Preview initial road"
        case .roadBuilding where decision.selectedEdges.isEmpty:
            action = "Preview first Road Building road"
        case .roadBuilding: action = "Preview second Road Building road"
        default: action = "Preview road"
        }
        return "\(action) at legal edge \(index + 1) of \(decision.legalEdges.count)"
    }

    private func targetAccessibilityHint(isSelected: Bool) -> String {
        isSelected
            ? "Selected. Choose another highlighted target to revise before confirming."
            : "Stages this target without changing the game. Confirm in the board action dock."
    }
}

/// The draggable piece and its drag-follow feedback, drawn above every
/// canonical and provisional board layer.
struct BoardDecisionCradleLayer: View {
    let board: Board
    let decision: BoardDecisionPresentation
    let geometry: HexGeometry
    let containerSize: CGSize
    let civilization: Civilization
    let onSelectTarget: (BoardTarget) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var draggedPieceLocation: CGPoint?

    var body: some View {
        let piece = BoardDecisionPieceKind(intent: decision.intent)
        let ordinal = roadOrdinal
        ZStack {
            Color.clear.allowsHitTesting(false)
            BoardDecisionCradle(
                piece: piece,
                civilization: civilization,
                roadOrdinal: ordinal,
                isDragging: draggedPieceLocation != nil,
                accessibilityLabel: cradleAccessibilityLabel
            )
            .position(cradlePosition)
            .gesture(cradleDragGesture)

            if let draggedPieceLocation, !reduceMotion {
                BoardDecisionDragToken(
                    piece: piece,
                    civilization: civilization,
                    roadOrdinal: ordinal
                )
                .position(draggedPieceLocation)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cradleDragGesture: some Gesture {
        DragGesture(
            minimumDistance: 3,
            coordinateSpace: .named(BoardDecisionCoordinateSpace.name)
        )
        .updating($draggedPieceLocation) { value, location, _ in
            location = value.location
        }
        .onEnded { value in
            guard let target = BoardDropTargetResolver.nearest(
                to: value.location,
                decision: decision,
                board: board,
                geometry: geometry
            ) else { return }
            onSelectTarget(target)
        }
    }

    private var cradlePosition: CGPoint {
        CGPoint(
            x: max(Layout.cradleEdgeInset, containerSize.width - Layout.cradleEdgeInset),
            y: max(Layout.cradleEdgeInset, containerSize.height - Layout.cradleEdgeInset)
        )
    }

    private var roadOrdinal: Int? {
        guard decision.intent == .roadBuilding else { return nil }
        return min(decision.selectedEdges.count + 1, 2)
    }

    private var cradleAccessibilityLabel: String {
        switch decision.intent {
        case .initialSettlement: "Initial settlement drag piece"
        case .initialRoad: "Initial road drag piece"
        case .buildRoad: "Road drag piece"
        case .buildSettlement: "Settlement drag piece"
        case .buildCity: "City drag piece"
        case .roadBuilding: "Road Building road \(roadOrdinal ?? 1) drag piece"
        case .robberAfterSeven: "Rolled seven robber drag piece"
        case .knight: "Knight robber drag piece"
        }
    }

    private enum Layout {
        static let cradleEdgeInset: CGFloat = 35
    }
}

/// Pure nearest-target geometry shared by taps and drags.
private enum BoardDropTargetResolver {
    static func nearest(
        to point: CGPoint,
        decision: BoardDecisionPresentation,
        board: Board,
        geometry: HexGeometry
    ) -> BoardTarget? {
        let candidates = legalTargets(decision: decision, board: board, geometry: geometry)
        guard let nearest = candidates.min(by: {
            distance($0.point, point) < distance($1.point, point)
        }) else { return nil }
        let radius = dropRadius(for: nearest.target, geometry: geometry)
        return distance(nearest.point, point) <= radius ? nearest.target : nil
    }

    private static func legalTargets(
        decision: BoardDecisionPresentation,
        board: Board,
        geometry: HexGeometry
    ) -> [(target: BoardTarget, point: CGPoint)] {
        let vertices = decision.legalVertices.map {
            (BoardTarget.vertex($0), geometry.vertexPosition($0, board: board))
        }
        let edges = decision.legalEdges.map {
            (BoardTarget.edge($0), geometry.edgeMidpoint($0, board: board))
        }
        let tiles = decision.legalTiles.map {
            (BoardTarget.tile($0), geometry.center(of: $0))
        }
        return vertices + edges + tiles
    }

    private static func dropRadius(for target: BoardTarget, geometry: HexGeometry) -> CGFloat {
        switch target {
        case .tile: max(Layout.minimumRadius, geometry.size * 0.92)
        case .vertex, .edge: max(Layout.minimumRadius, geometry.size * 0.72)
        case .victim: 0
        }
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private enum Layout {
        static let minimumRadius: CGFloat = 30
    }
}
