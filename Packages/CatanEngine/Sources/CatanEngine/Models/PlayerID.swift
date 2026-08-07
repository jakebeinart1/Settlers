/// Identifies a seat at the table. Index 0 is always the human player;
/// indices 1-3 are bots.
public struct PlayerID: Hashable, Codable, Sendable, Comparable {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public static func < (lhs: PlayerID, rhs: PlayerID) -> Bool {
        lhs.index < rhs.index
    }
}
