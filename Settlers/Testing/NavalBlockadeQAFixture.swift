#if DEBUG
import CatanEngine

/// Generated-world replacement baselines for blockade interaction. Every hull
/// is bought and sailed through the rules with bank-conserved cards. Like the
/// harvest fixture, preparation refreshes travel and sets the acting phase;
/// subsequent native actions use the ordinary session and checkpoint path.
enum NavalBlockadeQAFixture {
    enum Position: CaseIterable, Sendable { case passage, capture, launch }
    private static let actor = PlayerID(index: 0)
    private static let rival = PlayerID(index: 1)
    private static let homeMoatOuterRadius = 4

    static func make(_ position: Position, options: NavalOptions = NavalOptions()) throws -> GameState {
        var state = try NavalQAFixture.make(.voyage, options: options)
        if position == .launch {
            try blockLaunchCoast(in: &state)
        } else {
            try blockPassage(in: &state)
            if position == .capture {
                state.naval?.options.shipStealingEnabled = true
                state.phase = .rollDice(playerIndex: actor.index)
                state.rng = NavalQAFixture.rollSource(total: 11)
                try RulesEngine.apply(.rollDice, by: actor, to: &state)
                precondition(state.phase == .capturingShip(playerIndex: actor.index))
            }
        }
        precondition(Naval.validationProblem(in: state) == nil)
        return state
    }

    /// A straight two-hex destination has one intermediate cell, even in open
    /// ocean. This proves a travel-budget obstruction, not a global choke point.
    static func destination(in state: GameState) -> HexCoordinate {
        let origin = state.naval!.ships.first { $0.id == 0 }!.coordinate
        let blocker = state.naval!.ships.first { $0.id == 1 }!.coordinate
        return HexCoordinate(q: 2 * blocker.q - origin.q, r: 2 * blocker.r - origin.r)
    }

    private static func blockPassage(in state: inout GameState) throws {
        NavalQAFixture.grant(Naval.shipCost, to: actor, in: &state)
        let ownedID = try NavalQAFixture.purchase(for: actor, in: &state)
        let origin = state.naval!.ships.first { $0.id == ownedID }!.coordinate
        let pair = passageCoordinates(from: origin, in: state)
        try travel(ownedID, to: pair.origin, in: &state)
        NavalQAFixture.grant(Naval.shipCost, to: rival, in: &state)
        let rivalID = try NavalQAFixture.purchase(for: rival, in: &state)
        try travel(rivalID, to: pair.blocker, in: &state)
        state.naval!.ships[ownedID].stepsRemaining = Naval.movementPerTurn(in: state)
        state.naval!.ships[rivalID].stepsRemaining = 0
        state.phase = .mainTurn(playerIndex: actor.index)
        precondition(state.naval!.ships.count == 2 && ownedID == 0 && rivalID == 1)
        precondition(Naval.isBlockaded(pair.blocker, by: actor, in: state))
        precondition(Naval.sailingRoute(for: state.naval!.ships[ownedID], to: destination(in: state), in: state) == nil)
    }

    /// Home has a two-hex sea moat. Staying within radii 3–4 gives readable
    /// local screenshots and a connected route around the occupied origin.
    private static func passageCoordinates(from launch: HexCoordinate,
                                           in state: GameState) -> (origin: HexCoordinate, blocker: HexCoordinate) {
        let home = HexCoordinate(q: 0, r: 0)
        let sea = Set(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        let candidates = sea.filter { $0.distance(to: home) <= homeMoatOuterRadius }.sorted {
            let lhs = $0.distance(to: launch), rhs = $1.distance(to: launch)
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
        for origin in candidates {
            for direction in 0..<6 {
                let blocker = origin.neighbor(direction)
                let destination = blocker.neighbor(direction)
                if sea.contains(blocker), sea.contains(destination),
                   blocker.distance(to: home) <= homeMoatOuterRadius,
                   destination.distance(to: home) <= homeMoatOuterRadius {
                    return (origin, blocker)
                }
            }
        }
        preconditionFailure("Generated Naval fixture has no straight sea passage in its home moat")
    }

    private static func blockLaunchCoast(in state: inout GameState) throws {
        let coast = Naval.launchSites(for: actor, in: state)
        precondition(!coast.isEmpty && coast.count <= Naval.hullsPerBuilder)
        for destination in coast {
            NavalQAFixture.grant(Naval.shipCost, to: rival, in: &state)
            let shipID = try NavalQAFixture.purchase(for: rival, in: &state)
            try travel(shipID, to: destination, in: &state)
            state.naval!.ships[shipID].stepsRemaining = 0
        }
        NavalQAFixture.replaceHand(Naval.shipCost, for: actor, in: &state)
        state.phase = .mainTurn(playerIndex: actor.index)
        precondition(Naval.launchSites(for: actor, in: state).isEmpty)
        precondition(Naval.blockadedLaunchSites(for: actor, in: state) == coast)
    }

    /// Full geography only chooses this explicit fixture's preparation path;
    /// each adjacent move still uses public production legality and reveals.
    private static func travel(_ shipID: Int, to destination: HexCoordinate, in state: inout GameState) throws {
        let ship = state.naval!.ships.first { $0.id == shipID }!
        let occupied = Set(state.naval!.ships.filter { $0.owner != ship.owner }.map(\.coordinate))
        let sea = Set(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate)).subtracting(occupied)
        let path = NavalQAFixture.shortestPath(from: ship.coordinate, to: [destination], sea: sea)
        state.phase = .mainTurn(playerIndex: ship.owner.index)
        for next in path {
            state.naval!.ships[shipID].stepsRemaining = Naval.movementPerTurn(in: state)
            try RulesEngine.apply(.sailShip(id: shipID, to: next), by: ship.owner, to: &state)
        }
    }
}
#endif
