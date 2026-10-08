import Foundation

extension Naval {
    /// Validates authoritative saves/checkpoints. A deliberately masked observation is not a save.
    public static func validationProblem(in state: GameState) -> String? {
        guard state.mode == .naval else { return state.naval == nil ? nil : "naval state in another mode" }
        guard let naval = state.naval, state.variant == .standard,
              state.garrisons.isEmpty, state.armyDeck.isEmpty, state.armyHands.isEmpty,
              (oldestSupportedRulesVersion...currentRulesVersion).contains(naval.rulesVersion),
              naval.mapVersion == currentMapVersion else {
            return "naval mode/version"
        }
        let map = NavalGeneratedMap(board: state.board, family: naval.mapFamily, islandByHex: naval.islandByHex)
        if let problem = NavalMapValidation.problem(in: map) { return problem }
        let choiceCount = state.board.tiles.filter { $0.kind == .resourceChoice }.count
        guard choiceCount == (naval.options.resourceChoiceEnabled ? 2 : 0),
              naval.options.mapFamily.map({ $0 == naval.mapFamily }) ?? true else { return "naval option/world disagreement" }
        let coordinates = Set(state.board.tiles.map(\.coordinate))
        guard naval.revealed.isSubset(of: coordinates),
              Set(BoardGenerator.spiralCoordinates(radius: homeRadius)).isSubset(of: naval.revealed),
              isKnownLand(state.board.robberTile, in: state),
              naval.options.fogEnabled || naval.revealed == coordinates else { return "naval visibility/robber" }
        if let problem = shipProblem(naval, in: state) { return problem }
        if let problem = colonyProblem(naval, in: state) { return problem }
        return productionProblem(naval, in: state)
    }

    private static func shipProblem(_ naval: NavalState, in state: GameState) -> String? {
        let owners = Set(state.players.map(\.id))
        let ids = naval.ships.map(\.id)
        guard Set(ids).count == ids.count, ids.allSatisfy({ $0 >= 0 && $0 < naval.nextShipID }),
              naval.nextShipID == naval.ships.count, naval.nextShipID < Int.max,
              naval.hullsBuilt.keys.allSatisfy(owners.contains),
              naval.hullsBuilt.values.allSatisfy({ (0...hullsPerBuilder).contains($0) }),
              naval.hullsBuilt.values.reduce(0, +) == naval.ships.count else { return "naval hull identity/stock" }
        guard naval.ships.allSatisfy({ ship in
            owners.contains(ship.owner) && (0...movementPerTurn(in: state)).contains(ship.stepsRemaining)
                && naval.revealed.contains(ship.coordinate)
                && state.board.tiles.contains { $0.coordinate == ship.coordinate && $0.kind == .sea }
                && state.board.tiles.filter { $0.coordinate.distance(to: ship.coordinate) <= viewingRange }
                    .allSatisfy { naval.revealed.contains($0.coordinate) }
                && validSailingOrigin(for: ship, naval: naval, in: state)
        }) else { return "naval ship position/movement" }
        return nil
    }

    private static func validSailingOrigin(for ship: Ship, naval: NavalState, in state: GameState) -> Bool {
        guard let origin = ship.previousSailingOrigin else { return true }
        return naval.rulesVersion >= sailingHistoryRulesVersion && ship.stepsRemaining < movementPerTurn(in: state)
            && (1...movementPerTurn(in: state)).contains(origin.distance(to: ship.coordinate))
            && naval.revealed.contains(origin)
            && state.board.tiles.contains { $0.coordinate == origin && $0.kind == .sea }
    }

    private static func colonyProblem(_ naval: NavalState, in state: GameState) -> String? {
        let owners = Set(state.players.map(\.id))
        guard naval.colonyPoints.keys.allSatisfy(owners.contains), naval.colonizedIslands.keys.allSatisfy(owners.contains),
              naval.colonyPoints.values.allSatisfy({ (0...maximumColonyPoints).contains($0) }),
              naval.colonizedIslands.values.allSatisfy({ $0.isSubset(of: Set(1...4)) }) else { return "naval colony score" }
        for owner in owners {
            let visited = naval.colonizedIslands[owner, default: []].count
            guard naval.colonyPoints[owner, default: 0] == min(visited, maximumColonyPoints) else { return "naval colony history" }
        }
        return nil
    }

    private static func productionProblem(_ naval: NavalState, in state: GameState) -> String? {
        guard naval.pendingResourceChoices.allSatisfy({ state.players.indices.contains($0.playerIndex) && $0.remaining > 0 }),
              Set(naval.pendingResourceChoices.map(\.playerIndex)).count == naval.pendingResourceChoices.count,
              naval.productionRollerIndex.map(state.players.indices.contains) ?? true else { return "naval production obligations" }
        switch state.phase {
        case .choosingResource(let index):
            return choiceProblem(naval, index: index, in: state)
        case .capturingShip(let index):
            guard naval.options.shipStealingEnabled, state.lastDiceRoll == 11,
                  naval.capturePending, naval.productionRollerIndex == index,
                  naval.pendingResourceChoices.isEmpty,
                  naval.ships.contains(where: { $0.owner.index != index }) else { return "naval capture phase" }
        default:
            guard !naval.capturePending, naval.productionRollerIndex == nil, naval.pendingResourceChoices.isEmpty else {
                return "naval pending production outside resolution"
            }
        }
        return nil
    }

    private static func choiceProblem(_ naval: NavalState, index: Int, in state: GameState) -> String? {
        guard let roller = naval.productionRollerIndex, let roll = state.lastDiceRoll,
              [4, 10].contains(roll), naval.options.resourceChoiceEnabled, !naval.capturePending,
              naval.pendingResourceChoices.first?.playerIndex == index,
              Resource.allCases.contains(where: { state.bank[$0, default: 0] > 0 }) else { return "naval choice phase" }
        let expected = resourceChoices(for: roll, rollerIndex: roller, in: state)
        guard let start = expected.firstIndex(where: { $0.playerIndex == index }) else { return "naval choice entitlement" }
        let suffix = Array(expected[start...])
        let pending = naval.pendingResourceChoices
        guard pending.count == suffix.count else { return "naval choice suffix" }
        for offset in pending.indices {
            guard pending[offset].playerIndex == suffix[offset].playerIndex,
                  pending[offset].remaining <= suffix[offset].remaining,
                  offset == 0 || pending[offset].remaining == suffix[offset].remaining else { return "naval choice entitlement" }
        }
        return nil
    }
}
