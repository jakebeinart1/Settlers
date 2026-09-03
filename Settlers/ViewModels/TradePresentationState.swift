import Foundation
import CatanEngine

/// The bots' answers to the most recent player-proposed trade.
public struct TradeOutcomeState: Equatable {
    public let decisions: [(bot: PlayerID, accepted: Bool, message: String)]
    public let acceptedBy: PlayerID?

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.acceptedBy == rhs.acceptedBy
            && lhs.decisions.map(\.bot) == rhs.decisions.map(\.bot)
            && lhs.decisions.map(\.accepted) == rhs.decisions.map(\.accepted)
            && lhs.decisions.map(\.message) == rhs.decisions.map(\.message)
    }
}

/// A bot acceptance held until the player confirms which partner to use.
public struct PendingTradeConfirmationState {
    public let offerID: UUID
    public let selectedBot: PlayerID
    public let decisions: [(bot: PlayerID, accepted: Bool, message: String)]
}

/// One user-visible engine operation, sequenced so identical events still notify SwiftUI.
public struct GameEventBatch: Equatable {
    public let sequence: Int
    public let events: [GameEvent]
}
