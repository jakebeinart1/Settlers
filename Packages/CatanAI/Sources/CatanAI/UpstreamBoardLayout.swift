import CatanEngine

/// The pinned Eli6th v1 board order, independent of Empires' sorted encoders.
/// Integer pointy-hex geometry proves which coordinate each neural slot names;
/// matching only the 19/54/72 counts would silently put logits on wrong places.
public struct UpstreamBoardLayout: Sendable {
    public let tiles: [HexCoordinate]
    public let vertices: [VertexID]
    public let edges: [EdgeID]

    public enum LayoutError: Error { case unsupportedBoard }

    public init(board: Board) throws {
        let tiles = board.tiles.map(\.coordinate).sorted { ($0.r, $0.q) < ($1.r, $1.q) }
        guard tiles.count == 19, Set(tiles) == Self.tileCoordinates,
              board.onBoardVertices == Self.canonical.onBoardVertices,
              board.onBoardEdges == Self.canonical.onBoardEdges else {
            throw LayoutError.unsupportedBoard
        }
        let byPoint = Dictionary(uniqueKeysWithValues: board.onBoardVertices.map { (Point(vertex: $0), $0) })
        var ordered: [VertexID] = []
        for tile in tiles {
            for (dx, dy) in Self.corners {
                guard let vertex = byPoint[Point(x: 2 * tile.q + tile.r + dx, y: 3 * tile.r + dy)] else {
                    throw LayoutError.unsupportedBoard
                }
                if !ordered.contains(vertex) { ordered.append(vertex) }
            }
        }
        guard ordered.count == 54 else { throw LayoutError.unsupportedBoard }
        let indices = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1, $0) })
        self.tiles = tiles
        self.vertices = ordered
        self.edges = board.onBoardEdges.sorted {
            Self.endpoints($0, indices: indices) < Self.endpoints($1, indices: indices)
        }
    }

    // Only topology is fixed. Resource placement, number tokens and ports stay
    // native to this match and are encoded from the actual board, not this one.
    private static let canonical = BoardGenerator.standard()
    private static let tileCoordinates = Set(canonical.tiles.map(\.coordinate))
    private static let corners = [(0, -2), (1, -1), (1, 1), (0, 2), (-1, 1), (-1, -1)]

    private static func endpoints(_ edge: EdgeID, indices: [VertexID: Int]) -> (Int, Int) {
        // The board's edge set must reference the same 54 vertices.
        guard let a = indices[edge.a], let b = indices[edge.b] else {
            preconditionFailure("board edge references an absent vertex")
        }
        return (min(a, b), max(a, b))
    }

    private struct Point: Hashable {
        let x: Int
        let y: Int
        init(x: Int, y: Int) { self.x = x; self.y = y }
        init(vertex: VertexID) {
            let q = vertex.touchingTiles.reduce(0) { $0 + $1.q }
            let r = vertex.touchingTiles.reduce(0) { $0 + $1.r }
            self.init(x: (2 * q + r) / 3, y: r)
        }
    }
}
