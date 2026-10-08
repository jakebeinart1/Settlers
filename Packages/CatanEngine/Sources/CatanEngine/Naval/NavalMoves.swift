import Foundation

extension Naval {
    static func mainMoves(for player: Player, in state: GameState) -> [GameMove] {
        guard let naval = state.naval else { return [] }
        var moves: [GameMove] = []
        if RulesEngine.canAfford(shipCost, player: player) {
            moves += launchSites(for: player.id, in: state).map { .buildShip(at: $0) }
        }
        for ship in naval.ships.sorted(by: { $0.id < $1.id }) where ship.owner == player.id {
            moves += sailingDestinations(for: ship, in: state).map { .sailShip(id: ship.id, to: $0) }
        }
        return moves
    }

    static func captureMoves(for player: PlayerID, in state: GameState) -> [GameMove] {
        guard state.naval?.options.shipStealingEnabled == true else { return [] }
        let ships = (state.naval?.ships ?? []).filter { $0.owner != player }.sorted { $0.id < $1.id }
        return ships.map { .captureShip(id: $0.id) } + [.skipShipCapture]
    }

    static func applyMain(_ move: GameMove, by player: PlayerID, to state: inout GameState) throws -> [GameEvent] {
        switch move {
        case .buildShip(let coordinate): return try build(at: coordinate, by: player, state: &state)
        case .sailShip(let id, let coordinate): return try sail(id: id, to: coordinate, by: player, state: &state)
        default: throw MoveError.wrongPhase
        }
    }

    private static func build(at coordinate: HexCoordinate, by player: PlayerID, state: inout GameState) throws -> [GameEvent] {
        guard let naval = state.naval, launchSites(for: player, in: state).contains(coordinate),
              let index = state.players.firstIndex(where: { $0.id == player }) else { throw MoveError.illegalPlacement }
        try RulesEngine.deduct(shipCost, from: &state, playerIndex: index)
        let ship = Ship(id: naval.nextShipID, owner: player, coordinate: coordinate, stepsRemaining: movementPerTurn(in: state))
        state.naval?.ships.append(ship)
        state.naval?.nextShipID += 1
        state.naval?.hullsBuilt[player, default: 0] += 1
        return [.builtShip(player, shipID: ship.id, at: coordinate)] + reveal(around: [coordinate], by: player, in: &state)
    }

    private static func sail(id: Int, to coordinate: HexCoordinate, by player: PlayerID,
                             state: inout GameState) throws -> [GameEvent] {
        guard let index = state.naval?.ships.firstIndex(where: { $0.id == id }),
              let ship = state.naval?.ships[index], ship.owner == player,
              let route = sailingRoute(for: ship, to: coordinate, in: state) else { throw MoveError.illegalPlacement }
        if (state.naval?.rulesVersion ?? 0) >= sailingHistoryRulesVersion {
            state.naval?.ships[index].previousSailingOrigin = ship.coordinate
        }
        state.naval?.ships[index].coordinate = coordinate
        state.naval?.ships[index].stepsRemaining -= route.count
        return [.sailedShip(player, shipID: id, from: ship.coordinate, to: coordinate)]
            + reveal(around: route, by: player, in: &state)
    }

    static func applyCapture(_ move: GameMove, by player: PlayerID, to state: inout GameState) throws -> [GameEvent] {
        guard let naval = state.naval, naval.options.shipStealingEnabled else { throw MoveError.wrongPhase }
        switch move {
        case .skipShipCapture:
            state.naval?.capturePending = false
            state.naval?.productionRollerIndex = nil
            state.phase = .mainTurn(playerIndex: player.index)
            return []
        case .captureShip(let id):
            guard let index = naval.ships.firstIndex(where: { $0.id == id }), naval.ships[index].owner != player else {
                throw MoveError.illegalPlacement
            }
            let previous = naval.ships[index].owner
            let allowance = movementPerTurn(in: state)
            state.naval?.ships[index].owner = player
            state.naval?.ships[index].stepsRemaining = allowance
            if naval.rulesVersion >= sailingHistoryRulesVersion { state.naval?.ships[index].previousSailingOrigin = nil }
            state.naval?.capturePending = false
            state.naval?.productionRollerIndex = nil
            state.phase = .mainTurn(playerIndex: player.index)
            return [.capturedShip(player, shipID: id, from: previous)]
        default: throw MoveError.wrongPhase
        }
    }

    static func beginTurn(for player: PlayerID, in state: inout GameState) {
        guard let ships = state.naval?.ships else { return }
        let allowance = movementPerTurn(in: state)
        for index in ships.indices where ships[index].owner == player {
            state.naval?.ships[index].stepsRemaining = allowance
        }
        clearSailingOrigins(for: player, in: &state)
    }

    /// Discovery and a new settlement change expedition opportunities; resource
    /// spending and city upgrades do not. Older matches never record this history.
    static func clearSailingOrigins(for player: PlayerID? = nil, in state: inout GameState) {
        guard let naval = state.naval, naval.rulesVersion >= sailingHistoryRulesVersion else { return }
        for index in naval.ships.indices where player == nil || naval.ships[index].owner == player {
            state.naval?.ships[index].previousSailingOrigin = nil
        }
    }
}
