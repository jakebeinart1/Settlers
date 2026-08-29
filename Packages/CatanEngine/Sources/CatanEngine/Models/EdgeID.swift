/// A board edge (road spot), canonicalized as a sorted pair of its two
/// endpoint vertices so the same edge always compares/hashes equal
/// regardless of which endpoint order it was constructed from.
public struct EdgeID: Hashable, Codable, Sendable, Comparable {
    public let a: VertexID
    public let b: VertexID

    public init(_ v1: VertexID, _ v2: VertexID) {
        if v1 < v2 { a = v1; b = v2 } else { a = v2; b = v1 }
    }

    /// Ordered by endpoint, low end first. Exists so `RulesEngine.legalMoves`
    /// can enumerate edges in a stable order: the board stores them in a
    /// `Set`, whose iteration order Swift seeds per process, and an unstable
    /// move order makes a bot's tie-breaks differ between runs of the same
    /// seed.
    public static func < (lhs: EdgeID, rhs: EdgeID) -> Bool {
        lhs.a == rhs.a ? lhs.b < rhs.b : lhs.a < rhs.a
    }
}
