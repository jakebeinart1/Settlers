import CatanEngine

/// Policy-independent trajectory evidence. A colony or discovery can justify
/// productive backtracking; movement and counter changes cannot erase a stall.
public struct NavalNavigationDiagnostics {
    public private(set) var rawRevisits = 0
    public private(set) var idleRevisits = 0
    public private(set) var progressSteps = 0
    private var turn: Int?
    private var rawVisited: [Int: Set<HexCoordinate>] = [:]
    private var idleVisited: [Int: Set<HexCoordinate>] = [:]
    private var marker: [Int] = []

    public init() {}

    @discardableResult
    public mutating func observe(_ move: GameMove, by actor: PlayerID, before: GameState, after: GameState) -> Bool {
        if case .mainTurn(let roller) = before.phase {
            if turn != roller {
                turn = roller
                rawVisited = positions(in: before)
                marker = []
            }
        } else { turn = nil }
        let opportunity = expeditionMarker(in: before)
        if opportunity != marker {
            marker = opportunity
            idleVisited = positions(in: before)
        }
        for ship in after.naval?.ships ?? [] where before.naval?.ships.contains(where: { $0.id == ship.id }) != true {
            rawVisited[ship.id] = [ship.coordinate]
            idleVisited[ship.id] = [ship.coordinate]
        }
        guard case .sailShip(let id, let destination) = move,
              let ship = before.naval?.ships.first(where: { $0.id == id }),
              let route = Naval.sailingRoute(for: ship, to: destination, in: before) else { return false }
        for coordinate in route {
            if !rawVisited[id, default: []].insert(coordinate).inserted { rawRevisits += 1 }
            if !idleVisited[id, default: []].insert(coordinate).inserted { idleRevisits += 1 }
        }
        let progress = productiveHexes(along: route, from: ship.coordinate, for: actor, in: before)
        progressSteps += progress
        return progress > 0
    }

    /// Sea at ring three touches a home coast. Only overseas LAND identifies
    /// a colony, including vertices whose other touching hexes are ocean.
    public static func isOverseasSite(_ vertex: VertexID, in state: GameState) -> Bool {
        vertex.touchingTiles.contains { coordinate in
            coordinate.distance(to: HexCoordinate(q: 0, r: 0)) >= 5
                && Naval.isKnownLand(coordinate, in: state)
        }
    }

    private func positions(in state: GameState) -> [Int: Set<HexCoordinate>] {
        Dictionary(uniqueKeysWithValues: (state.naval?.ships ?? []).map { ($0.id, Set([$0.coordinate])) })
    }

    /// Count real travelled hexes rather than endpoint actions. Each leg sees only
    /// discoveries committed by earlier legs, matching the former adjacent-move evidence.
    private func productiveHexes(along route: [HexCoordinate], from origin: HexCoordinate,
                                 for actor: PlayerID, in state: GameState) -> Int {
        var position = origin
        var known = state
        var count = 0
        for coordinate in route {
            let visible = Set(state.board.tiles.filter { $0.coordinate.distance(to: coordinate) <= Naval.viewingRange }.map(\.coordinate))
            let reveals = !visible.isSubset(of: known.naval?.revealed ?? [])
            if reveals || approachesColony(from: position, to: coordinate, for: actor, in: known) { count += 1 }
            known.naval?.revealed.formUnion(visible)
            position = coordinate
        }
        return count
    }

    /// Building totals survive city upgrades. Fresh land access, public terrain
    /// and fleet ownership are substantive changes; resources, coordinates,
    /// remaining steps, logs and action counters are deliberately absent.
    private func expeditionMarker(in state: GameState) -> [Int] {
        [state.naval?.revealed.count ?? 0]
            + state.players.sorted { $0.id < $1.id }.map { $0.settlements.count + $0.cities.count }
            + (state.naval?.ships ?? []).sorted { $0.id < $1.id }.flatMap { [$0.id, $0.owner.index] }
    }

    private func approachesColony(from origin: HexCoordinate, to destination: HexCoordinate,
                                  for actor: PlayerID, in state: GameState) -> Bool {
        let sea = Set(state.board.tiles.filter {
            $0.kind == .sea && Naval.isRevealed($0.coordinate, in: state)
                && ($0.coordinate == origin || !Naval.isBlockaded($0.coordinate, by: actor, in: state))
        }.map(\.coordinate))
        let targets = Set(Naval.potentialColonySites(for: actor, in: state)
            .filter { Self.isOverseasSite($0, in: state) }.flatMap(\.touchingTiles)).intersection(sea)
        guard !targets.isEmpty else { return false }
        var distances = Dictionary(uniqueKeysWithValues: targets.sorted().map { ($0, 0) })
        var queue = targets.sorted()
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            // Reverse search may reach a mixed-owner starting hex, but passing
            // through it would invent a route forbidden by the forward engine.
            if current == origin, Naval.isBlockaded(origin, by: actor, in: state) { continue }
            for direction in 0..<6 {
                let next = current.neighbor(direction)
                guard sea.contains(next), distances[next] == nil else { continue }
                distances[next] = distances[current, default: 0] + 1
                queue.append(next)
            }
        }
        guard let start = distances[origin], let end = distances[destination] else { return false }
        return end < start
    }
}
