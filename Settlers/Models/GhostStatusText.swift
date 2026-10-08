import CatanAI

/// The one line that says what a player's ghost is doing (Jake, 2026-10-08:
/// "clear that the ghost is being trained, when it is done (games remaining)").
enum GhostStatusText {
    static func line(for ghost: GhostProfile, isTraining: Bool) -> String {
        if ghost.isTrainingPaused { return "Paused - your games are not being taught" }
        if isTraining { return "Training now..." }
        let remaining = GhostStore.minimumGamesToPlay - ghost.gamesLearned
        guard remaining > 0 else { return "Learning from every game" }
        return "Learning - \(remaining) more \(remaining == 1 ? "game" : "games") until others can play it"
    }
}
