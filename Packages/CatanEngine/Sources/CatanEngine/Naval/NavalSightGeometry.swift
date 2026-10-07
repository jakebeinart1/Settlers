import Foundation

extension Naval {
    private static let cornerCoordinateScale = 3

    /// Whether a hex center is within two hex spacings of the actual settlement/city corner.
    ///
    /// A canonical corner is the centroid of its three mutually adjacent hex centers, including
    /// sea and off-envelope coordinates. Scaling axial coordinates by three represents this
    /// centroid exactly; the cube norm then gives a symmetric range without rounding. At range
    /// two its 12-hex footprint also matches a physical circle of two center-to-center spacings.
    /// Filtering to land or on-board centers would move the origin away from the rendered corner
    /// and reveal farther terrain on some coastlines. This is the version 2 building predicate;
    /// ships retain their hex-centered range, and legacy saves retain their version 1 behavior.
    public static func isWithinViewingRange(_ coordinate: HexCoordinate, of vertex: VertexID) -> Bool {
        precondition(vertex.touchingTiles.count == cornerCoordinateScale, "vision requires a canonical three-hex corner")
        let cornerQ = vertex.touchingTiles.map(\.q).reduce(0, +)
        let cornerR = vertex.touchingTiles.map(\.r).reduce(0, +)
        let deltaQ = coordinate.q * cornerCoordinateScale - cornerQ
        let deltaR = coordinate.r * cornerCoordinateScale - cornerR
        let distance = max(abs(deltaQ), abs(deltaR), abs(deltaQ + deltaR))
        return distance <= viewingRange * cornerCoordinateScale
    }
}
