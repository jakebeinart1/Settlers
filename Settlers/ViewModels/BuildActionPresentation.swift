import CatanEngine

/// Read-only construction feedback for the displayed seat. Legal moves remain
/// the sole authority for enabled actions; the remaining checks only explain
/// why an action is unavailable, without probing or revealing hidden terrain.
struct BuildActionPresentation: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case ship, road, settlement, city, devCard, armyCard, deployArmy

        var title: String {
            switch self {
            case .ship: return "Ship"
            case .road: return "Road"
            case .settlement: return "Settlement"
            case .city: return "City"
            case .devCard: return "Dev Card"
            case .armyCard: return "Army Card"
            case .deployArmy: return "Deploy Army"
            }
        }

        func matches(_ move: GameMove) -> Bool {
            switch (self, move) {
            case (.ship, .buildShip), (.road, .buildRoad), (.settlement, .buildSettlement),
                 (.city, .buildCity), (.devCard, .buyDevCard), (.armyCard, .buyArmyCard),
                 (.deployArmy, .deployArmy): return true
            default: return false
            }
        }
    }

    struct Cost: Identifiable, Equatable {
        let resource: Resource
        let held: Int
        let required: Int
        var id: Resource { resource }
        var missing: Int { max(0, required - held) }
    }

    let kind: Kind
    let isEnabled: Bool
    let detail: String
    let costs: [Cost]
    let flexibleCost: String?
    let inventoryDetail: String?
    var id: Kind { kind }
    var title: String { kind.title }
    var status: String { isEnabled ? "Ready" : "Unavailable" }
    var accessibilityValue: String {
        ([status, detail] + costs.map {
            "\($0.resource.rawValue.capitalized): have \($0.held), cost \($0.required), missing \($0.missing)"
        } + [flexibleCost, inventoryDetail].compactMap { $0 }).joined(separator: ". ")
    }

    /// One move enumeration serves the whole menu. The seat check is explicit:
    /// legalMoves(for:seat:) filters simultaneous discard only, and otherwise
    /// returns the current actor's moves even when a different seat is supplied.
    static func menu(in state: GameState, for actor: PlayerID) -> [Self] {
        let player = state.players.first { $0.id == actor }!
        let isMainTurn = state.phase == .mainTurn(playerIndex: actor.index)
        let legal = isMainTurn ? RulesEngine.legalMoves(for: state) : []
        return Kind.allCases.filter {
            if $0 == .ship { return state.mode == .naval }
            if $0 == .armyCard || $0 == .deployArmy { return state.variant == .conquest }
            return true
        }.map { kind in
            let cost = kind.fixedCost(in: state)
            let costs = Resource.allCases.compactMap { resource -> Cost? in
                guard let required = cost[resource], required > 0 else { return nil }
                return Cost(resource: resource, held: player.resources[resource, default: 0], required: required)
            }
            let enabled = legal.contains(where: kind.matches)
            let detail = enabled ? kind.readyDetail(for: player, in: state)
                : kind.unavailableDetail(for: player, in: state, costs: costs)
            return Self(kind: kind, isEnabled: enabled, detail: detail, costs: costs,
                        flexibleCost: kind.flexibleCost(for: player, in: state),
                        inventoryDetail: kind.inventoryDetail(for: player, in: state))
        }
    }
}

private extension BuildActionPresentation.Kind {
    func fixedCost(in state: GameState) -> [Resource: Int] {
        switch self {
        case .ship: return Naval.shipCost
        case .road: return Building.roadCost
        case .settlement: return Building.settlementCost
        case .city: return Building.cityCost
        case .devCard: return Building.devCardCost
        case .armyCard: return state.armyPrice == .oneOfEach ? Conquest.armyCardCost : [:]
        case .deployArmy: return [:]
        }
    }

    func flexibleCost(for player: Player, in state: GameState) -> String? {
        guard self == .armyCard, state.armyPrice != .oneOfEach else { return nil }
        let count = state.armyPrice == .anyOne ? 1 : 3
        let held = player.resources.values.reduce(0, +)
        return "Any \(count) · have \(held) \(held == 1 ? "card" : "cards")"
    }

