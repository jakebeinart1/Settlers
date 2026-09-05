import SwiftUI
import CatanEngine

/// The fitted hex-board renderer for canonical pieces and uncommitted spatial
/// proposals.
///
/// `BoardDecisionPresentation` is the complete rendering contract: this view
/// never reconstructs legality and never emits a `GameMove`. Taps, drags,
/// VoiceOver activation, and UI automation all send one typed `BoardTarget`
/// through `onSelectTarget`; confirmation remains outside the board. The layer
/// order is deliberate and load-bearing: legal-target hints sit below committed
/// pieces, while unmistakably provisional previews sit above them.
public struct BoardView: View {
    public let state: GameState
    public let playerIdentity: (PlayerID) -> PlayerIdentity
    public let decision: BoardDecisionPresentation?
    public let onSelectTarget: (BoardTarget) -> Void
    /// False during inspect-only mandatory decisions. The board stays visible,
    /// but vertex, edge and tile command targets leave both hit testing and
    /// the accessibility tree. Non-mutating camera gestures can remain on the
    /// board container independently when the board gains them.
    public let allowsGameCommands: Bool
    /// Tiles matching the most recent dice roll, briefly outlined right
    /// after a roll - purely a visual cue for where production came from,
    /// distinct from a board decision's legal robber destinations. Both can
    /// technically be present, though a mandatory robber move follows a 7,
    /// which has no producing tiles to highlight.
    public let rollHighlightTiles: Set<HexCoordinate>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var draggedPieceLocation: CGPoint?

    private static let boardCoordinateSpace = "board-decision-coordinate-space"
    private static let cradleEdgeInset: CGFloat = 35
    private static let dragDropMinimumRadius: CGFloat = 30

    public init(
        state: GameState,
        playerIdentity: @escaping (PlayerID) -> PlayerIdentity = CatanTheme.playerIdentity,
        decision: BoardDecisionPresentation?,
        onSelectTarget: @escaping (BoardTarget) -> Void,
        allowsGameCommands: Bool = true,
        rollHighlightTiles: Set<HexCoordinate> = []
    ) {
        self.state = state
        self.playerIdentity = playerIdentity
        self.decision = decision
        self.onSelectTarget = onSelectTarget
        self.allowsGameCommands = allowsGameCommands
        self.rollHighlightTiles = rollHighlightTiles
    }

    private var board: Board { state.board }

