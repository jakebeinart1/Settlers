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
    ///
    /// **Retired from the New Game screen, and deliberately not deleted.** Its
    /// 25-point target was unreachable on a 37-tile board for most of the
    /// table - four players claim only eight or nine vertices each, capping a
    /// player near 17 points of buildings, so the rest had to come from a deck
    /// the same four players were emptying. Measured over 40 seeded games, 19
    /// emptied the deck and one reached the move cap at 21/19/24/22 with no way
    /// for anyone to score again. `vast` replaces it.
    ///
    /// The case survives because saves store this raw value: deleting it makes
    /// `GameState.init(from:)` throw on an in-progress Expanded game, and
    /// `GameStore.load()` swallows that with `try?` and silently starts a new
    /// game. A player mid-match would simply lose it. It therefore stays
    /// decodable and playable, and only leaves `newGameChoices`.
    case expanded
    /// The 61-tile board played to 26, sized so that the target is reachable by
    /// building rather than only by emptying the development deck.
    case vast

    /// The modes a new game may be started in, in the order they are offered.
    ///
    /// Not `allCases`: `expanded` is still decodable so existing saves resume,
    /// but must not be startable again. Anything driving a mode picker reads
    /// this, so retiring a mode is one edit here rather than a filter repeated
    /// at every call site - the copy-the-decision pattern that has already cost
    /// this repository a seat-numbering bug in four places.
    public static let newGameChoices: [GameMode] = [.classic, .vast]

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .expanded: return "Expanded"
        case .vast: return "Vast"
        }
    }

    /// One line, shown under the name in the mode picker.
    public var summary: String {
        switch self {
        case .classic: return "The standard 19-tile board, played to 8, 10 or 12 points."
        case .expanded: return "A 37-tile map played to 25 points, with twice the pieces and 4-point bonuses."
        case .vast: return "A 61-tile map played to 26 points, with room to build your way there."
        }
    }
}
