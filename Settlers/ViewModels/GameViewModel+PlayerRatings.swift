import Foundation

extension GameViewModel {
    /// Read the saved match contract, never the next game's preferences.
    /// The confirmation must describe the game about to be replaced.
    var activeAIRatingPool: RatingPool? {
        guard let setup = checkpointDocument?.activeMatch?.setup else { return nil }
        return RatingPool.eligible(for: setup)
    }

    var abandoningChangesRating: Bool {
        guard let match = checkpointDocument?.activeMatch else { return false }
        if case .gameOver = match.state.phase { return false }
        if activeAIRatingPool != nil { return true }
        // Ghosts retain their original Classic ladder and restart policy.
        return match.setup.mode == .classic && match.setup.variant == .standard
            && match.setup.humanSeats.count == 1
    }

    var unratedMatchExplanation: String? {
        guard let setup = checkpointDocument?.activeMatch?.setup else {
            return "This game has no recorded AI rating."
        }
        if setup.humanSeats.count != 1 { return "Pass & Play doesn’t change your AI rating." }
        if activeAIRatingPool == nil { return "Ghost games use the ghost ladder, separate from your AI record." }
        return nil
    }
}
