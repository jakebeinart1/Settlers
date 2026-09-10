public enum TileKind: Codable, Sendable, Hashable {
    case resource(Resource)
    case desert
}

public struct Tile: Codable, Sendable, Equatable {
    public let coordinate: HexCoordinate
    public let kind: TileKind
    /// The number token (2-12, no 7) that produces resources on this tile.
    /// `nil` for the desert, which produces nothing.
    public let numberToken: Int?

    public init(coordinate: HexCoordinate, kind: TileKind, numberToken: Int?) {
        self.coordinate = coordinate
        self.kind = kind
        self.numberToken = numberToken
    }
}
