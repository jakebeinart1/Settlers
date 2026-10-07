import Foundation

extension Naval {
    /// Every reachable destination, in stable coordinate order, through publicly charted sea.
    /// A ship's radius-two sight already charts its complete destination sailing range.
    public static func sailingDestinations(for ship: Ship, in state: GameState) -> [HexCoordinate] {
        sailingRoutes(for: ship, in: state).keys.sorted()
    }

    /// The shortest public sea route, excluding the origin and including the destination.
    ///
    /// Sorted neighbor expansion chooses one reproducible route when two shortest paths exist.
    /// Reveals use that same route, so previews, policy costs and replay cannot disagree about
    /// intermediate sight. Concealed terrain never determines routes or the public action mask.
    /// Legacy matches retain adjacent-only actions and their saved three-hex turn allowance.
    /// Rival-held hexes stop version 4 routes. Capture can leave rivals sharing the origin,
    /// so only neighbor entry is blocked; departure from that origin remains legal.
    public static func sailingRoute(for ship: Ship, to destination: HexCoordinate,
                                    in state: GameState) -> [HexCoordinate]? {
        sailingRoutes(for: ship, in: state)[destination]
    }

    private static func sailingRoutes(for ship: Ship, in state: GameState) -> [HexCoordinate: [HexCoordinate]] {
        guard let naval = state.naval, ship.stepsRemaining > 0 else { return [:] }
        let limit = naval.rulesVersion < destinationSailingRulesVersion ? 1 : min(ship.stepsRemaining, movementPerTurn(in: state))
        let sea = Set(state.board.tiles.filter { isRevealed($0.coordinate, in: state) && $0.kind == .sea }.map(\.coordinate))
        guard sea.contains(ship.coordinate) else { return [:] }
        var routes: [HexCoordinate: [HexCoordinate]] = [ship.coordinate: []]
        var queue = [ship.coordinate]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            let route = routes[current]!
            guard route.count < limit else { continue }
            for next in (0..<6).map({ current.neighbor($0) }).sorted()
                where sea.contains(next) && routes[next] == nil && !isBlockaded(next, by: ship.owner, in: state) {
                routes[next] = route + [next]
                queue.append(next)
            }
        }
        routes[ship.coordinate] = nil
        return routes
    }
}
