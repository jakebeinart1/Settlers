public enum BoardGenerator {

    // MARK: Fixed board shape

    /// The 19 board hexes in spiral order: center first, then ring 1 (6
    /// tiles), then ring 2 (12 tiles), each ring walked clockwise starting
    /// from a fixed direction. This ordering is what both the standard fixed
    /// layout and the randomizer's shuffle are defined against.
    static let tileCoordinates: [HexCoordinate] = spiralCoordinates(radius: 2)

    private static func spiralCoordinates(radius: Int) -> [HexCoordinate] {
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

    public static func standard() -> Board {
        var numbers = standardNumberOrder.makeIterator()
        let tiles = zip(tileCoordinates, standardResourceOrder).map { coordinate, kind -> Tile in
            let number = (kind == .desert) ? nil : numbers.next()
            return Tile(coordinate: coordinate, kind: kind, numberToken: number)
        }
        return makeBoard(tiles: tiles)
    }

    // MARK: Randomized layout

    /// Shuffles the 19 resource tiles (incl. desert) and the 18 number
    /// tokens independently using a seeded RNG, re-rolling the shuffle
    /// whenever a 6 or 8 would end up adjacent to another 6 or 8. Ports stay
    /// in their fixed standard positions.
    public static func randomized(seed: UInt64) -> Board {
        var rng = SeededGenerator(seed: seed)
        var kinds: [TileKind]
        var numbers: [Int]
        repeat {
            kinds = standardResourceOrder.shuffled(using: &rng)
            numbers = standardNumberOrder.shuffled(using: &rng)
        } while hasAdjacentSixOrEight(kinds: kinds, numbers: numbers)

        var numberIterator = numbers.makeIterator()
        let tiles = zip(tileCoordinates, kinds).map { coordinate, kind -> Tile in
            let number = (kind == .desert) ? nil : numberIterator.next()
            return Tile(coordinate: coordinate, kind: kind, numberToken: number)
        }
        return makeBoard(tiles: tiles)
    }

    private static func hasAdjacentSixOrEight(kinds: [TileKind], numbers: [Int]) -> Bool {
        var numberIterator = numbers.makeIterator()
        var tokenByCoordinate: [HexCoordinate: Int] = [:]
        for (coordinate, kind) in zip(tileCoordinates, kinds) {
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

    // MARK: Shared assembly

    private static func makeBoard(tiles: [Tile]) -> Board {
        var vertices = Set<VertexID>()
        var edges = Set<EdgeID>()
        for tile in tiles {
            vertices.formUnion(HexGeometry.corners(of: tile.coordinate))
            edges.formUnion(HexGeometry.edges(of: tile.coordinate))
        }
        let robberTile = tiles.first(where: { $0.kind == .desert })?.coordinate ?? tiles[0].coordinate
        return Board(
            tiles: tiles,
            ports: standardPorts,
            onBoardVertices: vertices,
            onBoardEdges: edges,
            robberTile: robberTile
        )
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
