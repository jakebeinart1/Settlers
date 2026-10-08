#if DEBUG
import CatanEngine

/// Deterministic, conserved rare-state baselines for native tests. Setup,
/// purchases, discovery, colony founding and rolls all use the real rules.
/// The only travel shortcut refreshes steps between fixture-only sailing
/// rounds; ordinary gameplay never calls this type.
enum NavalQAFixture {
    enum Position: Sendable { case voyage, capture, shipLoss, harvest, cityHarvest, adjacentShips, stackedShips, mixedShips, genericPort, resourcePort }
    private static let actor = PlayerID(index: 0)
    private static let seed: UInt64 = 7_501
    private static let portTradeCards = 9

    static func make(_ position: Position, options: NavalOptions = NavalOptions()) throws -> GameState {
        var state = Naval.newGame(seed: seed, options: options)
        if position == .capture || position == .shipLoss { state.naval?.options.shipStealingEnabled = true }
        // This historical art fixture deliberately sails rivals onto one cell.
        // v4 captures may create mixed stacks, but entering one is now prohibited.
        if position == .mixedShips { state.naval?.rulesVersion = 3 }
        while state.phase.isSetup {
            let seat = PlayerID(index: state.phase.awaitingSeatIndex!)
            let move = setupMove(for: seat, position: position, in: state)
            try RulesEngine.apply(move, by: seat, to: &state)
        }
        state.phase = .mainTurn(playerIndex: actor.index)
        grant([.lumber: 3, .wool: 2, .ore: 2, .grain: 1, .brick: 1], to: actor, in: &state)
        switch position {
        case .voyage: break
        case .capture: try prepareCapture(in: &state)
        case .shipLoss: try prepareShipLoss(in: &state)
        case .harvest: try prepareHarvest(in: &state)
        case .cityHarvest: try prepareHarvest(upgradeToCity: true, in: &state)
        case .adjacentShips: try prepareNearbyShips(stacked: false, in: &state)
        case .stackedShips: try prepareNearbyShips(stacked: true, in: &state)
        case .mixedShips: try prepareMixedShips(in: &state)
        case .genericPort: grant([.lumber: portTradeCards], to: actor, in: &state)
        case .resourcePort: grant([.grain: portTradeCards], to: actor, in: &state)
        }
        return state
    }

    /// Preparation purchases a human hull and rigs the rival's next roll.
    /// The runner must still roll, choose capture and durably transfer it.
    private static func prepareShipLoss(in state: inout GameState) throws {
        _ = try purchase(for: actor, in: &state)
        state.phase = .rollDice(playerIndex: 1)
        state.rng = rollSource(total: 11)
    }

    /// Only harbor fixtures choose the actor's first legal home-port corner.
    /// Every placement and road is still applied by the engine; existing rare
    /// positions retain their original first-legal setup sequence.
    private static func setupMove(for seat: PlayerID, position: Position, in state: GameState) -> GameMove {
        let legal = RulesEngine.legalMoves(for: state, seat: seat)
        let kind: PortKind?
        switch position {
        case .genericPort: kind = .generic
        case .resourcePort: kind = .resource(.grain)
        default: kind = nil
        }
        guard seat == actor, state.players[actor.index].settlements.isEmpty, let kind else { return legal.first! }
        let port = state.board.ports.first { port in
            port.kind == kind && [port.vertexA, port.vertexB].flatMap(\.touchingTiles).contains {
                state.naval?.islandByHex[$0] == 0
            }
        }!
        return legal.first { move in
            guard case .placeInitialSettlement(let vertex) = move else { return false }
            return vertex == port.vertexA || vertex == port.vertexB
        }!
    }

    static func grant(_ cards: [Resource: Int], to player: PlayerID, in state: inout GameState) {
        for resource in Resource.allCases {
            let amount = cards[resource, default: 0]
            precondition(state.bank[resource, default: 0] >= amount)
            state.players[player.index].resources[resource, default: 0] += amount
            state.bank[resource, default: 0] -= amount
        }
    }

    /// QA changes a hand through the bank, preserving every resource supply.
    /// Ordinary setup, connected coast and piece stock remain the real baseline.
    static func replaceHand(_ cards: [Resource: Int], for player: PlayerID, in state: inout GameState) {
        for resource in Resource.allCases {
            state.bank[resource, default: 0] += state.players[player.index].resources[resource, default: 0]
        }
        state.players[player.index].resources = [:]
        grant(cards, to: player, in: &state)
    }

    static func purchase(for player: PlayerID, in state: inout GameState) throws -> Int {
        state.phase = .mainTurn(playerIndex: player.index)
        let move = RulesEngine.legalMoves(for: state, seat: player).first {
            if case .buildShip = $0 { return true }
            return false
        }!
        try RulesEngine.apply(move, by: player, to: &state)
        return state.naval!.ships.last!.id
    }

