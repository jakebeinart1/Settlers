import Foundation

/// Reject geometric and economic false greens before a generated world reaches a player.
enum NavalMapValidation {
    static func problem(in map: NavalGeneratedMap) -> String? {
        let board = map.board
        let envelope = Set(BoardGenerator.spiralCoordinates(radius: Naval.worldRadius))
        guard board.tiles.count == envelope.count, Set(board.tiles.map(\.coordinate)) == envelope else { return "world envelope" }
        let land = board.tiles.filter { $0.kind.isLand }
        guard land.count == 47, Set(map.islandByHex.keys) == Set(land.map(\.coordinate)),
              Set(map.islandByHex.values) == Set(0...4) else { return "land budget/partition" }
        let edges = Set(land.flatMap { HexGeometry.edges(of: $0.coordinate) })
        guard board.onBoardEdges == edges, board.onBoardVertices == Set(edges.flatMap { [$0.a, $0.b] }) else { return "land topology" }
        guard familySizesAreValid(in: map), labelsMatchConnectivity(in: map) else { return "family components" }
        guard Set(map.islandByHex.filter({ $0.value == 0 }).map(\.key))
                == Set(BoardGenerator.spiralCoordinates(radius: Naval.homeRadius)),
              map.islandByHex.allSatisfy({ $0.value == 0 || $0.key.distance(to: HexCoordinate(q: 0, r: 0)) >= 5 }) else {
            return "home sea moat"
        }
        let sea = Set(board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        guard let origin = sea.sorted().first, flood(from: [origin], within: sea).count == sea.count else { return "disconnected sea" }
        for island in 1...4 {
            let region = Set(map.islandByHex.filter { $0.value == island }.map(\.key))
            guard let first = region.sorted().first, flood(from: [first], within: region).count == region.count else {
                return "disconnected island"
            }
            guard region.allSatisfy({ coordinate in sea.contains { coordinate.distance(to: $0) <= Naval.viewingRange } }) else {
                return "unreachable island interior"
            }
            guard coastalCapacity(island: island, in: map) >= 3 else { return "insufficient coastal sites" }
        }
        guard board.ports.count == 9, Set(board.ports.flatMap { [$0.vertexA, $0.vertexB] }).count == 18 else { return "port overlap/count" }
        guard portsAreCoastal(in: board) else { return "noncoastal port" }
        guard productionIsValid(map) else { return "production budget/adjacency" }
        guard homeHarborsHaveAlternatives(in: map, sea: sea) else { return "one-way home expedition" }
        return nil
    }

    private static func familySizesAreValid(in map: NavalGeneratedMap) -> Bool {
        let actual = (1...4).map { island in map.islandByHex.values.filter { $0 == island }.count }.sorted()
        let expected: [Int]
        switch map.family {
        case .archipelago: expected = [7, 7, 7, 7]
        case .peninsula: expected = [3, 4, 7, 14]
        case .twinIslands: expected = [3, 3, 11, 11]
        }
        return actual == expected
    }

    private static func labelsMatchConnectivity(in map: NavalGeneratedMap) -> Bool {
        map.islandByHex.allSatisfy { coordinate, island in
            (0..<6).allSatisfy { direction in
                let neighbor = map.islandByHex[coordinate.neighbor(direction)]
                return neighbor == nil || neighbor == island
            }
        }
    }

    private static func portsAreCoastal(in board: Board) -> Bool {
        let kinds = Dictionary(uniqueKeysWithValues: board.tiles.map { ($0.coordinate, $0.kind) })
        return board.ports.allSatisfy { port in
            let touching = Set(port.vertexA.touchingTiles).intersection(port.vertexB.touchingTiles)
            return board.onBoardEdges.contains(EdgeID(port.vertexA, port.vertexB))
                && touching.contains { kinds[$0]?.isLand == true } && touching.contains { kinds[$0] == .sea }
        }
    }

    private static func productionIsValid(_ map: NavalGeneratedMap) -> Bool {
        let board = map.board
        let home = board.tiles.filter { map.islandByHex[$0.coordinate] == 0 }
        let overseas = board.tiles.filter { (map.islandByHex[$0.coordinate] ?? 0) > 0 }
        let choices = overseas.filter { $0.kind == .resourceChoice }
        guard choices.count == 0 || choices.count == 2,
              board.tiles.allSatisfy({ $0.kind.produces ? (2...12).contains($0.numberToken ?? 0) && $0.numberToken != 7 : $0.numberToken == nil }) else {
            return false
        }
        let ordinary = [Resource.lumber: 6, .grain: 6, .wool: 6, .brick: 5, .ore: 5]
        var expected = ordinary
        if !choices.isEmpty {
            expected[.grain] = 5
            expected[.wool] = 5
            guard choices.map({ $0.numberToken! }).sorted() == [4, 10],
                  Set(choices.compactMap { map.islandByHex[$0.coordinate] }).count == 2 else { return false }
        }
        guard resourceCounts(in: home) == [.grain: 4, .wool: 4, .lumber: 4, .brick: 3, .ore: 3],
              home.filter({ $0.kind == .desert }).count == 1, resourceCounts(in: overseas) == expected,
              home.compactMap(\.numberToken).sorted() == BoardGenerator.standardNumberOrder.sorted(),
              overseas.compactMap(\.numberToken).sorted() == NavalTerrain.tokens.sorted() else { return false }
        let hot = Set(board.tiles.filter { $0.numberToken == 6 || $0.numberToken == 8 }.map(\.coordinate))
        let sea = Set(board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        let usefulIslands = (1...4).allSatisfy { island in
            hot.contains { hex in map.islandByHex[hex] == island && (0..<6).contains { sea.contains(hex.neighbor($0)) } }
        }
        return usefulIslands && hot.allSatisfy { hex in (0..<6).allSatisfy { !hot.contains(hex.neighbor($0)) } }
    }

    private static func resourceCounts(in tiles: [Tile]) -> [Resource: Int] {
        var counts: [Resource: Int] = [:]
        for tile in tiles {
            if case .resource(let resource) = tile.kind { counts[resource, default: 0] += 1 }
        }
        return counts
    }

    private static func coastalCapacity(island: Int, in map: NavalGeneratedMap) -> Int {
        let edges = NavalPorts.coastEdges(in: map.board, islandByHex: map.islandByHex, island: island)
        let sites = Set(edges.flatMap { [$0.a, $0.b] }).sorted()
        var occupied = Set<VertexID>()
        for site in sites where !map.board.adjacentVertices(of: site).contains(where: occupied.contains) {
            occupied.insert(site)
        }
        return occupied.count
    }

    private static func homeHarborsHaveAlternatives(in map: NavalGeneratedMap, sea: Set<HexCoordinate>) -> Bool {
        let edges = NavalPorts.coastEdges(in: map.board, islandByHex: map.islandByHex, island: 0)
        let harbors = Set(edges.flatMap { [$0.a, $0.b] }).sorted()
        for harbor in harbors {
            let launch = Set(harbor.touchingTiles).intersection(sea)
            let reached = flood(from: launch.sorted(), within: sea, limit: 6)
            let islands = Set(reached.flatMap { seaHex in
                (0..<6).compactMap { map.islandByHex[seaHex.neighbor($0)] }.filter { $0 != 0 }
            })
            if islands.count < 2 { return false }
        }
        return true
    }

    static func flood(from starts: [HexCoordinate], within allowed: Set<HexCoordinate>,
                      limit: Int = Int.max) -> Set<HexCoordinate> {
        var reached = Set(starts)
        var frontier = starts
        var depth = 0
        while !frontier.isEmpty && depth < limit {
            var next: [HexCoordinate] = []
            for hex in frontier {
                for direction in 0..<6 {
                    let neighbor = hex.neighbor(direction)
                    if allowed.contains(neighbor) && reached.insert(neighbor).inserted { next.append(neighbor) }
                }
            }
            frontier = next
            depth += 1
        }
        return reached
    }
}
