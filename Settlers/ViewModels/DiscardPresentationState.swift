import Foundation
import CatanEngine

/// Ephemeral cards selected for a mandatory discard.
///
/// This deliberately does not live in `GameState`: no card has left the hand
/// until the player presses the explicit commit button. The view model owns
/// the draft so opening Settings or rebuilding `GameView` after a recoverable
/// save error cannot erase a choice the player was still considering.
struct DiscardDraft: Equatable {
    private(set) var owner: PlayerID?
    private(set) var counts: [Resource: Int] = [:]
    private(set) var errorMessage: String?

    var selectedCount: Int { counts.values.reduce(0, +) }

    func isComplete(requiredCount: Int) -> Bool {
        selectedCount == requiredCount
    }

    mutating func select(_ resource: Resource, owned: Int, required: Int) {
        guard selectedCount < required, (counts[resource] ?? 0) < owned else { return }
        counts[resource] = (counts[resource] ?? 0) + 1
        errorMessage = nil
    }

    mutating func deselect(_ resource: Resource) {
        guard let selected = counts[resource], selected > 0 else { return }
        if selected == 1 {
            counts[resource] = nil
        } else {
            counts[resource] = selected - 1
        }
        errorMessage = nil
    }

    /// Keeps a recoverable draft only while it still belongs to this exact
    /// player and remains legal against the checkpoint that was reloaded.
    mutating func reconcile(owner: PlayerID, holding: [Resource: Int], requiredCount: Int) {
        guard self.owner == nil || self.owner == owner else {
            self = DiscardDraft(owner: owner)
            return
        }
        self.owner = owner
        var room = requiredCount
        var valid: [Resource: Int] = [:]
        for resource in Resource.allCases {
            let retained = min(max(counts[resource] ?? 0, 0), holding[resource] ?? 0, room)
            if retained > 0 { valid[resource] = retained }
            room -= retained
        }
        if valid != counts { errorMessage = nil }
        counts = valid
    }

    /// Runs only from an explicit submit action. The local-copy pattern used
    /// by `GameViewModel` avoids overlapping mutation while the closure
    /// commits through that same model.
    mutating func submit(
        requiredCount: Int,
        perform: ([Resource: Int]) throws -> Void
    ) -> Bool {
        guard isComplete(requiredCount: requiredCount) else { return false }
        do {
            try perform(counts)
            self = DiscardDraft()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    mutating func reset() {
        self = DiscardDraft()
    }
}

extension GameViewModel {
    struct DiscardObligation {
        let owner: PlayerID
        let holding: [Resource: Int]
        let requiredCount: Int
    }

    var currentDiscardObligation: DiscardObligation? {
        let owner = humanPlayer
        guard case .discarding(let pending) = state.phase, pending.contains(owner),
              let player = state.players.first(where: { $0.id == owner }) else { return nil }
        return DiscardObligation(
            owner: owner,
            holding: player.resources,
            requiredCount: Robber.discardCount(for: player)
        )
    }

    func prepareDiscardPresentation() {
        guard let obligation = currentDiscardObligation else {
            resetDiscardPresentation()
            return
        }
        let previousOwner = discardDraft.owner
        discardDraft.reconcile(
            owner: obligation.owner,
            holding: obligation.holding,
            requiredCount: obligation.requiredCount
        )
        if let previousOwner, previousOwner != obligation.owner {
            isDiscardEditorMinimized = false
        }
    }

    func selectForDiscard(_ resource: Resource) {
        guard let obligation = currentDiscardObligation else { return }
        discardDraft.reconcile(
            owner: obligation.owner,
            holding: obligation.holding,
            requiredCount: obligation.requiredCount
        )
        discardDraft.select(
            resource,
            owned: obligation.holding[resource] ?? 0,
            required: obligation.requiredCount
        )
    }

    func deselectFromDiscard(_ resource: Resource) {
        prepareDiscardPresentation()
        discardDraft.deselect(resource)
    }

    func setDiscardEditorMinimized(_ minimized: Bool) {
        prepareDiscardPresentation()
        guard currentDiscardObligation != nil else { return }
        isDiscardEditorMinimized = minimized
    }

    @discardableResult
    func submitDiscard() -> Bool {
        prepareDiscardPresentation()
        guard let obligation = currentDiscardObligation else { return false }
        var candidate = discardDraft
        let succeeded = candidate.submit(requiredCount: obligation.requiredCount) { counts in
            try apply(.discard(counts))
        }
        discardDraft = candidate
        if succeeded { isDiscardEditorMinimized = false }
        return succeeded
    }

    func resetDiscardPresentation() {
        discardDraft.reset()
        isDiscardEditorMinimized = false
    }
}
