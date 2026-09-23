/// Which rule layer a game is played under, on top of its board (`GameMode`).
///
/// Separate from `GameMode` because Conquest crosses every board: folding it in
/// would need a `classicConquest` and a `vastConquest`, doubling the modes for
/// every future layer. `String`-raw for the same save-stability reason as
/// `GameMode`.
public enum GameVariant: String, Codable, CaseIterable, Sendable {
    case standard
    /// Hexes are held by tribes and taken with army cards; an occupied hex pays
    /// only its occupier, plus one. See `Conquest`.
    case conquest

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .conquest: return "Conquest"
        }
    }
}
