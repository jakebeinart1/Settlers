import Foundation
import CatanEngine

/// A harvest is a quantity choice, including repeated resources. No selected
/// card belongs to the hand until the complete draft is durably confirmed.
nonisolated struct NavalHarvestDraft: Equatable {
    struct Context: Equatable {
        let matchID: UUID?
        let owner: PlayerID
        let moveCount: Int
        let remaining: Int
    }

    private(set) var context: Context?
    private(set) var counts: [Resource: Int] = [:]
    private(set) var errorMessage: String?

    var selectedCount: Int { Resource.allCases.reduce(0) { $0 + counts[$1, default: 0] } }
    var resources: [Resource] {
        Resource.allCases.flatMap { Array(repeating: $0, count: counts[$0, default: 0]) }
    }

    func canAdd(_ resource: Resource, bank: [Resource: Int], required: Int) -> Bool {
        selectedCount < required && counts[resource, default: 0] < bank[resource, default: 0]
    }

    mutating func add(_ resource: Resource, bank: [Resource: Int], required: Int) {
        guard canAdd(resource, bank: bank, required: required) else { return }
        counts[resource, default: 0] += 1
        errorMessage = nil
    }

    mutating func remove(_ resource: Resource) {
        guard let count = counts[resource], count > 0 else { return }
        counts[resource] = count == 1 ? nil : count - 1
        errorMessage = nil
    }

    /// Only the exact unresolved production keeps an in-process draft. Time
    /// accounting writes do not clear it; a different actor or committed move
    /// does. A cold launch starts empty because drafts are never serialized.
    mutating func reconcile(context: Context, bank: [Resource: Int], required: Int) {
        if self.context != context { self = NavalHarvestDraft(context: context) }
        var room = required
        for resource in Resource.allCases {
            let retained = min(counts[resource, default: 0], bank[resource, default: 0], room)
            counts[resource] = retained == 0 ? nil : retained
            room -= retained
        }
    }

    mutating func fail(_ error: Error) { errorMessage = error.localizedDescription }
    mutating func reset() { self = NavalHarvestDraft() }
}
