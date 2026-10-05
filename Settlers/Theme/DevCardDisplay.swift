import CatanEngine

/// Copy for owned stacks, separate from engine timing. `ready` in the inventory
/// is an age count; only the engine's typed status permits advertising play.
enum DevCardDisplay {
    static func inventoryBadge(_ item: DevCardInventoryItem) -> String {
        if item.status == .passiveVictoryPoint { return "PASSIVE" }
        let older = item.status.isPlayable ? "READY" : "HELD"
        if item.ready > 0, item.boughtThisTurn > 0 {
            return "\(item.ready) \(older) · \(item.boughtThisTurn) NEW"
        }
        if item.ready > 0 { return "\(item.ready) \(older)" }
        return "\(item.boughtThisTurn) NEW"
    }

    static func accessibilityValue(_ item: DevCardInventoryItem) -> String {
        let status = DevCardStyle.statusTitle(for: item.status)
        if item.status == .passiveVictoryPoint { return status }
        let older = item.status.isPlayable ? "ready" : "held"
        return "\(item.ready) \(older), \(item.boughtThisTurn) new. \(status)"
    }

    static func summary(_ type: DevCardType) -> String {
        switch type {
        case .knight: "Move & steal"
        case .roadBuilding: "Two free roads"
        case .yearOfPlenty: "Two bank cards"
        case .monopoly: "Collect one resource"
        case .victoryPoint: "+1 hidden point"
        }
    }

    static func compactStatus(_ status: DevCardPlayStatus) -> String {
        switch status {
        case .playable: "READY"
        case .passiveVictoryPoint: "VP"
        case .boughtThisTurn: "NEW"
        case .waitingForYourTurn: "WAIT"
        case .alreadyPlayedThisTurn: "USED"
        case .resolveRequiredAction: "WAIT"
        case .noLegalChoices: "HELD"
        case .notOwned: "NONE"
        case .gameOver: "ENDED"
        }
    }

    /// Both age counts fit the unchanged HUD footprint without shrinking
    /// READY/NEW into unreadable type. Full words are in its spoken value.
    static func handBadgeStatus(_ item: DevCardInventoryItem) -> String {
        guard item.ready > 0, item.boughtThisTurn > 0, item.status != .passiveVictoryPoint else {
            return compactStatus(item.status)
        }
        let older = item.status.isPlayable ? "R" : "H"
        return "\(item.ready)\(older) · \(item.boughtThisTurn)N"
    }
}