    public var body: some View {
        GeometryReader { proxy in
            // A plain cosmetic margin, and nothing more. It used to be 16pt
            // standing in for the port badges' overhang, because
            // `fittedGeometry` measured only the tile corners and something had
            // to cover what was drawn outside them. That guess is now
            // redundant: the fit measures the badges and reserves the vertex
            // rings itself, so leaving 16 here reserved the same space a second
            // time and visibly shrank the board.
            let geometry = Self.fittedGeometry(for: board, in: CGRect(origin: .zero, size: proxy.size),
                                               padding: Self.boardPadding)
            let boardCenter = Self.boardCenter(for: board, geometry: geometry)
            let ownership = Ownership(players: state.players)

            ZStack {
                boardCanvas(geometry: geometry, boardCenter: boardCenter)

                if !allowsGameCommands {
                    BoardInspectionSemantics(
                        state: state,
                        geometry: geometry,
                        boardCenter: boardCenter,
                        playerIdentity: playerIdentity
                    )
                }

                // Interactive target layers remain below every canonical
                // piece. This prevents a road glow from repainting a
                // settlement at their shared vertex while hit testing still
                // falls through the non-interactive piece layers above it.
                if allowsGameCommands, let decision {
                    tileTargets(for: decision, geometry: geometry)
                    edgeTargets(for: decision, geometry: geometry)
                    vertexTargets(for: decision, geometry: geometry)
                }

                roadViews(geometry: geometry)

                if let decision, !decision.selectedEdges.isEmpty {
                    stagedRoadPreview(for: decision, geometry: geometry)
                }

                // Drawn as its own layer, above roads (which the base tile
                // `Canvas` sits behind - a rolled tile's own ring used to be
                // drawn as part of that same `Canvas`, so any road crossing
                // near the tile's edge could visually cut into it) but below
                // buildings, so the ring never covers a settlement/city sitting
                // right on the tile's corner.
                if !rollHighlightTiles.isEmpty {
                    Canvas { context, _ in
                        for tile in board.tiles where rollHighlightTiles.contains(tile.coordinate) {
                            // Inset slightly (matches the resource-fill hex,
                            // not the full manila frame) so the ring sits
                            // cleanly within the tile's own fill rather than
                            // straddling the ambiguous seam with its
                            // neighbors.
                            let path = TileDrawing.hexPath(for: tile.coordinate, geometry: geometry, scale: 0.93)
                            context.stroke(path, with: .color(.white), lineWidth: 6)
                        }
                    }
                    .allowsHitTesting(false)
                }

                buildingViews(geometry: geometry, ownership: ownership)

                if let decision {
                    cityUpgradeGuides(for: decision, geometry: geometry)
                    stagedBuildingPreview(for: decision, geometry: geometry)
                    stagedRobberPreview(for: decision, geometry: geometry)
                    robberMarkerSemantics(for: decision, geometry: geometry)
                }

                if allowsGameCommands, let decision {
                    decisionCradle(for: decision, geometry: geometry, containerSize: proxy.size)
                }
            }
            .coordinateSpace(name: Self.boardCoordinateSpace)
            .animation(reduceMotion ? nil : .spring(), value: BoardSnapshot(state: state))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: decision)
        }
    }

    // MARK: - Board decision layers

    private func boardCanvas(geometry: HexGeometry, boardCenter: CGPoint) -> some View {
        Canvas { context, _ in
            drawTiles(geometry: geometry, in: context)
            drawRobberTargeting(geometry: geometry, in: context)
            for port in board.ports {
                TileDrawing.drawPort(
                    port,
                    geometry: geometry,
                    board: board,
                    boardCenter: boardCenter,
                    in: context
                )
            }
            drawCanonicalRobber(geometry: geometry, in: context)
        }
        .contentShape(Rectangle())
        .gesture(tileTapGesture(geometry: geometry))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Game board")
        .accessibilityIdentifier(AccessibilityID.Board.surface)
    }

    /// Tiles are completed before any target outline. Drawing highlights in
    /// the tile loop lets a later neighbor repaint half of an earlier ring.
    private func drawTiles(geometry: HexGeometry, in context: GraphicsContext) {
        for tile in board.tiles {
            TileDrawing.drawTile(tile, geometry: geometry, in: context)
        }
    }

    private func drawRobberTargeting(geometry: HexGeometry, in context: GraphicsContext) {
        guard let decision, decision.intent.isRobber else { return }
        let legalTiles = Set(decision.legalTiles)
        for tile in board.tiles {
            let path = TileDrawing.hexPath(for: tile.coordinate, geometry: geometry)
            if tile.coordinate == decision.selectedTile {
                context.fill(path, with: .color(CatanTheme.cityPennantGold.opacity(0.1)))
                context.stroke(path, with: .color(CatanTheme.cityPennantGold), lineWidth: 5)
            } else if legalTiles.contains(tile.coordinate) {
                context.stroke(path, with: .color(CatanTheme.cityPennantGold.opacity(0.92)), lineWidth: 3)
            } else {
                context.fill(path, with: .color(.black.opacity(0.24)))
            }
        }
    }

    private func drawCanonicalRobber(geometry: HexGeometry, in context: GraphicsContext) {
        let number = board.tiles.first { $0.coordinate == board.robberTile }?.numberToken
        if decision?.intent.isRobber == true {
            TileDrawing.drawRobberOrigin(
                at: board.robberTile,
                number: number,
                geometry: geometry,
                in: context
            )
        } else {
            TileDrawing.drawRobber(at: board.robberTile, number: number, geometry: geometry, in: context)
        }
    }

    @ViewBuilder
    private func tileTargets(for decision: BoardDecisionPresentation, geometry: HexGeometry) -> some View {
        if decision.intent.isRobber {
            let legalTiles = Set(decision.legalTiles)
            ForEach(board.tiles.filter { legalTiles.contains($0.coordinate) }, id: \.coordinate) { tile in
                let isSelected = tile.coordinate == decision.selectedTile
                TileTapTarget(
                    position: geometry.center(of: tile.coordinate),
                    diameter: max(44, geometry.size * 1.35),
                    isEnabled: true,
                    isSelected: isSelected,
                    accessibilityIdentifier: AccessibilityID.Board.tile(tile.coordinate),
                    accessibilityLabel: tileAccessibilityLabel(tile, decision: decision),
                    accessibilityValue: isSelected ? "Selected destination" : "Available destination",
                    accessibilityHint: boardTargetAccessibilityHint(isSelected: isSelected),
                    onTap: { onSelectTarget(.tile(tile.coordinate)) }
                )
            }
        }
    }

    @ViewBuilder
    private func edgeTargets(for decision: BoardDecisionPresentation, geometry: HexGeometry) -> some View {
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
                accessibilityLabel: edgeAccessibilityLabel(index: index, decision: decision),
                accessibilityValue: isSelected ? "Selected" : "Available",
                accessibilityHint: boardTargetAccessibilityHint(isSelected: isSelected),
                onTap: { onSelectTarget(.edge(edge)) }
            )
        }
    }

    @ViewBuilder
    private func vertexTargets(for decision: BoardDecisionPresentation, geometry: HexGeometry) -> some View {
        ForEach(Array(decision.legalVertices.enumerated()), id: \.element) { index, vertex in
            let isSelected = vertex == decision.selectedVertex
            VertexTapTarget(
                position: geometry.vertexPosition(vertex, board: board),
                isHighlighted: true,
                isEnabled: true,
                isSelected: isSelected,
                accessibilityIdentifier: AccessibilityID.Board.vertex(vertex),
                accessibilityLabel: vertexAccessibilityLabel(index: index, decision: decision),
                accessibilityValue: isSelected ? "Selected" : "Available",
                accessibilityHint: boardTargetAccessibilityHint(isSelected: isSelected),
                onTap: { onSelectTarget(.vertex(vertex)) }
            )
        }
    }

    @ViewBuilder
    private func stagedBuildingPreview(
        for decision: BoardDecisionPresentation,
        geometry: HexGeometry
    ) -> some View {
        if let vertex = decision.selectedVertex,
           let isCity = stagedBuildingIsCity(for: decision.intent) {
            let civilization = playerIdentity(decision.actor).civilization
            let correction = civilization.pieceSizeCorrection(isCity: isCity)
            let size = geometry.size * (isCity ? 0.98 : 0.78) * correction
            ProvisionalBuildingBadge(
                civilization: civilization,
                isCity: isCity,
                size: size,
                accessibilityLabel: isCity ? "Staged city preview" : "Staged settlement preview"
            )
            .position(geometry.vertexPosition(vertex, board: board))
        }
    }

    /// City targets are the one legal vertex target that necessarily already
    /// contains a canonical piece. The ordinary target ring belongs below
    /// pieces (otherwise road hints recolor settlements), so a separate
    /// outline is drawn above eligible settlements. It surrounds the artwork
    /// without covering it and makes "choose a highlighted settlement" true
    /// on screen rather than merely true to accessibility.
    @ViewBuilder
    private func cityUpgradeGuides(
        for decision: BoardDecisionPresentation,
        geometry: HexGeometry
    ) -> some View {
        if decision.intent == .buildCity {
            ForEach(decision.legalVertices, id: \.self) { vertex in
                let isSelected = decision.selectedVertex == vertex
                ZStack {
                    Circle()
                        .strokeBorder(Color.black.opacity(0.9), lineWidth: isSelected ? 6 : 5)
                    Circle()
                        .strokeBorder(
                            CatanTheme.cityPennantGold.opacity(isSelected ? 1 : 0.9),
                            lineWidth: isSelected ? 3.5 : 2.5
                        )
                }
                .frame(width: geometry.size * 0.92, height: geometry.size * 0.92)
                .shadow(color: CatanTheme.cityPennantGold.opacity(0.45), radius: 2)
                .position(geometry.vertexPosition(vertex, board: board))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func stagedBuildingIsCity(for intent: BoardDecisionIntent) -> Bool? {
        switch intent {
        case .initialSettlement, .buildSettlement: false
        case .buildCity: true
        default: nil
        }
    }

    @ViewBuilder
    private func stagedRobberPreview(
        for decision: BoardDecisionPresentation,
        geometry: HexGeometry
    ) -> some View {
        if decision.intent.isRobber, let tile = decision.selectedTile {
            Canvas { context, _ in
                let number = board.tiles.first { $0.coordinate == tile }?.numberToken
                TileDrawing.drawRobberPreview(at: tile, number: number, geometry: geometry, in: context)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func robberMarkerSemantics(
        for decision: BoardDecisionPresentation,
        geometry: HexGeometry
    ) -> some View {
        if decision.intent.isRobber {
            boardMarker(
                position: geometry.center(of: board.robberTile),
                identifier: AccessibilityID.Board.robberOrigin,
                label: "Current robber territory",
                value: "Origin; the robber has not moved"
            )
            if let selectedTile = decision.selectedTile {
                boardMarker(
                    position: geometry.center(of: selectedTile),
                    identifier: AccessibilityID.Board.stagedRobberPreview,
                    label: "Staged robber destination",
                    value: "Proposed; not yet moved"
                )
            }
        }
    }

    private func boardMarker(position: CGPoint, identifier: String, label: String, value: String) -> some View {
        Circle()
            .fill(Color.white.opacity(0.001))
            .frame(width: 44, height: 44)
            .position(position)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(label)
            .accessibilityValue(value)
    }

    @ViewBuilder
    private func decisionCradle(
        for decision: BoardDecisionPresentation,
        geometry: HexGeometry,
        containerSize: CGSize
    ) -> some View {
        let civilization = playerIdentity(decision.actor).civilization
        let piece = BoardDecisionPieceKind(intent: decision.intent)
        let ordinal = roadOrdinal(for: decision)
        BoardDecisionCradle(
            piece: piece,
            civilization: civilization,
            roadOrdinal: ordinal,
            isDragging: draggedPieceLocation != nil,
            accessibilityLabel: cradleAccessibilityLabel(for: decision)
        )
        .position(cradlePosition(in: containerSize))
        .gesture(cradleDragGesture(for: decision, geometry: geometry))

        // Direct dragging still selects the same nearest legal target with
        // Reduce Motion enabled, but the cradle's opacity is the only moving
        // feedback; a second token no longer chases the player's finger.
        if let draggedPieceLocation, !reduceMotion {
            BoardDecisionDragToken(piece: piece, civilization: civilization, roadOrdinal: ordinal)
                .position(draggedPieceLocation)
        }
    }

    private func cradleDragGesture(
        for decision: BoardDecisionPresentation,
        geometry: HexGeometry
    ) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.boardCoordinateSpace))
            .updating($draggedPieceLocation) { value, location, _ in
                location = value.location
            }
            .onEnded { value in
                guard let target = nearestDropTarget(to: value.location, decision: decision, geometry: geometry) else {
                    return
                }
                onSelectTarget(target)
            }
    }

    private func nearestDropTarget(
        to point: CGPoint,
        decision: BoardDecisionPresentation,
        geometry: HexGeometry
    ) -> BoardTarget? {
        let candidates = legalDropTargets(for: decision, geometry: geometry)
        guard let nearest = candidates.min(by: { distance($0.point, point) < distance($1.point, point) }) else {
            return nil
        }
        let radius = dropRadius(for: nearest.target, geometry: geometry)
        return distance(nearest.point, point) <= radius ? nearest.target : nil
    }

    private func legalDropTargets(
        for decision: BoardDecisionPresentation,
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

    private func dropRadius(for target: BoardTarget, geometry: HexGeometry) -> CGFloat {
        switch target {
        case .tile: max(Self.dragDropMinimumRadius, geometry.size * 0.92)
        case .vertex, .edge: max(Self.dragDropMinimumRadius, geometry.size * 0.72)
        case .victim: 0
        }
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func cradlePosition(in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(Self.cradleEdgeInset, size.width - Self.cradleEdgeInset),
            y: max(Self.cradleEdgeInset, size.height - Self.cradleEdgeInset)
        )
    }

    private func roadOrdinal(for decision: BoardDecisionPresentation) -> Int? {
        guard decision.intent == .roadBuilding else { return nil }
        return min(decision.selectedEdges.count + 1, 2)
    }

    private func cradleAccessibilityLabel(for decision: BoardDecisionPresentation) -> String {
        switch decision.intent {
        case .initialSettlement: "Initial settlement drag piece"
        case .initialRoad: "Initial road drag piece"
        case .buildRoad: "Road drag piece"
        case .buildSettlement: "Settlement drag piece"
        case .buildCity: "City drag piece"
        case .roadBuilding: "Road Building road \(roadOrdinal(for: decision) ?? 1) drag piece"
        case .robberAfterSeven: "Rolled seven robber drag piece"
        case .knight: "Knight robber drag piece"
        }
    }

    private func vertexAccessibilityLabel(index: Int, decision: BoardDecisionPresentation) -> String {
        let action = decision.intent == .initialSettlement ? "Preview initial settlement" :
            decision.intent == .buildCity ? "Preview city" : "Preview settlement"
        return "\(action) at legal corner \(index + 1) of \(decision.legalVertices.count)"
    }

    private func edgeAccessibilityLabel(index: Int, decision: BoardDecisionPresentation) -> String {
        let action: String
        switch decision.intent {
        case .initialRoad: action = "Preview initial road"
        case .roadBuilding where decision.selectedEdges.isEmpty: action = "Preview first Road Building road"
        case .roadBuilding: action = "Preview second Road Building road"
        default: action = "Preview road"
        }
        return "\(action) at legal edge \(index + 1) of \(decision.legalEdges.count)"
    }

    private func boardTargetAccessibilityHint(isSelected: Bool) -> String {
        isSelected
            ? "Selected. Choose another highlighted target to revise before confirming."
            : "Stages this target without changing the game. Confirm in the board action dock."
    }

    // MARK: - Pieces

    @ViewBuilder
    private func buildingViews(geometry: HexGeometry, ownership: Ownership) -> some View {
        ForEach(sortedVertices, id: \.self) { vertex in
            if let owner = ownership.owner(ofSettlementOrCity: vertex) {
                let position = geometry.vertexPosition(vertex, board: board)
                // Settlements bumped up from 0.48, then again from 0.58 -
                // pieces read as too small on the actual board, especially
                // once `CivilizationBadge` added the etched detail/pennant
                // (which need real size to stay legible). Cities nudged up
                // too, so the settlement -> city size jump stays clearly
                // noticeable rather than shrinking once settlements got
                // closer to their old size.
                let civilization = playerIdentity(owner.player).civilization
                let size = geometry.size * (owner.isCity ? 0.87 : 0.68) * civilization.pieceSizeCorrection(isCity: owner.isCity)
                CivilizationBadge(civilization: civilization, isCity: owner.isCity, size: size)
                    // A small grounding shadow - pieces sat perfectly flat
                    // against the tile texture before, with nothing to
                    // separate them from the board underneath.
                    .shadow(color: .black.opacity(0.45), radius: 1.5, x: 0, y: size * 0.05)
                    .position(position)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Tried using each civilization's actual wall/path artwork here too,
    /// rotated to each edge's angle - it doesn't work: those source pieces
    /// are each a different, mostly-square aspect ratio, and force-fitting
    /// one into a long thin rotated bar just shows a cropped, misaligned
    /// slice of it rather than a coherent road. A flat civilization-colored
    /// bar reads far more cleanly at this size and angle range.
    ///
    /// Drawn per *player* rather than per edge: each of a player's road
    /// segments still starts life as the same rounded-rect bar as before,
    /// but every segment is geometrically unioned into one combined `Path`
    /// (`Path.union`) before it's ever filled or bordered, so two segments
    /// sharing a vertex merge into one shape instead of two separate
    /// bordered rectangles butting against each other - the black border
    /// only ever traces the *outside* of a player's whole connected road
    /// network, never a seam at an internal joint. Same two-layer
    /// bigger-shape-then-smaller-shape trick `TileDrawing.drawTile` uses
    /// for the manila gap between tiles: a wider black union filled first,
    /// then a narrower colored union on top leaves a uniform border ring
    /// showing only around the true outline.
    /// Rendered in ascending road-count order, so whoever has more roads
    /// draws *last* (on top) wherever two different players' networks
    /// happen to touch the same vertex - a player with two roads meeting
    /// there (part of a longer connected chain) reads better sitting over
    /// a neighbor with just one isolated segment there than the reverse.
    /// A per-player approximation rather than tracking it per contested
    /// vertex (which the current whole-network-per-player `Path.union`
    /// approach doesn't cleanly support) - fine in practice since draw
    /// order only matters at all where two players' roads actually meet.
    @ViewBuilder
    private func roadViews(geometry: HexGeometry) -> some View {
        ForEach(state.players.sorted { $0.roads.count < $1.roads.count }, id: \.id) { player in
            if !player.roads.isEmpty {
                // Border margin bumped from a fixed 0.07 addition (barely
                // visible at typical board scale, especially once
                // `Path.union` softened it further at every joint) to a
                // proportionally bigger, near-opaque ring - it needs to
                // read unmistakably as a border around the whole connected
                // shape, not just a faint edge.
                let overlap = geometry.size * 0.05
                let fillHeight = geometry.size * 0.20
                let borderHeight = geometry.size * 0.30
                let borderPath = unionedRoadPath(for: player.roads, geometry: geometry, height: borderHeight, overlap: overlap)
                let fillPath = unionedRoadPath(for: player.roads, geometry: geometry, height: fillHeight, overlap: overlap)

                ZStack {
                    borderPath.fill(.black.opacity(0.9))
                    fillPath.fill(playerIdentity(player.id).civilization.accentColor)
                }
                // Same small grounding shadow as `CivilizationBadge` -
                // consistent depth cue across every piece on the board.
                .shadow(color: .black.opacity(0.4), radius: 1.2, x: 0, y: geometry.size * 0.015)
                .allowsHitTesting(false)
            }
        }
    }

    /// A visibly provisional road. Road Building retains the coordinator's
    /// ordered edge array and adds numbered seals; the set is used only for the
    /// geometric union that removes seams where the two previews meet.
    private func stagedRoadPreview(
        for decision: BoardDecisionPresentation,
        geometry: HexGeometry
    ) -> some View {
        let stagedRoads = Set(decision.selectedEdges)
        let overlap = geometry.size * 0.05
        let borderPath = unionedRoadPath(
            for: stagedRoads,
            geometry: geometry,
            height: geometry.size * 0.32,
            overlap: overlap
        )
        let fillPath = unionedRoadPath(
            for: stagedRoads,
            geometry: geometry,
            height: geometry.size * 0.20,
            overlap: overlap
        )
        return ZStack {
            borderPath.fill(CatanTheme.cityPennantGold.opacity(0.98))
            fillPath.fill(playerIdentity(decision.actor).civilization.accentColor.opacity(0.72))
            if decision.intent == .roadBuilding {
                ForEach(Array(decision.selectedEdges.enumerated()), id: \.element) { index, edge in
                    BoardRoadOrderBadge(ordinal: index + 1)
                        .position(geometry.edgeMidpoint(edge, board: board))
                }
            }
        }
        .shadow(color: CatanTheme.cityPennantGold.opacity(0.55), radius: 3)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(
            decision.selectedEdges.count == 1 ? "Staged road preview" : "Two staged road previews"
        )
        .accessibilityValue("Proposed, not yet built")
        .accessibilityIdentifier(AccessibilityID.Board.stagedRoadPreview)
    }

    /// The union of every edge in `edges`, each first built as the same
    /// rectangular bar `RoadShape` always used, positioned/rotated onto its
    /// actual board edge via `roadSegmentPath` - see `roadViews` for why
    /// this needs to be a true geometric union rather than separately
    /// filled/bordered shapes. A plain rectangle union alone still isn't
    /// enough, though: two straight bars meeting at an angle leave a
    /// wedge-shaped gap on the outside of the bend (each bar's end is cut
    /// perpendicular to *its own* axis, not angled to the bisector between
    /// the two) - a classic "miter join" problem, confirmed by rendering
    /// this in isolation and seeing the exact notch. The fix is the
    /// standard one: union in a filled circle at every vertex a road in
    /// this set touches, which closes that gap regardless of angle (a
    /// "round join") and, as a side effect, gives dead-end tips a clean
    /// rounded cap too.
    private func unionedRoadPath(for edges: Set<EdgeID>, geometry: HexGeometry, height: CGFloat, overlap: CGFloat) -> Path {
        var result = Path()
        var vertices: Set<VertexID> = []
        for edge in edges {
            let (a, b) = board.vertices(of: edge)
            let start = geometry.vertexPosition(a, board: board)
            let end = geometry.vertexPosition(b, board: board)
            let segment = roadSegmentPath(from: start, to: end, height: height, overlap: overlap)
            result = result.isEmpty ? segment : result.union(segment)
            vertices.insert(a)
            vertices.insert(b)
        }
        let radius = height / 2
        for vertex in vertices {
            let center = geometry.vertexPosition(vertex, board: board)
            let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            result = result.union(circle)
        }
        return result
    }

    /// One road edge's bar, built in its own local (unrotated, centered-at-
    /// origin) coordinate space via `RoadShape` and then transformed onto
    /// its actual position/angle between `start` and `end` - kept as a
    /// standalone `Path` (rather than a positioned/rotated `View`, the old
    /// approach) specifically so `unionedRoadPath` can combine several of
    /// these with `Path.union` before any fill/stroke happens.
    private func roadSegmentPath(from start: CGPoint, to end: CGPoint, height: CGFloat, overlap: CGFloat) -> Path {
        let length = hypot(end.x - start.x, end.y - start.y) + overlap
        let angle = atan2(end.y - start.y, end.x - start.x)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let localRect = CGRect(x: -length / 2, y: -height / 2, width: length, height: height)
        let transform = CGAffineTransform(rotationAngle: angle)
            .concatenating(CGAffineTransform(translationX: midpoint.x, y: midpoint.y))
        return RoadShape().path(in: localRect).applying(transform)
    }

    // MARK: - Gestures

    private func tileTapGesture(geometry: HexGeometry) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            guard allowsGameCommands, let decision, decision.intent.isRobber else { return }
            guard let target = nearestDropTarget(
                to: value.location,
                decision: decision,
                geometry: geometry
            ), case .tile(let tile) = target else { return }
            onSelectTarget(.tile(tile))
        }
    }

    private func tileAccessibilityLabel(
        _ tile: Tile,
        decision: BoardDecisionPresentation
    ) -> String {
        let contents: String
        switch tile.kind {
        case .resource(let resource):
            contents = tile.numberToken.map { "\(resource.rawValue), number \($0)" } ?? resource.rawValue
        case .desert:
            contents = "desert"
        }
        let source = decision.intent == .knight ? "Knight" : "rolled seven"
        return "Preview \(source) robber move to \(contents)"
    }

    // MARK: - Stable ordering

    private var sortedVertices: [VertexID] {
        board.onBoardVertices.sorted()
    }

    // MARK: - Geometry fitting

    /// Sizes and centers a `HexGeometry` so **everything drawn on the board**
    /// fits within `rect`, inset by `padding` on all sides.
    ///
    /// ## What "everything" means, and why it used to be wrong
    /// This measured the tile corners only. But ports are drawn *offshore* -
    /// pushed out past the shoreline along their edge's normal - so the board
    /// was scaled so the hexes fitted exactly and the port badges hung over the
    /// edges and were clipped, worst at the top and bottom where the margin is
    /// tightest. The fix is to measure what is actually drawn rather than to
    /// shrink the board by a guessed percentage: a fixed 10% would be wrong on
    /// the next screen size, and right here only by luck.
    ///
    /// Two extents are added to the tile bounds:
    ///
    /// - **Ports**, measured in hex-size units through the same
    ///   `TileDrawing.portIconPoint` the renderer uses, so the two cannot drift.
    /// - **Vertex placement rings**, which are a *fixed point size* rather than
    ///   a multiple of the hex, so they cannot go into the scale calculation -
    ///   they come off the available space instead.
    /// Cosmetic margin left around the board, in points.
    ///
    /// A `static` so `BoardFitTests` can assert against the value that actually
    /// ships. When the test hardcoded its own 4, it proved a property of a
    /// number it supplied itself: changing the shipped value to 0 left every
    /// assertion passing while the real board clipped.
    static let boardPadding: CGFloat = 4

    static func fittedGeometry(for board: Board, in rect: CGRect, padding: CGFloat) -> HexGeometry {
        let probe = HexGeometry(origin: .zero, size: 1)
        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for tile in board.tiles {
            for index in 0..<6 {
                let corner = probe.corner(of: tile.coordinate, index: index)
                minX = min(minX, corner.x)
                maxX = max(maxX, corner.x)
                minY = min(minY, corner.y)
                maxY = max(maxY, corner.y)
            }
        }

        guard maxX > minX, maxY > minY else {
            return HexGeometry(origin: CGPoint(x: rect.midX, y: rect.midY), size: 20)
        }

        // Port badges, at the same unit scale. `portIconPoint` needs a board
        // centre; at size 1 that is the mean of the tile centres, exactly as
        // `boardCenter(for:geometry:)` computes it at real scale.
        let probeCenters = board.tiles.map { probe.center(of: $0.coordinate) }
        let probeCenter = CGPoint(
            x: probeCenters.map(\.x).reduce(0, +) / CGFloat(max(probeCenters.count, 1)),
            y: probeCenters.map(\.y).reduce(0, +) / CGFloat(max(probeCenters.count, 1)))
        let badge = TileDrawing.portFrameRadiusFactor
        for port in board.ports {
            let icon = TileDrawing.portIconPoint(a: probe.vertexPosition(port.vertexA, board: board),
                                              b: probe.vertexPosition(port.vertexB, board: board),
                                              boardCenter: probeCenter, size: 1)
            minX = min(minX, icon.x - badge)
            maxX = max(maxX, icon.x + badge)
            minY = min(minY, icon.y - badge)
            maxY = max(maxY, icon.y + badge)
        }

        let availableWidth = max(rect.width - padding * 2, 1)
        let availableHeight = max(rect.height - padding * 2, 1)

        // Vertex placement rings are a FIXED point size, so they cannot go into
        // a scale computed in hex-size units - their extent in those units
        // depends on the very size being solved for. Two passes settle it:
        // solve ignoring them, convert the ring to units at that size, fold it
        // into the tile bounds, solve again.
        //
        // Folding rather than reserving matters. Reserving a flat 11pt on every
        // side, as this first did, takes it even on the sides where a port
        // badge already sticks out four times further and the ring is nowhere
        // near the outer edge - which is board size given away for nothing. The
        // ring only ever binds on a stretch of coast with no port on it.
        func fit(_ boundsMinX: CGFloat, _ boundsMaxX: CGFloat,
                 _ boundsMinY: CGFloat, _ boundsMaxY: CGFloat) -> CGFloat {
            min(availableWidth / (boundsMaxX - boundsMinX), availableHeight / (boundsMaxY - boundsMinY))
        }

        let firstPass = fit(minX, maxX, minY, maxY)
        let ringInUnits = firstPass > 0 ? TileDrawing.vertexRingRadius / firstPass : 0
        for tile in board.tiles {
            for index in 0..<6 {
                let corner = probe.corner(of: tile.coordinate, index: index)
                minX = min(minX, corner.x - ringInUnits)
                maxX = max(maxX, corner.x + ringInUnits)
                minY = min(minY, corner.y - ringInUnits)
                maxY = max(maxY, corner.y + ringInUnits)
            }
        }
        let size = fit(minX, maxX, minY, maxY)

        let boardCenterX = (minX + maxX) / 2 * size
        let boardCenterY = (minY + maxY) / 2 * size
        let origin = CGPoint(x: rect.midX - boardCenterX, y: rect.midY - boardCenterY)
        return HexGeometry(origin: origin, size: size)
    }

    static func boardCenter(for board: Board, geometry: HexGeometry) -> CGPoint {
        let centers = board.tiles.map { geometry.center(of: $0.coordinate) }
        guard !centers.isEmpty else { return .zero }
        let x = centers.map(\.x).reduce(0, +) / CGFloat(centers.count)
        let y = centers.map(\.y).reduce(0, +) / CGFloat(centers.count)
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Ownership lookup

/// A settlement/city owner plus which of the two it is.
private struct BuildingOwner {
    let player: PlayerID
    let isCity: Bool
}

/// Precomputed vertex -> owner lookup, built once per render from
/// `state.players` rather than re-scanning all players per vertex. Roads no
/// longer need an equivalent lookup here - `roadViews` reads `player.roads`
/// directly, once per player, to build each player's unioned road path.
private struct Ownership {
    private let buildings: [VertexID: BuildingOwner]

    init(players: [Player]) {
        var buildings: [VertexID: BuildingOwner] = [:]
        for player in players {
            for vertex in player.settlements {
                buildings[vertex] = BuildingOwner(player: player.id, isCity: false)
            }
            for vertex in player.cities {
                buildings[vertex] = BuildingOwner(player: player.id, isCity: true)
            }
        }
        self.buildings = buildings
    }

    func owner(ofSettlementOrCity vertex: VertexID) -> BuildingOwner? {
        buildings[vertex]
    }
}

// MARK: - Animation trigger

/// A lightweight `Equatable` snapshot of everything `BoardView` renders that
/// can change turn-to-turn, used purely to drive `.animation(_:value:)` -
/// `GameState` itself isn't `Equatable` (it carries bank counts, dev card
/// decks, etc. that don't affect the board), so this narrows to just the
/// pieces and robber position.
private struct BoardSnapshot: Equatable {
    let robberTile: HexCoordinate
    let settlements: [Set<VertexID>]
    let cities: [Set<VertexID>]
    let roads: [Set<EdgeID>]

    init(state: GameState) {
        robberTile = state.board.robberTile
        settlements = state.players.map(\.settlements)
        cities = state.players.map(\.cities)
        roads = state.players.map(\.roads)
    }
}
