public enum GamePhase: Codable, Sendable, Equatable {
    case setupForward(playerIndex: Int)
    case setupBackward(playerIndex: Int)
    case rollDice(playerIndex: Int)
    case mainTurn(playerIndex: Int)
    case discarding(pending: Set<PlayerID>)
    case movingRobber(playerIndex: Int)
    case gameOver(winner: PlayerID)
}
