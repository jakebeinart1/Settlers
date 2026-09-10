public enum BoardGenerator {

    // MARK: Fixed board shape

    /// The 19 board hexes in spiral order: center first, then ring 1 (6
    /// tiles), then ring 2 (12 tiles), each ring walked clockwise starting
    /// from a fixed direction. This ordering is what both the standard fixed
    /// layout and the randomizer's shuffle are defined against.
    static let tileCoordinates: [HexCoordinate] = spiralCoordinates(radius: 2)

    static func spiralCoordinates(radius: Int) -> [HexCoordinate] {
        var results = [HexCoordinate(q: 0, r: 0)]
        guard radius > 0 else { return results }
        for ring in 1...radius {
            let start = HexCoordinate.neighborDirections[4]
            var coordinate = HexCoordinate(q: start.0 * ring, r: start.1 * ring)
            for direction in 0..<6 {
                for _ in 0..<ring {
                    results.append(coordinate)
                    coordinate = coordinate.neighbor(direction)
                }
            }
        }
        return results
    }

    // MARK: Standard fixed layout

    /// Standard resource distribution (4 grain, 4 wool, 4 lumber, 3 brick,
    /// 3 ore, 1 desert = 19 tiles), in the same spiral order as
    /// `tileCoordinates`, matching the classic physical Catan board.
    static let standardResourceOrder: [TileKind] = [
        .resource(.grain), .resource(.wool), .resource(.lumber), .resource(.grain),
        .resource(.brick), .resource(.wool), .resource(.lumber), .resource(.ore),
        .resource(.grain), .desert,
        .resource(.brick), .resource(.wool), .resource(.lumber), .resource(.ore),
        .resource(.grain), .resource(.wool), .resource(.brick), .resource(.ore),
        .resource(.lumber),
    ]

    /// Standard number tokens (18, no token for the desert). Dealt in order
    /// onto the non-desert tiles of `tileCoordinates`; this is the classic
    /// arrangement in which no 6 or 8 ever touches another 6 or 8.
    static let standardNumberOrder: [Int] =
        [5, 2, 6, 3, 8, 10, 9, 12, 11, 4, 8, 10, 9, 4, 5, 6, 3, 11]

    /// Standard port layout: 9 ports (4 generic 3:1 + 1 per resource 2:1) at
    /// fixed shoreline edges around the outer ring, matching the classic
    /// board. Alternates resource/generic around the perimeter.
    static let standardPorts: [Port] = [
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: 0, r: 2), HexCoordinate(q: 0, r: 3), HexCoordinate(q: 1, r: 2)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: 0, r: 2), HexCoordinate(q: 1, r: 1), HexCoordinate(q: 1, r: 2)]),
            kind: .resource(.grain)
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: 1, r: 1), HexCoordinate(q: 2, r: 0), HexCoordinate(q: 2, r: 1)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: 2, r: 0), HexCoordinate(q: 2, r: 1), HexCoordinate(q: 3, r: 0)]),
            kind: .generic
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: 2, r: -1), HexCoordinate(q: 2, r: 0), HexCoordinate(q: 3, r: -1)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: 2, r: -1), HexCoordinate(q: 3, r: -2), HexCoordinate(q: 3, r: -1)]),
            kind: .resource(.wool)
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: 2, r: -3), HexCoordinate(q: 2, r: -2), HexCoordinate(q: 3, r: -3)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: 1, r: -2), HexCoordinate(q: 2, r: -3), HexCoordinate(q: 2, r: -2)]),
            kind: .generic
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: 0, r: -2), HexCoordinate(q: 1, r: -3), HexCoordinate(q: 1, r: -2)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: 0, r: -3), HexCoordinate(q: 0, r: -2), HexCoordinate(q: 1, r: -3)]),
            kind: .resource(.lumber)
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: -1, r: -2), HexCoordinate(q: -1, r: -1), HexCoordinate(q: 0, r: -2)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: -2, r: -1), HexCoordinate(q: -1, r: -2), HexCoordinate(q: -1, r: -1)]),
            kind: .generic
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: -3, r: 0), HexCoordinate(q: -3, r: 1), HexCoordinate(q: -2, r: 0)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: -3, r: 1), HexCoordinate(q: -2, r: 0), HexCoordinate(q: -2, r: 1)]),
            kind: .resource(.brick)
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: -3, r: 2), HexCoordinate(q: -2, r: 1), HexCoordinate(q: -2, r: 2)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: -3, r: 2), HexCoordinate(q: -3, r: 3), HexCoordinate(q: -2, r: 2)]),
            kind: .generic
        ),
        Port(
            vertexA: VertexID(touchingTiles: [HexCoordinate(q: -2, r: 2), HexCoordinate(q: -2, r: 3), HexCoordinate(q: -1, r: 2)]),
            vertexB: VertexID(touchingTiles: [HexCoordinate(q: -2, r: 3), HexCoordinate(q: -1, r: 2), HexCoordinate(q: -1, r: 3)]),
            kind: .resource(.ore)
        ),
    ]

    public static func standard() -> Board { standard(BoardShape.classic) }

    /// Deals `shape`'s tiles onto its spiral, in `shape.terrain`'s expanded
    /// order, and resolves its ports.
    public static func standard(_ shape: BoardShape) -> Board {
        precondition(shape.compositionProblem == nil,
                     "cannot deal this board: \(shape.compositionProblem!)")
        let coordinates = spiralCoordinates(radius: shape.radius)
        let kinds = shape.terrain.expanded(tileCount: shape.tileCount)
        var numbers = shape.tokens
            .expanded(count: kinds.filter { $0 != .desert }.count)
            .makeIterator()
        let tiles = zip(coordinates, kinds).map { coordinate, kind -> Tile in
            let number = (kind == .desert) ? nil : numbers.next()
            return Tile(coordinate: coordinate, kind: kind, numberToken: number)
        }
        return makeBoard(tiles: tiles, shape: shape)
    }

    // MARK: Randomized layout

    /// Shuffles the 19 resource tiles (incl. desert) and the 18 number
    /// tokens independently using a seeded RNG, re-rolling the shuffle
    /// whenever a 6 or 8 would end up adjacent to another 6 or 8. Ports stay
    /// in their fixed standard positions.
    public static func randomized(seed: UInt64) -> Board {
        randomized(seed: seed, shape: BoardShape.classic)
    }

    /// Shuffles allowed before `randomized(seed:shape:)` hands off to the
    /// deterministic repair pass.
    ///
    /// Bounded rather than unbounded: classic's bag is known feasible, but
    /// this loop is reachable with an arbitrary `shape` - a token
    /// composition that packs a board with 6s and 8s (as in
    /// `aCompositionExpandsToExactlyTheDeclaredCounts`) can have no
    /// arrangement that satisfies "no 6 or 8 touches another 6 or 8" at all,
    /// and an unbounded retry would hang forever rather than fail.
    /// `repairingAdjacentSixOrEight` is what runs when the bound is hit.
    private static let maxShuffleAttempts = 100

    /// Shuffles `shape`'s expanded terrain and tokens independently using a
    /// seeded RNG, re-rolling whenever a 6 or 8 would end up adjacent to
    /// another 6 or 8. Ports are resolved from `shape.ports`, unshuffled.
    public static func randomized(seed: UInt64, shape: BoardShape) -> Board {
        precondition(shape.compositionProblem == nil,
                     "cannot deal this board: \(shape.compositionProblem!)")
        var rng = SeededGenerator(seed: seed)
        let coordinates = spiralCoordinates(radius: shape.radius)
        let baseKinds = shape.terrain.expanded(tileCount: shape.tileCount)
        let baseNumbers = shape.tokens
            .expanded(count: baseKinds.filter { $0 != .desert }.count)
        var kinds: [TileKind]
        var numbers: [Int]
        // The bound is already present from Task 3 - keep it.
        var attemptsRemaining = maxShuffleAttempts
        // Classic clears this in a handful of shuffles - 4 hot tiles among 19.
        // Expanded has 8 among 36 on a graph with far more adjacencies, where a
        // clean shuffle is rare enough that an unbounded loop can spin, and a
        // thousand-tile board would never clear it. Try, then repair.
        repeat {
            kinds = baseKinds.shuffled(using: &rng)
            numbers = baseNumbers.shuffled(using: &rng)
            attemptsRemaining -= 1
        } while attemptsRemaining > 0
            && hasAdjacentSixOrEight(kinds: kinds, numbers: numbers, coordinates: coordinates)

        numbers = repairingAdjacentSixOrEight(kinds: kinds, numbers: numbers, radius: shape.radius)

        var numberIterator = numbers.makeIterator()
        let tiles = zip(coordinates, kinds).map { coordinate, kind -> Tile in
            let number = (kind == .desert) ? nil : numberIterator.next()
            return Tile(coordinate: coordinate, kind: kind, numberToken: number)
        }
        return makeBoard(tiles: tiles, shape: shape)
    }

    private static func hasAdjacentSixOrEight(
        kinds: [TileKind], numbers: [Int], coordinates: [HexCoordinate]
    ) -> Bool {
        var numberIterator = numbers.makeIterator()
        var tokenByCoordinate: [HexCoordinate: Int] = [:]
        for (coordinate, kind) in zip(coordinates, kinds) {
            if kind != .desert, let token = numberIterator.next() {
                tokenByCoordinate[coordinate] = token
            }
        }
        for (coordinate, token) in tokenByCoordinate where token == 6 || token == 8 {
            for direction in 0..<6 {
                let neighbor = coordinate.neighbor(direction)
                if let neighborToken = tokenByCoordinate[neighbor], neighborToken == 6 || neighborToken == 8 {
                    return true
                }
            }
        }
        return false
    }

    /// Swaps every 6/8 that touches another 6/8 onto a cool tile, walking tiles
    /// in spiral order and taking the first cool partner that does not itself
    /// create an adjacency.
    ///
    /// Best-effort on the no-adjacent-6/8 rule, not a guarantee: some
    /// compositions (every token hot, for instance) make the rule
    /// unsatisfiable at any arrangement, and this pass cannot conjure a
    /// solution that does not exist. What it guarantees absolutely is
    /// completeness - every producing tile keeps exactly one token, none
    /// dropped or duplicated - and determinism - the walk is over an ordered
    /// array, never a `Set` or `Dictionary` iteration, and the partner choice
    /// is "first that works" rather than a random pick, so two calls with the
    /// same input return the same board, in this process and in tomorrow's.
    private static func repairingAdjacentSixOrEight(
        kinds: [TileKind], numbers: [Int], radius: Int
    ) -> [Int] {
        let coordinates = spiralCoordinates(radius: radius)
        var tokenIndexByCoordinate: [HexCoordinate: Int] = [:]
        var nextToken = 0
        for (coordinate, kind) in zip(coordinates, kinds) where kind != .desert {
            tokenIndexByCoordinate[coordinate] = nextToken
            nextToken += 1
        }
        var result = numbers
        func isHot(_ token: Int) -> Bool { token == 6 || token == 8 }
        func touchesHot(_ coordinate: HexCoordinate, ignoring: HexCoordinate?) -> Bool {
            (0..<6).contains { direction in
                let neighbor = coordinate.neighbor(direction)
                guard neighbor != ignoring, let index = tokenIndexByCoordinate[neighbor] else { return false }
                return isHot(result[index])
            }
        }
        for coordinate in coordinates {
            guard let index = tokenIndexByCoordinate[coordinate], isHot(result[index]) else { continue }
            guard touchesHot(coordinate, ignoring: nil) else { continue }
            let partner = coordinates.first { candidate in
                guard let candidateIndex = tokenIndexByCoordinate[candidate],
                      !isHot(result[candidateIndex]) else { return false }
                return !touchesHot(candidate, ignoring: coordinate)
            }
            guard let partner, let partnerIndex = tokenIndexByCoordinate[partner] else { continue }
            result.swapAt(index, partnerIndex)
        }
        return result
    }

    // MARK: Shared assembly

    private static func makeBoard(tiles: [Tile], shape: BoardShape) -> Board {
        var vertices = Set<VertexID>()
        var edges = Set<EdgeID>()
        for tile in tiles {
            vertices.formUnion(HexGeometry.corners(of: tile.coordinate))
            edges.formUnion(HexGeometry.edges(of: tile.coordinate))
        }
        let robberTile = tiles.first(where: { $0.kind == .desert })?.coordinate ?? tiles[0].coordinate
        return Board(
            tiles: tiles,
            ports: resolvePorts(shape.ports, tiles: tiles),
            onBoardVertices: vertices,
            onBoardEdges: edges,
            robberTile: robberTile
        )
    }

    private static func resolvePorts(_ layout: PortLayout, tiles: [Tile]) -> [Port] {
        switch layout {
        case .fixed(let ports):
            return ports
        case .derived(let kinds):
            return derivedPorts(kinds: kinds, tiles: tiles)
        }
    }
}

/// A small deterministic PRNG (xorshift64*) so `randomized(seed:)` is
/// reproducible across runs/platforms, unlike `SystemRandomNumberGenerator`.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed != 0 ? seed : 0x9E3779B97F4A7C15
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
