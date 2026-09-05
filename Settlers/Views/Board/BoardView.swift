import SwiftUI
import CatanEngine

/// The hex-board play surface: draws all tiles, number tokens, the robber,
/// and ports via `Canvas`, layers invisible tap targets over every on-board
/// vertex/edge (plus the tiles themselves) for building, and draws
/// settlements/cities/roads as animated `Shape`s colored by owning player on
/// top of all of it. The stacking order is deliberate and load-bearing: the
/// tap targets' placement highlights belong *under* the pieces - see the
/// comment on that layer in `body`.
public struct BoardView: View {
    public let state: GameState
    public let playerIdentity: (PlayerID) -> PlayerIdentity
    public let onTapVertex: (VertexID) -> Void
    public let onTapEdge: (EdgeID) -> Void
    public let onTapTile: (HexCoordinate) -> Void
    /// When non-empty, only these vertices are tappable (highlighted with a
    /// glow ring); every other vertex is dimmed and ignores taps. `nil` sets
    /// (the default `[]` for both) mean "no vertex/edge placement mode" -
    /// see `highlightedEdges` for the edge equivalent. The two are
    /// independent so, e.g., a settlement placement can highlight vertices
    /// while leaving edges untouched.
    public let highlightedVertices: Set<VertexID>
    /// Same as `highlightedVertices`, for edges (road placement).
    public let highlightedEdges: Set<EdgeID>
    /// Roads selected as part of an uncommitted multi-road card. They are
    /// drawn in the owner's color with a gold preview border, but never added
    /// to `GameState` until the complete move is confirmed.
    public let stagedRoads: Set<EdgeID>
    public let stagedRoadOwner: PlayerID?
    /// True while any placement mode (vertex or edge) is active, so
    /// non-highlighted tap targets can be disabled/dimmed even when their own
    /// highlight set happens to be empty (e.g. edges during a settlement
    /// placement).
    public let isPlacementModeActive: Bool
    /// While `isTileTargetingActive`, tiles in this set (the legal robber
    /// destinations) are outlined so they read as tappable; every other tile
    /// is dimmed. Mirrors `highlightedVertices`/`highlightedEdges` for the
    /// inline robber-move flow (see `GameView`).
    public let highlightedTiles: Set<HexCoordinate>
    public let isTileTargetingActive: Bool
    /// Tiles matching the most recent dice roll, briefly outlined right
    /// after a roll - purely a visual cue for where production came from,
    /// distinct from `highlightedTiles`' robber-targeting purpose (both can
    /// technically be active at once, though in practice a mandatory robber
    /// move only follows a 7, which never has producing tiles to highlight).
    public let rollHighlightTiles: Set<HexCoordinate>