    /// Actual conserved purchases place hulls together; one actual sailing
    /// step creates the adjacent control that overlaps at World zoom.
    private static func prepareNearbyShips(stacked: Bool, in state: inout GameState) throws {
        for _ in 0..<(stacked ? 3 : 2) {
            grant(Naval.shipCost, to: actor, in: &state)
            _ = try purchase(for: actor, in: &state)
        }
        let move = RulesEngine.legalMoves(for: state, seat: actor).first {
            if case .sailShip(let id, let destination) = $0 {
                return id == 1 && state.naval!.ships[1].coordinate.distance(to: destination) == 1
            }
            return false
        }!
        try RulesEngine.apply(move, by: actor, to: &state)
        precondition(state.naval!.ships[0].coordinate.distance(to: state.naval!.ships[1].coordinate) == 1)
    }

    private static func prepareCapture(in state: inout GameState) throws {
        let rival = PlayerID(index: 1)
        grant(Naval.shipCost, to: rival, in: &state)
        _ = try purchase(for: rival, in: &state)
        state.phase = .rollDice(playerIndex: actor.index)
        state.rng = rollSource(total: 11)
        try RulesEngine.apply(.rollDice, by: actor, to: &state)
        precondition(state.phase == .capturingShip(playerIndex: actor.index))
    }

    /// Two actual purchases and legal sea steps form a mixed-controller
    /// stack. Only the same explicit QA travel refresh used by harvest
    /// baselines skips intervening rounds; identities and ownership are real.
    private static func prepareMixedShips(in state: inout GameState) throws {
        let first = try purchase(for: actor, in: &state)
        let destination = state.naval!.ships.first { $0.id == first }!.coordinate
        let rival = PlayerID(index: 1)
        grant(Naval.shipCost, to: rival, in: &state)
        let second = try purchase(for: rival, in: &state)
        let origin = state.naval!.ships.first { $0.id == second }!.coordinate
        let sea = Set(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        for next in shortestPath(from: origin, to: [destination], sea: sea) {
            let index = state.naval!.ships.firstIndex { $0.id == second }!
            state.naval!.ships[index].stepsRemaining = Naval.movementPerTurn(in: state)
            try RulesEngine.apply(.sailShip(id: second, to: next), by: rival, to: &state)
        }
        state.phase = .mainTurn(playerIndex: actor.index)
        precondition(state.naval!.ships.allSatisfy { $0.coordinate == destination })
    }

    private static func prepareHarvest(upgradeToCity: Bool = false, in state: inout GameState) throws {
        let tile = state.board.tiles.first { $0.kind == .resourceChoice }!
        let shipID = try purchase(for: actor, in: &state)
        let sea = Set(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        let goals = Set(state.board.corners(of: tile.coordinate).flatMap(\.touchingTiles)).intersection(sea)
        let origin = state.naval!.ships.first { $0.id == shipID }!.coordinate
        for destination in shortestPath(from: origin, to: goals, sea: sea) {
            let index = state.naval!.ships.firstIndex { $0.id == shipID }!
            state.naval!.ships[index].stepsRemaining = Naval.movementPerTurn(in: state)
            try RulesEngine.apply(.sailShip(id: shipID, to: destination), by: actor, to: &state)
        }
        let vertex = state.board.corners(of: tile.coordinate).first {
            Naval.canFoundColony(at: $0, by: actor, in: state)
        }!
        try RulesEngine.apply(.buildSettlement(vertex), by: actor, to: &state)
        if upgradeToCity {
            grant(Building.cityCost, to: actor, in: &state)
            try RulesEngine.apply(.buildCity(vertex), by: actor, to: &state)
        }
        state.phase = .rollDice(playerIndex: actor.index)
        state.rng = rollSource(total: tile.numberToken!)
        try RulesEngine.apply(.rollDice, by: actor, to: &state)
        precondition(state.phase == .choosingResource(playerIndex: actor.index))
    }

    static func shortestPath(from start: HexCoordinate, to goals: Set<HexCoordinate>,
                             sea: Set<HexCoordinate>) -> [HexCoordinate] {
        var queue = [start]
        var visited: Set<HexCoordinate> = [start]
        var paths: [HexCoordinate: [HexCoordinate]] = [start: []]
        var cursor = 0
        while cursor < queue.count {
            let coordinate = queue[cursor]
            cursor += 1
            if goals.contains(coordinate) { return paths[coordinate]! }
            for next in (0..<6).map(coordinate.neighbor).sorted() where sea.contains(next) {
                guard visited.insert(next).inserted else { continue }
                paths[next] = paths[coordinate]! + [next]
                queue.append(next)
            }
        }
        preconditionFailure("Naval fixture has no navigable route to its harvest island")
    }

    static func rollSource(total: Int) -> RandomSource {
        for candidate in UInt64(0)..<10_000 {
            var source = RandomSource(seed: candidate)
            let sum = Int.random(in: 1...6, using: &source) + Int.random(in: 1...6, using: &source)
            if sum == total { return RandomSource(seed: candidate) }
        }
        preconditionFailure("No fixture seed for roll \(total)")
    }
}
#endif
