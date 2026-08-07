/// Axial coordinate for a hex tile. `q` is the column, `r` is the row in axial
/// hex-grid space. See https://www.redblobgames.com/grids/hexagons/ for background.
public struct HexCoordinate: Hashable, Codable, Sendable, Comparable {
    public let q: Int
    public let r: Int

    public init(q: Int, r: Int) { self.q = q; self.r = r }

    public static func < (lhs: HexCoordinate, rhs: HexCoordinate) -> Bool {
        (lhs.q, lhs.r) < (rhs.q, rhs.r)
    }

    /// The six axial neighbor offsets, in consistent rotational (60°) order.
    public static let neighborDirections: [(Int, Int)] =
        [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]

    public func neighbor(_ direction: Int) -> HexCoordinate {
        let d = HexCoordinate.neighborDirections[((direction % 6) + 6) % 6]
        return HexCoordinate(q: q + d.0, r: r + d.1)
    }
}
