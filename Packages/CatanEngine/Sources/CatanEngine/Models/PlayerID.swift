/// Identifies a seat at the table, 0 through 3.
///
/// Deliberately says nothing about who occupies a seat. This doc used to claim
/// "index 0 is always the human player", which stopped being true the moment
/// "Randomize Seat" shipped - it is on by default and picks any of the four.
/// That was the fifth copy of the same belief found in this codebase; the
/// others produced a log that called a bot "You" and two seat-index bugs in
/// trade resolution. The engine has no notion of a human seat and should not
/// acquire one.
public struct PlayerID: Hashable, Codable, Sendable, Comparable {
    public let index: Int

    public init(index: Int) {
        self.index = index
    }

    public static func < (lhs: PlayerID, rhs: PlayerID) -> Bool {
        lhs.index < rhs.index
    }
}
