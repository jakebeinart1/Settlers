/// A board corner (settlement/city spot), canonicalized by the set of tile
/// coordinates that meet at that corner. Two corners are the same vertex iff
/// they are touched by the same set of tiles, so this doubles as a stable,
/// hashable, order-independent identifier for the corner.
public struct VertexID: Hashable, Codable, Sendable, Comparable {
    /// The 1-3 tile coordinates that meet at this corner, always stored sorted.
    public let touchingTiles: [HexCoordinate]

    public init(touchingTiles: Set<HexCoordinate>) {
        self.touchingTiles = touchingTiles.sorted()
    }

    public static func < (lhs: VertexID, rhs: VertexID) -> Bool {
        lhs.touchingTiles.lexicographicallyPrecedes(rhs.touchingTiles) { a, b in a < b }
    }
}
