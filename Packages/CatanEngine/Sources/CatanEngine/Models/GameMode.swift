/// Which rule set a game is played under.
///
/// A tag, not a bag of values: the quantities live in `Ruleset`, keyed by this.
/// Storing the tag rather than the numbers means a save cannot carry an
/// incoherent combination — a 25-point target beside classic's five-settlement
/// limit — and adding a mode needs one decode default rather than one per
/// quantity.
///
/// `String`-raw on purpose: saves store this, and a `String` survives
/// reordering the cases where an `Int` would not.
public enum GameMode: String, Codable, CaseIterable, Sendable {
    /// The 19-tile board played to 8, 10 or 12 points. Every save written
    /// before modes existed is this one.
    case classic
    /// The 37-tile board played to 25, with doubled pieces, bank and deck, and
    /// 4-point bonuses.
    case expanded

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .expanded: return "Expanded"
        }
    }

    /// One line, shown under the name in the mode picker.
    public var summary: String {
        switch self {
        case .classic: return "The standard 19-tile board, played to 8, 10 or 12 points."
        case .expanded: return "A 37-tile map played to 25 points, with twice the pieces and 4-point bonuses."
        }
    }
}