    public init(
        state: GameState,
        playerIdentity: @escaping (PlayerID) -> PlayerIdentity = CatanTheme.playerIdentity,
        onTapVertex: @escaping (VertexID) -> Void,
        onTapEdge: @escaping (EdgeID) -> Void,
        onTapTile: @escaping (HexCoordinate) -> Void,
        highlightedVertices: Set<VertexID> = [],
        highlightedEdges: Set<EdgeID> = [],
        stagedRoads: Set<EdgeID> = [],
        stagedRoadOwner: PlayerID? = nil,
        isPlacementModeActive: Bool = false,
        highlightedTiles: Set<HexCoordinate> = [],
        isTileTargetingActive: Bool = false,
        rollHighlightTiles: Set<HexCoordinate> = []
    ) {
        self.state = state
        self.playerIdentity = playerIdentity
        self.onTapVertex = onTapVertex
        self.onTapEdge = onTapEdge
        self.onTapTile = onTapTile
        self.highlightedVertices = highlightedVertices
        self.highlightedEdges = highlightedEdges
        self.stagedRoads = stagedRoads
        self.stagedRoadOwner = stagedRoadOwner
        self.isPlacementModeActive = isPlacementModeActive
        self.highlightedTiles = highlightedTiles
        self.isTileTargetingActive = isTileTargetingActive
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
                // No opaque fill here anymore - `GameView`'s scenic
                // background painting shows through the gaps around the
                // hex cluster and behind the ports, the way it does behind
                // the rest of the board screen. See design-references/STATUS.md.

                Canvas { context, _ in
                    // Two passes rather than one: every tile's fill has to
                    // finish drawing *before* any tile's highlight ring
                    // does, or a later tile in `board.tiles`' iteration
                    // order paints its own manila frame right over the
                    // shared-edge half of an earlier tile's ring - the roll
                    // highlight looked "inconsistent" because whether that
                    // happened (and which side got clipped) depended on
                    // draw order relative to that tile's neighbors.
                    for tile in board.tiles {
                        TileDrawing.drawTile(tile, geometry: geometry, in: context)
                    }
                    for tile in board.tiles where isTileTargetingActive {
                        let path = TileDrawing.hexPath(for: tile.coordinate, geometry: geometry)
                        if highlightedTiles.contains(tile.coordinate) {
                            context.stroke(path, with: .color(.yellow), lineWidth: 3)
                        } else {
                            context.fill(path, with: .color(.black.opacity(0.45)))
                        }
                    }
                    for port in board.ports {
                        TileDrawing.drawPort(port, geometry: geometry, board: board, boardCenter: boardCenter, in: context)
                    }
                    let robberTileNumber = board.tiles.first { $0.coordinate == board.robberTile }?.numberToken
                    TileDrawing.drawRobber(at: board.robberTile, number: robberTileNumber, geometry: geometry, in: context)
                }
                .contentShape(Rectangle())
                .gesture(tileTapGesture(geometry: geometry))

                // One semantic target per tile while the robber chooser is
                // active. The Canvas gesture keeps ordinary touch input fast,
                // but a Canvas exposes no individual hexes to XCUITest or
                // VoiceOver; without these targets, "choose a tile" was a
                // visual-only interaction that could not be reached or proved
                // through accessibility. They sit below edge/vertex targets
                // and exist only during tile targeting.
                if isTileTargetingActive {
                    ForEach(board.tiles, id: \.coordinate) { tile in
                        TileTapTarget(
                            position: geometry.center(of: tile.coordinate),
                            diameter: max(44, geometry.size * 1.25),
                            isEnabled: highlightedTiles.contains(tile.coordinate),
                            accessibilityIdentifier: AccessibilityID.Board.tile(tile.coordinate),
                            accessibilityLabel: tileAccessibilityLabel(tile),
                            onTap: { onTapTile(tile.coordinate) }
                        )
                    }
                }

                // Placement targets sit BELOW the pieces, not above them.
                // Their yellow highlights are a hint about what you may do
                // next; the pieces are the game state itself, and a hint must
                // never repaint state. Drawn last (the previous order), the
                // three legal road edges radiating from a just-placed
                // settlement laid three `Color.yellow.opacity(0.55)` capsules
                // across it - stacked, that is ~0.91 effective alpha, so the
                // piece read as a solid yellow blob for as long as the road
                // placement stayed armed and then "changed colour" the instant
                // the road went down and the highlights cleared. Reported as
                // "it's the wrong colour and then it switches colours" during
                // setup.
                //
                // Hit testing is unaffected by the move: every piece layer
                // above these is `.allowsHitTesting(false)`, so taps fall
                // straight through to the targets, and the tile `Canvas`'s own
                // gesture is still further below. A highlight can now be partly
                // covered by a piece, which is the correct direction - a legal
                // vertex never holds a building and a legal edge never holds a
                // road, so only the rounded joint of an adjacent road ever
                // overlaps one.
                ForEach(sortedEdges, id: \.self) { edge in
                    let (a, b) = board.vertices(of: edge)
                    EdgeTapTarget(
                        start: geometry.vertexPosition(a, board: board),
                        end: geometry.vertexPosition(b, board: board),
                        isHighlighted: highlightedEdges.contains(edge),
                        isEnabled: !isPlacementModeActive || highlightedEdges.contains(edge),
                        accessibilityIdentifier: AccessibilityID.Board.edge(edge),
                        onTap: { onTapEdge(edge) }
                    )
                }

                ForEach(sortedVertices, id: \.self) { vertex in
                    VertexTapTarget(
                        position: geometry.vertexPosition(vertex, board: board),
                        isHighlighted: highlightedVertices.contains(vertex),
                        isEnabled: !isPlacementModeActive || highlightedVertices.contains(vertex),
                        accessibilityIdentifier: AccessibilityID.Board.vertex(vertex),
                        onTap: { onTapVertex(vertex) }
                    )
                }

                roadViews(geometry: geometry)

                if let stagedRoadOwner, !stagedRoads.isEmpty {
                    stagedRoadPreview(geometry: geometry, owner: stagedRoadOwner)
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
            }
            .animation(.spring(), value: BoardSnapshot(state: state))
        }
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

    /// A visibly provisional road. The bright border differentiates it from
    /// committed state even when the player's road color is already pale,
    /// while translucency keeps the next legal yellow targets readable.
    private func stagedRoadPreview(geometry: HexGeometry, owner: PlayerID) -> some View {
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
            borderPath.fill(.yellow.opacity(0.95))
            fillPath.fill(playerIdentity(owner).civilization.accentColor.opacity(0.72))
        }
        .shadow(color: .yellow.opacity(0.45), radius: 3)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Staged road preview")
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
            guard let tile = nearestTile(to: value.location, geometry: geometry) else { return }
            onTapTile(tile)
        }
    }

    private func nearestTile(to point: CGPoint, geometry: HexGeometry) -> HexCoordinate? {
        board.tiles
            .map { ($0.coordinate, geometry.center(of: $0.coordinate)) }
            .min { lhs, rhs in
                let dl = hypot(lhs.1.x - point.x, lhs.1.y - point.y)
                let dr = hypot(rhs.1.x - point.x, rhs.1.y - point.y)
                return dl < dr
            }?.0
    }

    private func tileAccessibilityLabel(_ tile: Tile) -> String {
        let contents: String
        switch tile.kind {
        case .resource(let resource):
            contents = tile.numberToken.map { "\(resource.rawValue), number \($0)" } ?? resource.rawValue
        case .desert:
            contents = "desert"
        }
        return "Move robber to \(contents)"
    }

    // MARK: - Stable ordering

    private var sortedVertices: [VertexID] {
        board.onBoardVertices.sorted()
    }

    private var sortedEdges: [EdgeID] {
        board.onBoardEdges.sorted { lhs, rhs in
            (lhs.a, lhs.b) < (rhs.a, rhs.b)
        }
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
