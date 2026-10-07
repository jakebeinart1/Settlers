import Foundation

/// Production budgets are independent from geography. The two flexible sites have fixed
/// moderate tokens and an ordinary underlying resource even when the option is disabled.
enum NavalTerrain {
    static let resources: [Resource] = Array(repeating: .lumber, count: 6)
        + Array(repeating: .grain, count: 6) + Array(repeating: .wool, count: 6)
        + Array(repeating: .brick, count: 5) + Array(repeating: .ore, count: 5)
    static let tokens = [2, 2, 12, 12] + (3...11).filter { $0 != 7 }.flatMap { Array(repeating: $0, count: 3) }

    static func overseasTiles(groups: [[HexCoordinate]], resourceChoice: Bool,
                              rng: inout RandomSource) -> [Tile] {
        let coordinates = groups.flatMap { $0 }.sorted()
        var kinds = Dictionary(uniqueKeysWithValues: zip(coordinates, resources.shuffled(using: &rng)))
        let substantial = groups.enumerated().sorted {
            $0.element.count == $1.element.count ? $0.offset < $1.offset : $0.element.count > $1.element.count
        }
        let first = ensure(.grain, in: substantial[0].element, kinds: &kinds)
        let second = ensure(.wool, in: substantial[1].element, kinds: &kinds)
        let fixed = [first: 4, second: 10]
        let numbers = assignTokens(to: coordinates, groups: groups, fixed: fixed, rng: &rng)
        return coordinates.map { coordinate in
            let kind: TileKind = resourceChoice && fixed[coordinate] != nil ? .resourceChoice : .resource(kinds[coordinate]!)
            return Tile(coordinate: coordinate, kind: kind, numberToken: numbers[coordinate])
        }
    }

    /// A swap preserves total resource counts and guarantees each substantial island's site.
    private static func ensure(_ resource: Resource, in group: [HexCoordinate],
                               kinds: inout [HexCoordinate: Resource]) -> HexCoordinate {
        if let existing = group.sorted().first(where: { kinds[$0] == resource }) { return existing }
        let target = group.sorted()[0]
        let source = kinds.keys.sorted().first(where: { kinds[$0] == resource })!
        let previous = kinds[target]!
        kinds[target] = resource
        kinds[source] = previous
        return target
    }

    private static func assignTokens(to coordinates: [HexCoordinate], groups: [[HexCoordinate]], fixed: [HexCoordinate: Int],
                                     rng: inout RandomSource) -> [HexCoordinate: Int] {
        let available = coordinates.filter { fixed[$0] == nil }.shuffled(using: &rng)
        let hot = independentHotSites(in: available, groups: groups)
        var highTokens = [6, 6, 6, 8, 8, 8].shuffled(using: &rng).makeIterator()
        var lowTokens = tokens.filter { $0 != 6 && $0 != 8 }
        lowTokens.remove(at: lowTokens.firstIndex(of: 4)!)
        lowTokens.remove(at: lowTokens.firstIndex(of: 10)!)
        var remaining = lowTokens.shuffled(using: &rng).makeIterator()
        var result = fixed
        for coordinate in coordinates where fixed[coordinate] == nil {
            result[coordinate] = hot.contains(coordinate) ? highTokens.next() : remaining.next()
        }
        return result
    }

    /// A coastal hot tile per component gives small islands a useful production floor;
    /// the remaining two retain random placement. Separation keeps reservations independent.
    private static func independentHotSites(in candidates: [HexCoordinate], groups: [[HexCoordinate]]) -> Set<HexCoordinate> {
        let land = Set(groups.flatMap { $0 })
        var selected = Set<HexCoordinate>()
        for group in groups {
            let sites = Set(group)
            guard let coastal = candidates.first(where: { hex in
                sites.contains(hex) && (0..<6).contains { direction in
                    let neighbor = hex.neighbor(direction)
                    return neighbor.distance(to: HexCoordinate(q: 0, r: 0)) <= Naval.worldRadius && !land.contains(neighbor)
                }
                    && (0..<6).allSatisfy { !selected.contains(hex.neighbor($0)) }
            }) else { preconditionFailure("component cannot reserve a coastal production site") }
            selected.insert(coastal)
        }
        for coordinate in candidates where selected.count < 6 {
            if (0..<6).allSatisfy({ !selected.contains(coordinate.neighbor($0)) }) { selected.insert(coordinate) }
        }
        precondition(selected.count == 6, "component budgets cannot place six separated hot tokens")
        return selected
    }
}
