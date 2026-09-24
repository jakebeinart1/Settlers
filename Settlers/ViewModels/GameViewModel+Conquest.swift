import CatanEngine

/// The dock's one line about what the chosen cards will do, from the engine's rule.
enum ArmyPreview {
    static func sentence(total: Int, against current: Garrison?, me: PlayerID, name: (PlayerID) -> String) -> String {
        if let current, current.owner == me { return "Reinforces to \(current.strength + total)" }
        guard let after = Conquest.outcome(of: total, against: current, by: me) else { return "Leaves it empty" }
        if after.owner == me { return "Takes it, holding at \(after.strength)" }
        return after.owner.map { "Leaves \(name($0)) at \(after.strength)" } ?? "Leaves the tribe at \(after.strength)"
    }
}

/// Chip toggling for a hand that may hold the same strength twice: chip `index`
/// is "on" while fewer copies of its strength sit before it than are selected.
enum ArmyChips {
    static func isOn(_ index: Int, hand: [Int], selected: [Int]) -> Bool {
        let value = hand[index]
        return hand[..<index].filter { $0 == value }.count < selected.filter { $0 == value }.count
    }

    static func toggle(_ index: Int, hand: [Int], selected: [Int]) -> [Int] {
        var next = selected
        if isOn(index, hand: hand, selected: selected), let existing = next.firstIndex(of: hand[index]) {
            next.remove(at: existing)
        } else {
            next.append(hand[index])
        }
        return next.sorted()
    }
}

@MainActor
extension GameViewModel {
    /// The dock's title while choosing army cards, or nil outside a deploy.
    public var armyDeploymentPreview: String? {
        guard let decision = boardDecisionPresentation, decision.intent == .deployArmy,
              let hex = decision.selectedTile else { return nil }
        let total = decision.selectedArmyCards.reduce(0, +)
        guard total > 0 else { return "Choose army cards" }
        return ArmyPreview.sentence(total: total, against: state.garrisons[hex], me: humanPlayer,
                                    name: { self.playerIdentity(for: $0).displayName })
    }
}
