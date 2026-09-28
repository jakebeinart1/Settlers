import CatanEngine

/// A bot does not end its turn holding more cards than a seven lets it keep
/// while it still has something to spend them on.
///
/// ## Why this is a rule and not a weight
/// Jake's ghost sat at 7 VP with 25-31 cards for eight straight turns, rolling
/// and ending (game `8B5DB719`, 2026-09-28), and the replay showed why. In
/// Classic Expert's weights a card past the threshold is worth
/// `handCardOverflow + discardExposure` = +0.0573 - 0.0524 = **+0.005**, so a
/// big hand prices as slightly *good*. The 3:1 ore trade toward a city scored
/// -0.0249 against ending the turn's -0.0389: a 0.014 margin that the ghost's
/// learned habits (-1.3 on bank trades, -0.7 on ending) flipped at lambda 0.01.
/// Expert survived on the same knife edge; four Expert seats ended 7.2% of
/// turns over seven cards.
///
/// Raising the penalty weight would move every Expert decision the sweep
/// validated, and a thinner margin would still be a margin a ghost's habits
/// can flip. Jake's own rule for the game is a floor, not a preference: "stay
/// under seven... if you have 10 to 15 you should play out of that... you are
/// literally wasting cards." So it is enforced where the turn ends.
///
/// Every spending move lowers the hand (a bank trade gives more than it gets,
/// a purchase pays), so a turn that spends down always terminates.
public enum HandDiscipline {

    /// Whether `seat` holds more than a seven lets it keep, in its own main turn.
    public static func mustSpend(_ seat: PlayerID, in state: GameState) -> Bool {
        guard case .mainTurn(let current) = state.phase, current == seat.index,
              let player = state.players.first(where: { $0.id == seat }) else { return false }
        return player.resources.values.reduce(0, +) > state.rules.discardThreshold
    }

    /// A move that turns cards in hand into something else.
    public static func spends(_ move: GameMove) -> Bool {
        switch move {
        case .buildRoad, .buildSettlement, .buildCity, .buyDevCard, .buyArmyCard, .bankTrade: return true
        default: return false
        }
    }
}
