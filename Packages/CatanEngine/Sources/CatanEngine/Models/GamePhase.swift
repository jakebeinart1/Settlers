public enum GamePhase: Codable, Sendable, Equatable {
    case setupForward(playerIndex: Int)
    case setupBackward(playerIndex: Int)
    case rollDice(playerIndex: Int)
    case mainTurn(playerIndex: Int)
    case discarding(pending: Set<PlayerID>)
    case movingRobber(playerIndex: Int)
    case gameOver(winner: PlayerID)

    /// The seat this phase is waiting on, or `nil` when no single seat owns it.
    ///
    /// ## Why this exists
    /// Five of the seven cases carry a `playerIndex` that means the same thing,
    /// and every caller that wanted it had to unpack the associated value by
    /// hand. `GameView` alone had six copies of the same `if case`, and the
    /// answers drifted: the Build button simply never got one (it was hardcoded
    /// `isEnabled: true`, so it stayed lit through the setup phase, where the
    /// only legal moves are placing a settlement and a road), and the board's
    /// `.mainTurn` highlight arms omitted the seat check that the setup arms
    /// have, so an armed placement mode highlighted a *bot's* legal spots.
    ///
    /// A question asked six ways gets six answers. Asking it once fixes both.
    ///
    /// ## This does not teach the engine about humans
    /// It returns a seat index, not "the human". Which seat a person is sitting
    /// in remains entirely the UI's business - the engine has no way to know
    /// and must not acquire one, which is the mistake that had
    /// `RulesEngine.playerLabel` calling a bot "You" in three games out of four.
    /// The caller compares this against its own notion of the human seat.
    ///
    /// `nil` for `.discarding`, which is genuinely multi-seat (everyone over
    /// seven cards discards, and `GameSession` picks among them), and for
    /// `.gameOver`, which waits on nobody.
    public var awaitingSeatIndex: Int? {
        switch self {
        case .setupForward(let index), .setupBackward(let index),
             .rollDice(let index), .mainTurn(let index), .movingRobber(let index):
            return index
        case .discarding, .gameOver:
            return nil
        }
    }

    /// True when this phase is `.mainTurn` waiting on `seatIndex` - the one
    /// phase in which a player may build, trade or buy a development card.
    ///
    /// Separate from `awaitingSeatIndex` because "is it this seat's turn at
    /// all" and "may this seat act on the board right now" are different
    /// questions, and conflating them is what put the Build button and the
    /// Trade button on different answers.
    public func isMainTurn(of seatIndex: Int) -> Bool {
        if case .mainTurn(let index) = self { return index == seatIndex }
        return false
    }
}
