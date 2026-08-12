import CoreGraphics
import CatanEngine

/// Pure pixel-math for a pointy-top hex board: axial `HexCoordinate` <->
/// screen-space `CGPoint`. Unrelated to `CatanEngine`'s internal (non-public)
/// `HexGeometry` enum, which does corner/edge *canonicalization* (deriving
/// `VertexID`/`EdgeID` from axial coordinates) - this type only turns
/// coordinates that already exist into pixels for drawing.
public struct HexGeometry {
    /// Pixel origin (screen position of axial coordinate (0, 0)'s center).
    public let origin: CGPoint
    /// Distance from a tile's center to any of its 6 corners.
    public let size: CGFloat

    public init(origin: CGPoint, size: CGFloat) {
        self.origin = origin
        self.size = size
    }

    /// The pixel center of a hex tile, via the standard pointy-top axial
    /// formula: x = size * sqrt(3) * (q + r/2), y = size * 3/2 * r.
    public func center(of tile: HexCoordinate) -> CGPoint {
        let x = size * sqrt(3) * (CGFloat(tile.q) + CGFloat(tile.r) / 2)
        let y = size * 1.5 * CGFloat(tile.r)
        return CGPoint(x: origin.x + x, y: origin.y + y)
    }

    /// Corner `index` (0...5) of `tile`, at angle `60*index - 30` degrees
    /// from its center, at distance `size`.
    public func corner(of tile: HexCoordinate, index: Int) -> CGPoint {
        let center = center(of: tile)
        let angle = (Double(index) * 60 - 30) * .pi / 180
        return CGPoint(
            x: center.x + size * CGFloat(cos(angle)),
            y: center.y + size * CGFloat(sin(angle))
        )
    }

    /// The pixel position of a board corner (settlement/city spot).
    ///
    /// `VertexID.touchingTiles` is always exactly the 3 axial coordinates
    /// `{coordinate, coordinate.neighbor(i), coordinate.neighbor(i+1)}` that
    /// the engine used to canonicalize the corner (see `Board.swift`'s
    /// internal `HexGeometry.corner(of:between:)`) - even for a vertex on the
    /// edge of the physical board, where 1-2 of those 3 coordinates are
    /// off-board tiles that were never generated. In a regular hex grid,
    /// three mutually-adjacent tile centers always form an equilateral
    /// triangle whose centroid is exactly their shared corner (each center
    /// sits distance `size` from that corner, at 60 degrees apart), so
    /// averaging `center(of:)` over `touchingTiles` gives the exact pixel
    /// position with no need to reverse-engineer which of the 6 `corner(of:
    /// index:)` slots it corresponds to on any particular tile - robust even
    /// when some touching tiles are off-board, since `center(of:)` is pure
    /// axial math with no board-membership check.
    public func vertexPosition(_ vertex: VertexID, board: Board) -> CGPoint {
        let points = vertex.touchingTiles.map { center(of: $0) }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    /// The pixel midpoint of a board edge (road spot): the midpoint of its
    /// two endpoint vertices' positions.
    public func edgeMidpoint(_ edge: EdgeID, board: Board) -> CGPoint {
        let (a, b) = board.vertices(of: edge)
        let pa = vertexPosition(a, board: board)
        let pb = vertexPosition(b, board: board)
        return CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2)
    }
}
