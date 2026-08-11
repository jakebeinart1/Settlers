import SwiftUI
import CatanEngine

/// The hex-board play surface: draws all tiles, number tokens, the robber,
/// and ports via `Canvas`, overlays settlements/cities/roads as animated
/// `Shape`s colored by owning player, and overlays invisible tap targets at
/// every on-board vertex/edge (plus the tiles themselves) for building.
public struct BoardView: View {
    public let state: GameState
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
        onTapVertex: @escaping (VertexID) -> Void,
        onTapEdge: @escaping (EdgeID) -> Void,
        onTapTile: @escaping (HexCoordinate) -> Void,
        highlightedVertices: Set<VertexID> = [],
        highlightedEdges: Set<EdgeID> = [],
        isPlacementModeActive: Bool = false,
        highlightedTiles: Set<HexCoordinate> = [],
        isTileTargetingActive: Bool = false,
        rollHighlightTiles: Set<HexCoordinate> = []
    ) {
        self.state = state
        self.onTapVertex = onTapVertex
        self.onTapEdge = onTapEdge
        self.onTapTile = onTapTile
        self.highlightedVertices = highlightedVertices
        self.highlightedEdges = highlightedEdges
        self.isPlacementModeActive = isPlacementModeActive
        self.highlightedTiles = highlightedTiles
        self.isTileTargetingActive = isTileTargetingActive
        self.rollHighlightTiles = rollHighlightTiles
    }

    private var board: Board { state.board }

    public var body: some View {
        GeometryReader { proxy in
            let geometry = Self.fittedGeometry(for: board, in: CGRect(origin: .zero, size: proxy.size), padding: 24)
            let boardCenter = Self.boardCenter(for: board, geometry: geometry)
            let ownership = Ownership(players: state.players)

            ZStack {
                CatanTheme.waterBackground

                Canvas { context, _ in
                    for tile in board.tiles {
                        TileDrawing.drawTile(tile, geometry: geometry, in: context)
                        if isTileTargetingActive {
                            let path = TileDrawing.hexPath(for: tile.coordinate, geometry: geometry)
                            if highlightedTiles.contains(tile.coordinate) {
                                context.stroke(path, with: .color(.yellow), lineWidth: 3)
                            } else {
                                context.fill(path, with: .color(.black.opacity(0.45)))
                            }
                        }
                        if rollHighlightTiles.contains(tile.coordinate) {
                            let path = TileDrawing.hexPath(for: tile.coordinate, geometry: geometry)
                            context.stroke(path, with: .color(.white), lineWidth: 4)
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

                // Invisible per-tile anchors, reported in the shared "game"
                // coordinate space `GameView` establishes - purely so the
                // dice-roll resource-flight animation can launch each flying
                // badge from the actual producing tile's on-screen spot
                // rather than a single shared origin.
                ForEach(board.tiles, id: \.coordinate) { tile in
                    Color.clear
                        .frame(width: 1, height: 1)
                        .position(geometry.center(of: tile.coordinate))
                        .background(
                            GeometryReader { tileGeo in
                                Color.clear.preference(
                                    key: TileCenterKey.self,
                                    value: [tile.coordinate: tileGeo.frame(in: .named("game")).origin]
                                )
                            }
                        )
                        .allowsHitTesting(false)
                }

                roadViews(geometry: geometry, ownership: ownership)
                buildingViews(geometry: geometry, ownership: ownership)

                ForEach(sortedEdges, id: \.self) { edge in
                    let (a, b) = board.vertices(of: edge)
                    EdgeTapTarget(
                        start: geometry.vertexPosition(a, board: board),
                        end: geometry.vertexPosition(b, board: board),
                        isHighlighted: highlightedEdges.contains(edge),
                        isEnabled: !isPlacementModeActive || highlightedEdges.contains(edge),
                        onTap: { onTapEdge(edge) }
                    )
                }

                ForEach(sortedVertices, id: \.self) { vertex in
                    VertexTapTarget(
                        position: geometry.vertexPosition(vertex, board: board),
                        isHighlighted: highlightedVertices.contains(vertex),
                        isEnabled: !isPlacementModeActive || highlightedVertices.contains(vertex),
                        onTap: { onTapVertex(vertex) }
                    )
                }
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
                let size = geometry.size * (owner.isCity ? 0.62 : 0.48)
                let civilization = Civilization.forSeat(owner.player.index)
                CivilizationBadge(civilization: civilization, isCity: owner.isCity, size: size)
                    .position(position)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func roadViews(geometry: HexGeometry, ownership: Ownership) -> some View {
        ForEach(sortedEdges, id: \.self) { edge in
            if let owner = ownership.owner(ofRoad: edge) {
                let (a, b) = board.vertices(of: edge)
                let start = geometry.vertexPosition(a, board: board)
                let end = geometry.vertexPosition(b, board: board)
                let length = hypot(end.x - start.x, end.y - start.y)
                let angle = atan2(end.y - start.y, end.x - start.x)
                let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

                // Tried using each civilization's actual wall/path artwork
                // here too, rotated to the edge's angle - it doesn't work:
                // those source pieces are each a different, mostly-square
                // aspect ratio, and force-fitting one into a long thin
                // rotated bar just shows a cropped, misaligned slice of it
                // rather than a coherent road. A flat civilization-colored
                // bar reads far more cleanly at this size and angle range.
                RoadShape()
                    .fill(CatanTheme.color(for: owner))
                    .overlay(RoadShape().stroke(.black.opacity(0.6), lineWidth: 1))
                    .frame(width: length * 0.8, height: geometry.size * 0.22)
                    .rotationEffect(.radians(angle))
                    .position(midpoint)
                    .allowsHitTesting(false)
            }
        }
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

    /// Sizes and centers a `HexGeometry` so the whole board fits within
    /// `rect`, inset by `padding` on all sides. Measures the board's extent
    /// at `size: 1` first, then scales to fit.
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

        let availableWidth = max(rect.width - padding * 2, 1)
        let availableHeight = max(rect.height - padding * 2, 1)
        let size = min(availableWidth / (maxX - minX), availableHeight / (maxY - minY))

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

/// Precomputed vertex/edge -> owner lookups, built once per render from
/// `state.players` rather than re-scanning all players per vertex/edge.
private struct Ownership {
    private let buildings: [VertexID: BuildingOwner]
    private let roads: [EdgeID: PlayerID]

    init(players: [Player]) {
        var buildings: [VertexID: BuildingOwner] = [:]
        var roads: [EdgeID: PlayerID] = [:]
        for player in players {
            for vertex in player.settlements {
                buildings[vertex] = BuildingOwner(player: player.id, isCity: false)
            }
            for vertex in player.cities {
                buildings[vertex] = BuildingOwner(player: player.id, isCity: true)
            }
            for edge in player.roads {
                roads[edge] = player.id
            }
        }
        self.buildings = buildings
        self.roads = roads
    }

    func owner(ofSettlementOrCity vertex: VertexID) -> BuildingOwner? {
        buildings[vertex]
    }

    func owner(ofRoad edge: EdgeID) -> PlayerID? {
        roads[edge]
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
