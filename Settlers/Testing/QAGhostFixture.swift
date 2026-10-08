import CatanAI
import Foundation

#if DEBUG
/// `-qaSeedGhosts`: the player's own ghost three games short of playable, one
/// Old Ghost, and another player's ghost - every section of Manage Ghosts,
/// with no rated games played. Runs after the UI-test reset, like the history
/// fixture, so the reset cannot wipe it.
enum QAGhostFixture {
    static func seedIfRequested(store: GhostStore = .shared, me: String = PlayerDirectory.shared.me) {
        guard QALaunchFlag.seedGhosts.isSet else { return }
        do {
            let person = PersonModel.anchored(at: .forMode(.classic))
            try store.save(GhostProfile(id: me, name: "UI Tester's Ghost", person: person, lambda: 0.01, gamesLearned: 14))
            try store.reset(me, keepingOld: true)
            try store.save(GhostProfile(id: me, name: "UI Tester's Ghost", person: person, lambda: 0.01,
                                        gamesLearned: 7, revision: 30))
            try store.save(GhostProfile(id: "qa-rival", name: "Alex's Ghost", person: person, lambda: 0.01, gamesLearned: 12))
        } catch {
            preconditionFailure("Could not seed the QA ghosts: \(error)")
        }
    }
}
#endif
