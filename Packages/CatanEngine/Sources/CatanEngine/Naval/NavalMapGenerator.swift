import Foundation

struct NavalGeneratedMap {
    let board: Board
    let family: NavalMapFamily
    let islandByHex: [HexCoordinate: Int]
    var generationAttempts = 0
    var usedFallback = false
}

/// Family construction replaces unconstrained per-tile land shuffling: every island is grown
/// as a connected component inside a safe overseas belt, then the full world is validated.
enum NavalMapGenerator {
    static let generationAttempts = 64
    static let overseasLandCount = 28
    static let minimumOverseasRadius = 5
    static let anchors = [HexCoordinate(q: 6, r: 0), HexCoordinate(q: 0, r: 6),
                          HexCoordinate(q: -6, r: 0), HexCoordinate(q: 0, r: -6)]

    static func generate(using rng: inout RandomSource, options: NavalOptions) -> NavalGeneratedMap {
        let families = NavalMapFamily.allCases
        let family = options.mapFamily ?? families[Int(rng.next() % UInt64(families.count))]
        for attempt in 1...generationAttempts {
            guard let groups = islands(family: family, randomize: true, rng: &rng),
                  groupsAreDisjoint(groups) else { continue }
            var result = assemble(groups: groups, family: family, options: options, rng: &rng)
            result.generationAttempts = attempt
            if NavalMapValidation.problem(in: result) == nil { return result }
        }
        return fallback(family: family, options: options, using: &rng)
    }

    /// An explicit same-family escape hatch, also tested independently of lucky retries.
    static func fallback(family: NavalMapFamily, options: NavalOptions,
                         using rng: inout RandomSource, rotations: Int? = nil, reflected: Bool? = nil) -> NavalGeneratedMap {
        let turn = rotations ?? Int(rng.next() % 6)
        let mirror = reflected ?? (rng.next() % 2 == 0)
        let groups = NavalFallback.groups(for: family).map { group in
            group.map { transform($0, rotations: turn, reflected: mirror) }.sorted()
        }
        precondition(groupsAreDisjoint(groups), "same-family fallback overlaps land components")
        var fallback = assemble(groups: groups, family: family, options: options, rng: &rng)
        fallback.generationAttempts = generationAttempts
        fallback.usedFallback = true
        precondition(NavalMapValidation.problem(in: fallback) == nil,
                     "naval fallback violated \(NavalMapValidation.problem(in: fallback) ?? "unknown invariant")")
        return fallback
    }

    private static func sizes(for family: NavalMapFamily) -> [Int] {
        switch family {
        case .archipelago: return [7, 7, 7, 7]
        case .peninsula: return [14, 4, 7, 3]
        case .twinIslands: return [11, 3, 11, 3]
        }
    }

    private static func islands(family: NavalMapFamily, randomize: Bool,
                                rng: inout RandomSource) -> [[HexCoordinate]]? {
        let rotation = randomize ? Int(rng.next() % 6) : 0
        let reflected = randomize && rng.next() % 2 == 0
        var groups: [[HexCoordinate]] = []
        var reserved = Set<HexCoordinate>()
        for (index, entry) in zip(anchors, sizes(for: family)).enumerated() {
            let shape: [HexCoordinate]
            if family == .peninsula && index == 0 {
                shape = peninsula(randomize: randomize, rng: &rng)
            } else {
                guard let grown = grow(at: entry.0, size: entry.1, excluding: reserved, randomize: randomize, rng: &rng) else { return nil }
                shape = grown
            }
            reserved.formUnion(shape)
            reserved.formUnion(shape.flatMap { hex in (0..<6).map { hex.neighbor($0) } })
            groups.append(shape.map { transform($0, rotations: rotation, reflected: reflected) }.sorted())
        }
        return groups
    }

    private static func groupsAreDisjoint(_ groups: [[HexCoordinate]]) -> Bool {
        let coordinates = groups.flatMap { $0 }
        return coordinates.count == overseasLandCount && Set(coordinates).count == coordinates.count
    }

