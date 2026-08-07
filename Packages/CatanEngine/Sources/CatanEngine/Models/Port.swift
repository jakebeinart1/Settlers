public enum PortKind: Codable, Sendable, Equatable {
    /// 3 of any single resource : 1
    case generic
    /// 2 of the given resource : 1
    case resource(Resource)
}

/// A trading port, anchored to the two adjacent shoreline vertices where a
/// settlement/city must sit to use it.
public struct Port: Codable, Sendable {
    public let vertexA: VertexID
    public let vertexB: VertexID
    public let kind: PortKind

    public init(vertexA: VertexID, vertexB: VertexID, kind: PortKind) {
        self.vertexA = vertexA
        self.vertexB = vertexB
        self.kind = kind
    }
}
