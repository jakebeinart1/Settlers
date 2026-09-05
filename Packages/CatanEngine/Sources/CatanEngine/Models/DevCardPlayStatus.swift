/// The canonical answer to whether a development card can be played now.
///
/// Presentation maps these typed reasons to copy, but it never reconstructs
/// turn timing, the one-card-per-turn rule, or target availability itself. That
/// keeps a disabled button and `RulesEngine.legalMoves` on the same rules.
public enum DevCardPlayStatus: Sendable, Equatable {
    case playable
    case passiveVictoryPoint
    case notOwned
    case boughtThisTurn
    case alreadyPlayedThisTurn
    case waitingForYourTurn
    case resolveRequiredAction
    case noLegalChoices
    case gameOver

    public var isPlayable: Bool { self == .playable }
}
