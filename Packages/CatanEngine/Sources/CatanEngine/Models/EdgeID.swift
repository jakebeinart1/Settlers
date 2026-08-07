/// A board edge (road spot), canonicalized as a sorted pair of its two
/// endpoint vertices so the same edge always compares/hashes equal
/// regardless of which endpoint order it was constructed from.
public struct EdgeID: Hashable, Codable, Sendable {
    public let a: VertexID
    public let b: VertexID

    public init(_ v1: VertexID, _ v2: VertexID) {
        if v1 < v2 { a = v1; b = v2 } else { a = v2; b = v1 }
    }
}