    func inventoryDetail(for player: Player, in state: GameState) -> String? {
        guard self == .armyCard else { return nil }
        let cards = state.armyHands[player.id, default: []].sorted()
        return cards.isEmpty ? "No army cards held" : "Yours: " + cards.map(String.init).joined(separator: ", ")
    }

    func readyDetail(for player: Player, in state: GameState) -> String {
        switch self {
        case .ship: return "Launch at your coast · \(hullsRemaining(for: player, in: state)) hulls left"
        case .road: return "Choose an edge · \(state.rules.maxRoadsPerPlayer - player.roads.count) pieces left"
        case .settlement: return "Choose a corner · \(state.rules.pieceLimit(for: .settlement) - player.settlements.count) pieces left"
        case .city: return "Upgrade a settlement · \(state.rules.pieceLimit(for: .city) - player.cities.count) pieces left"
        case .devCard: return "Buy a card · \(state.devCardDeck.count) left"
        case .armyCard: return "Choose your payment · \(state.armyDeck.count) left"
        case .deployArmy: return "Choose a hex · \(state.armyHands[player.id, default: []].count) army cards"
        }
    }

    func unavailableDetail(for player: Player, in state: GameState, costs: [BuildActionPresentation.Cost]) -> String {
        if let phaseReason = phaseReason(for: player.id, in: state) { return phaseReason }
        if let supplyReason = supplyReason(for: player, in: state) { return supplyReason }
        let missing = costs.filter { $0.missing > 0 }
        if !missing.isEmpty {
            return "Need " + missing.map { "\($0.missing) \($0.resource.rawValue)" }.joined(separator: " · ")
        }
        if self == .armyCard, state.armyPrice != .oneOfEach {
            let count = state.armyPrice == .anyOne ? 1 : 3
            return "Need \(max(0, count - player.resources.values.reduce(0, +))) more resource cards"
        }
        return locationReason(for: player, in: state)
    }

    func phaseReason(for actor: PlayerID, in state: GameState) -> String? {
        guard state.phase != .mainTurn(playerIndex: actor.index) else { return nil }
        if case .gameOver = state.phase { return "The game has finished" }
        if state.phase == .rollDice(playerIndex: actor.index) { return "Roll the dice before building" }
        if state.phase.isSetup { return "Finish the starting placements first" }
        if state.phase.awaitingSeatIndex != actor.index { return "Available on your turn" }
        return "Finish the current decision first"
    }

    func supplyReason(for player: Player, in state: GameState) -> String? {
        switch self {
        case .ship where hullsRemaining(for: player, in: state) == 0: return "All six hulls have been built"
        case .road where player.roads.count >= state.rules.maxRoadsPerPlayer: return "No road pieces left"
        case .settlement where player.settlements.count >= state.rules.pieceLimit(for: .settlement):
            return "No settlement pieces left · upgrade one to a city"
        case .city where player.cities.count >= state.rules.pieceLimit(for: .city): return "No city pieces left"
        case .devCard where state.devCardDeck.isEmpty: return "Development deck is empty"
        case .armyCard where state.armyDeck.isEmpty: return "Army deck is empty"
        case .deployArmy where state.armyHands[player.id, default: []].isEmpty: return "Buy an army card first"
        default: return nil
        }
    }

    func locationReason(for player: Player, in state: GameState) -> String {
        switch self {
        case .ship: return "Requires your settlement or city on a charted coast"
        case .road: return "No connected land edge available"
        case .settlement:
            return state.mode == .naval ? "No legal corner reached by your roads or ships" : "No legal corner reached by your roads"
        case .city: return "Build a settlement to upgrade first"
        case .deployArmy: return "No producing hex touches your buildings"
        case .devCard, .armyCard: return "Finish the current decision first"
        }
    }

    func hullsRemaining(for player: Player, in state: GameState) -> Int {
        Naval.hullsPerBuilder - Naval.shipsBuilt(by: player.id, in: state)
    }
}
