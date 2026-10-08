import Observation

/// Which ghosts are mid-training right now, for Manage Ghosts' "Training
/// now..." line. Training runs in the background for about a minute after a
/// game (`GhostTrainingQueue`), which is exactly when a player opens the screen.
@MainActor @Observable
final class GhostTrainingStatus {
    static let shared = GhostTrainingStatus()
    private(set) var trainingIDs: Set<String> = []

    func begin(_ id: String) { trainingIDs.insert(id) }
    func end(_ id: String) { trainingIDs.remove(id) }
}
