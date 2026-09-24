public struct Board: Codable, Sendable, Equatable {
    public let tiles: [Tile]
    public let ports: [Port]
    public let onBoardVertices: Set<VertexID>
    public let onBoardEdges: Set<EdgeID>
    public var robberTile: HexCoordinate

    public init(
        tiles: [Tile],
        ports: [Port],
        onBoardVertices: Set<VertexID>,
        onBoardEdges: Set<EdgeID>,
        robberTile: HexCoordinate
    ) {
        self.tiles = tiles
        self.ports = ports
        self.onBoardVertices = onBoardVertices
        self.onBoardEdges = onBoardEdges
        self.robberTile = robberTile
    }

    /// The tile coordinates that meet at `vertex` (1-3 of them).
    /// The six corners of `hex`. Public on `Board` rather than by exposing
    /// `HexGeometry`, whose name the app target already uses for its own
    /// drawing geometry - both public, every file importing the two modules
    /// failed with "'HexGeometry' is ambiguous".
    public func corners(of hex: HexCoordinate) -> [VertexID] {
        HexGeometry.corners(of: hex)
    }

    public func neighborTiles(of vertex: VertexID) -> [HexCoordinate] {
        vertex.touchingTiles
    }

    // Both accessors below derive from `onBoardEdges`, which is a `Set` -
    // and Swift seeds set iteration order per process, so an unsorted result
    // here would come back in a different order on every launch. That order
    // reaches move enumeration (`SetupPhase.legalMoves` maps straight over
    // `edgesTouching`), so leaving it unsorted makes a bot's tie-breaks - and
    // therefore the whole game - differ between runs of the same seed. Both
    // return at most 3 elements, so the sort is not a meaningful cost.

    /// The vertices directly connected to `vertex` by an on-board edge, in a
    /// stable order.
    public func adjacentVertices(of vertex: VertexID) -> [VertexID] {
        var result: [VertexID] = []
        for edge in onBoardEdges {
            if edge.a == vertex {
                result.append(edge.b)
            } else if edge.b == vertex {
                result.append(edge.a)
            }
        }
        return result.sorted()
    }

    /// The on-board edges incident to `vertex`, in a stable order.
    public func edgesTouching(_ vertex: VertexID) -> [EdgeID] {
        onBoardEdges.filter { $0.a == vertex || $0.b == vertex }.sorted()
    }

    public func vertices(of edge: EdgeID) -> (VertexID, VertexID) {
        (edge.a, edge.b)
    }
}

// MARK: - Corner/edge canonicalization

/// Derives a tile's corners and edges from its `HexCoordinate` alone, using
/// `VertexID`/`EdgeID`'s canonical (set-of-tiles) representation. This is the
/// single source of truth for hex-grid geometry: every other piece of code
/// (board generation, adjacency queries) builds on these two functions rather
/// than re-deriving corner/edge positions.
enum HexGeometry {
    /// The corner shared by `coordinate` and its neighbors in directions `i`
    /// and `i+1`. `HexCoordinate.neighborDirections` is listed in consistent
    /// rotational (60°) order, so any two directions that are adjacent in
    /// that list are themselves mutually-adjacent tiles - meaning this triple
    /// always describes a real corner, even when 1-2 of the three tiles are
    /// off the physical board (in which case the corner is off-board too).
    static func corner(of coordinate: HexCoordinate, between i: Int) -> VertexID {
        VertexID(touchingTiles: Set([
            coordinate,
            coordinate.neighbor(i),
            coordinate.neighbor(i + 1),
        ]))
    }

    /// All 6 corners of a tile, indexed 0...5, where corner `i` sits between
    /// neighbor directions `i` and `i + 1`.
    static func corners(of coordinate: HexCoordinate) -> [VertexID] {
        (0..<6).map { corner(of: coordinate, between: $0) }
    }

    /// All 6 edges of a tile, indexed 0...5, where edge `i` is the edge
    /// shared with the neighbor in direction `i` (running between corner
    /// `i - 1` and corner `i`).
    static func edges(of coordinate: HexCoordinate) -> [EdgeID] {
        let c = corners(of: coordinate)
        return (0..<6).map { i in EdgeID(c[(i + 5) % 6], c[i]) }
    }
}
