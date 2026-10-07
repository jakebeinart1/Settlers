import Foundation
import Testing
@testable import CatanEngine

struct NavalMapTests {
    @Test(arguments: NavalMapFamily.allCases)
    func seededWorldStudy(family: NavalMapFamily) throws {
        let count = Int(ProcessInfo.processInfo.environment["NAVAL_MAP_STUDY"] ?? "25") ?? 25
        var geometries = Set<String>()
        var fallbacks = 0
        var attempts = 0
        var minimumBestLanding = Int.max
        var routes: [Int: Int] = [:]
        var productionBySize: [Int: [Int]] = [:]
        var landingBySize: [Int: [Int]] = [:]
        for seed in 0..<count {
            let state = Naval.newGame(seed: UInt64(seed), options: NavalOptions(mapFamily: family))
            #expect(Naval.validationProblem(in: state) == nil)
            let naval = try #require(state.naval)
            geometries.insert(state.board.tiles.filter { $0.kind.isLand }.map { "\($0.coordinate.q),\($0.coordinate.r)" }.joined(separator: ";"))
            fallbacks += naval.usedFallback ? 1 : 0
            attempts += naval.generationAttempts
            for island in 1...4 {
                let land = state.board.tiles.filter { naval.islandByHex[$0.coordinate] == island }
                let best = bestLanding(island: island, state: state)
                productionBySize[land.count, default: []].append(land.reduce(0) { $0 + pips($1.numberToken) })
                landingBySize[land.count, default: []].append(best)
                minimumBestLanding = min(minimumBestLanding, best)
            }
            for distance in routeDistances(state: state) { routes[distance, default: 0] += 1 }
            if seed < 5 { try export(state: state, seed: seed, family: family) }
        }
        #expect(geometries.count > min(count - 1, count * 3 / 4))
        #expect(fallbacks == 0)
        #expect(minimumBestLanding >= 5)
        let economy = productionBySize.keys.sorted().map { size in
            "size\(size):production=\(productionBySize[size]!.min()!)...\(productionBySize[size]!.max()!),landing=\(landingBySize[size]!.min()!)...\(landingBySize[size]!.max()!)"
        }
        print("NAVAL MAP ECONOMY family=\(family.rawValue) \(economy)")
        print("NAVAL MAP STUDY family=\(family.rawValue) seeds=\(count) geometries=\(geometries.count) fallbacks=\(fallbacks) "
              + "meanAttempts=\(Double(attempts) / Double(count)) minimumBestLandingPips=\(minimumBestLanding) routeSteps=\(routes.sorted { $0.key < $1.key })")
    }

    @Test(arguments: NavalMapFamily.allCases)
    func togglesPreserveWorldAndRandomStream(family: NavalMapFamily) {
        let count = Int(ProcessInfo.processInfo.environment["NAVAL_OPTION_STUDY"] ?? "25") ?? 25
        for seed in 0..<count {
            let baseline = Naval.newGame(seed: UInt64(seed), options: NavalOptions(mapFamily: family))
            for fog in [true, false] {
                for choice in [true, false] {
                    let other = Naval.newGame(seed: UInt64(seed), options: NavalOptions(fogEnabled: fog, resourceChoiceEnabled: choice, mapFamily: family))
                    #expect(other.rng == baseline.rng)
                    #expect(other.devCardDeck == baseline.devCardDeck)
                    #expect(other.naval?.islandByHex == baseline.naval?.islandByHex)
                    #expect(other.board.onBoardEdges == baseline.board.onBoardEdges)
                    #expect(other.board.ports == baseline.board.ports)
                    #expect(other.board.tiles.map(\.numberToken) == baseline.board.tiles.map(\.numberToken))
                    for (a, b) in zip(baseline.board.tiles, other.board.tiles) where a.kind != .resourceChoice { #expect(a.kind == b.kind) }
                }
            }
        }
    }

    @Test(arguments: NavalMapFamily.allCases)
    func sameFamilyFallbackIsValidForEitherProductionOption(family: NavalMapFamily) {
        for rotation in 0..<6 {
            for mirror in [true, false] {
                for choice in [true, false] {
                    var rng = RandomSource(seed: UInt64(rotation))
                    let map = NavalMapGenerator.fallback(family: family, options: NavalOptions(resourceChoiceEnabled: choice),
                                                         using: &rng, rotations: rotation, reflected: mirror)
                    #expect(map.family == family)
                    #expect(map.usedFallback)
                    #expect(NavalMapValidation.problem(in: map) == nil)
                }
            }
        }
    }

    private func bestLanding(island: Int, state: GameState) -> Int {
        let land = state.board.tiles.filter { state.naval?.islandByHex[$0.coordinate] == island }
        let coast = Set(land.flatMap { HexGeometry.corners(of: $0.coordinate) }).filter { Naval.isCoastal($0, in: state) }
        return coast.map { vertex in land.filter { vertex.touchingTiles.contains($0.coordinate) }.reduce(0) { $0 + pips($1.numberToken) } }.max() ?? 0
    }

    private func pips(_ number: Int?) -> Int { number.map { 6 - abs(7 - $0) } ?? 0 }

    private func routeDistances(state: GameState) -> [Int] {
        let sea = Set(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        let home = Set(state.board.tiles.filter { state.naval?.islandByHex[$0.coordinate] == 0 }.flatMap { HexGeometry.corners(of: $0.coordinate) }).filter { Naval.isCoastal($0, in: state) }.sorted()
        var result: [Int] = []
        for harbor in home {
            var distances = Dictionary(uniqueKeysWithValues: harbor.touchingTiles.filter(sea.contains).map { ($0, 0) })
            var queue = distances.keys.sorted()
            var index = 0
            while index < queue.count {
                let hex = queue[index]
                index += 1
                for direction in 0..<6 {
                    let next = hex.neighbor(direction)
                    if sea.contains(next) && distances[next] == nil { distances[next] = distances[hex]! + 1; queue.append(next) }
                }
            }
            for island in 1...4 {
                let coasts = sea.filter { hex in (0..<6).contains { state.naval?.islandByHex[hex.neighbor($0)] == island } }
                result.append(coasts.compactMap { distances[$0] }.min()!)
            }
        }
        return result
    }

    private func export(state: GameState, seed: Int, family: NavalMapFamily) throws {
        guard let directory = ProcessInfo.processInfo.environment["NAVAL_MAP_REPORT_DIR"] else { return }
        let tiles: [[String: Any]] = state.board.tiles.map { tile in
            ["q": tile.coordinate.q, "r": tile.coordinate.r, "kind": String(describing: tile.kind),
             "number": tile.numberToken as Any? ?? NSNull(), "island": state.naval?.islandByHex[tile.coordinate] as Any? ?? NSNull()]
        }
        let object: [String: Any] = ["seed": seed, "family": family.rawValue, "mapVersion": Naval.currentMapVersion,
                                     "board": try JSONSerialization.jsonObject(with: JSONEncoder().encode(state.board)), "tiles": tiles]
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(family.rawValue)-\(seed).json")
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
    }
}
