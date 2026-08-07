public struct Board: Codable, Sendable {
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
    public func neighborTiles(of vertex: VertexID) -> [HexCoordinate] {
        vertex.touchingTiles
    }

    /// The vertices directly connected to `vertex` by an on-board edge.
    public func adjacentVertices(of vertex: VertexID) -> [VertexID] {
        var result: [VertexID] = []
        for edge in onBoardEdges {
            if edge.a == vertex {
                result.append(edge.b)
            } else if edge.b == vertex {
                result.append(edge.a)
            }
        }
        return result
    }

    /// The on-board edges incident to `vertex`.
    public func edgesTouching(_ vertex: VertexID) -> [EdgeID] {
        onBoardEdges.filter { $0.a == vertex || $0.b == vertex }
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
