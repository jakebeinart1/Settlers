import Foundation
import CatanEngine

/// Presentation only: waiting can be skipped, decision computation cannot.
/// No timer, retry or view owns canonical game state or advances policy RNG.
enum BotTurnProgress: Equatable {
    case waiting(seat: PlayerID, until: Date)
    case thinking(seat: PlayerID)
    case failed(seat: PlayerID, message: String)
}

/// A private candidate carries both policy bookkeeping and the complete step.
/// The main actor publishes it only if its checkpoint revision is still current.
struct PreparedBotStep: Sendable {
    let session: GameSession
    let step: GameSession.Step
}