    /// A seven-hex core plus a narrow crescent or fork makes a genuine peninsula silhouette.
    private static func peninsula(randomize: Bool, rng: inout RandomSource) -> [HexCoordinate] {
        let core = [(6, 0), (6, -1), (5, 0), (5, 1), (6, 1), (7, 0), (7, -1)]
        let arms = [
            [(5, 2), (4, 2), (4, 3), (3, 3), (3, 4), (2, 4), (2, 5)],
            [(5, 2), (4, 2), (4, 3), (3, 3), (3, 4), (4, 1), (5, -1)],
            [(5, -1), (6, -2), (7, -2), (7, -3), (5, 2), (4, 2), (4, 3)],
        ]
        let index = randomize ? Int(rng.next() % UInt64(arms.count)) : 0
        return (core + arms[index]).map { HexCoordinate(q: $0.0, r: $0.1) }.sorted()
    }

    private static func grow(at anchor: HexCoordinate, size: Int, excluding reserved: Set<HexCoordinate>,
                             randomize: Bool, rng: inout RandomSource) -> [HexCoordinate]? {
        guard !reserved.contains(anchor) else { return nil }
        var selected: Set<HexCoordinate> = [anchor]
        let reach = size >= 14 ? 3 : 2
        while selected.count < size {
            let candidates = Set(selected.flatMap { hex in (0..<6).map { hex.neighbor($0) } })
                .filter { hex in
                    !selected.contains(hex) && !reserved.contains(hex) && hex.distance(to: anchor) <= reach
                        && (minimumOverseasRadius...Naval.worldRadius).contains(hex.distance(to: HexCoordinate(q: 0, r: 0)))
                }.sorted()
            guard !candidates.isEmpty else { return nil }
            let nearest = candidates.map { $0.distance(to: anchor) }.min() ?? 0
            let frontier = candidates.filter { $0.distance(to: anchor) == nearest }
            let choices = randomize ? (frontier + frontier + candidates) : frontier
            let index = randomize ? Int(rng.next() % UInt64(choices.count)) : 0
            selected.insert(choices[index])
        }
        return selected.sorted()
    }

    private static func transform(_ hex: HexCoordinate, rotations: Int, reflected: Bool) -> HexCoordinate {
        var result = reflected ? HexCoordinate(q: hex.r, r: hex.q) : hex
        for _ in 0..<rotations { result = HexCoordinate(q: -result.r, r: result.q + result.r) }
        return result
    }

    private static func assemble(groups: [[HexCoordinate]], family: NavalMapFamily,
                                 options: NavalOptions, rng: inout RandomSource) -> NavalGeneratedMap {
        let home = BoardGenerator.randomized(seed: rng.next()).tiles
        let overseas = NavalTerrain.overseasTiles(groups: groups, resourceChoice: options.resourceChoiceEnabled, rng: &rng)
        let land = home + overseas
        let landByHex = Dictionary(uniqueKeysWithValues: land.map { ($0.coordinate, $0) })
        let tiles = BoardGenerator.spiralCoordinates(radius: Naval.worldRadius).map { coordinate in
            landByHex[coordinate] ?? Tile(coordinate: coordinate, kind: .sea, numberToken: nil)
        }
        var ids = Dictionary(uniqueKeysWithValues: home.map { ($0.coordinate, 0) })
        for (index, group) in groups.enumerated() {
            for coordinate in group { ids[coordinate] = index + 1 }
        }
        let robber = home.first(where: { $0.kind == .desert })!.coordinate
        let bare = Naval.landBoard(tiles: tiles, ports: [], robber: robber)
        let ports = NavalPorts.make(in: bare, islandByHex: ids, rng: &rng)
        return NavalGeneratedMap(board: Naval.landBoard(tiles: tiles, ports: ports, robber: robber),
                                 family: family, islandByHex: ids)
    }
}
