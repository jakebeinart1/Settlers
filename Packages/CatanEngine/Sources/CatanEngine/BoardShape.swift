/// The geometry and terrain composition of one board, independent of the rules
/// played on it.
///
/// Separate from `Ruleset` because the two change for different reasons: a mode
/// reusing an existing map with different quantities touches only `Ruleset`; a
/// mode adding a map touches only this file.
///
/// ## Declared as a composition, not as a list of tiles
/// Boards of hundreds or a thousand tiles are planned, and one literal entry
/// per tile stops being writable long before that. A shape therefore states how
/// many of each terrain and each token it wants, and the generator expands that
/// onto the spiral. Classic is the exception: its arrangement is the authentic
/// physical board, so it declares a literal order.
public struct BoardShape: Sendable, Equatable {
    /// Rings of hexes around the centre. Radius 2 is the 19-tile classic board.
    public let radius: Int
    public let terrain: TerrainComposition
    public let tokens: TokenComposition
    public let ports: PortLayout

    public init(radius: Int, terrain: TerrainComposition,
                tokens: TokenComposition, ports: PortLayout) {
        self.radius = radius
        self.terrain = terrain
        self.tokens = tokens
        self.ports = ports
    }

    /// Tiles a hex board of `radius` holds: 3r^2 + 3r + 1.
    public static func tileCount(radius: Int) -> Int {
        3 * radius * radius + 3 * radius + 1
    }

    public var tileCount: Int { Self.tileCount(radius: radius) }

    /// Why this shape cannot be dealt, or `nil` if it can.
    ///
    /// Checked rather than trusted: a composition that does not fill the board
    /// would otherwise deal tiles with holes, and a token count that does not
    /// match the non-desert tiles would leave hexes that never produce.
    public var compositionProblem: String? {
        let kinds = terrain.expanded(tileCount: tileCount)
        guard kinds.count == tileCount else {
            return "terrain declares \(kinds.count) tiles for a \(tileCount)-tile board"
        }
        let producing = kinds.filter { $0 != .desert }.count
        let tokenTotal = tokens.expanded(count: producing).count
        guard tokenTotal == producing else {
            return "tokens declare \(tokenTotal) for \(producing) producing tiles"
        }
        return nil
    }
}

public extension BoardShape {
    /// The 19-tile board every game of Catan opens on. Literal orders, because
    /// this arrangement IS the physical board.
    static let classic = BoardShape(
        radius: 2,
        terrain: .literalOrder(BoardGenerator.standardResourceOrder),
        tokens: .literalOrder(BoardGenerator.standardNumberOrder),
        ports: .fixed(BoardGenerator.standardPorts)
    )
}

/// How a shape's terrain is specified.
public enum TerrainComposition: Sendable, Equatable {
    /// Classic's authentic arrangement, in spiral order. Not derivable from a
    /// rule, so it is written down.
    case literalOrder([TileKind])
    /// How many tiles of each kind. Expanded onto the spiral by interleaving,
    /// so a fixed board is playable rather than five solid wedges of one
    /// terrain. Deterministic: a fixed walk over a sorted array, no RNG.
    case counts([TileKind: Int])

    /// The terrain of every tile, in spiral order.
    ///
    /// `tileCount` is the board this composition is being expanded *for*; both
    /// current cases declare their own total instead of stretching to fill it,
    /// and `BoardShape.compositionProblem` is what compares the two and refuses
    /// a mismatch.
    func expanded(tileCount: Int) -> [TileKind] {
        switch self {
        case .literalOrder(let kinds):
            return kinds
        case .counts(let counts):
            let order = counts.keys.sorted { terrainSortKey($0) < terrainSortKey($1) }
            return interleaved(order.map { (element: $0, count: counts[$0]!) })
        }
    }
}

/// How a shape's number tokens are specified.
public enum TokenComposition: Sendable, Equatable {
    case literalOrder([Int])
    /// How many of each pip value.
    case counts([Int: Int])

    /// The token for each producing tile, in the order they are dealt.
    func expanded(count: Int) -> [Int] {
        switch self {
        case .literalOrder(let tokens):
            return tokens
        case .counts(let counts):
            return interleaved(counts.keys.sorted().map { (element: $0, count: counts[$0]!) })
        }
    }
}

/// How a shape's ports are placed.
///
/// Classic's nine are `.fixed`: they reproduce the physical board and are not
/// derivable. Anything larger is `.derived` - hand-authoring vertex triples for
/// a 42-edge coastline is error-prone, and a walk generalizes to radii nobody
/// has drawn.
public enum PortLayout: Sendable, Equatable {
    case fixed([Port])
    /// One port per entry, spread evenly around the coastline in this order.
    case derived(kinds: [PortKind])
}

// MARK: Deterministic expansion

/// A stable ordering for terrain kinds.
///
/// `TileKind` is deliberately not `Comparable` - the rules have no notion of one
/// terrain preceding another - but a composition still has to be walked in a
/// fixed order: `Dictionary` iteration order is seeded per process in Swift, so
/// an expansion that let it through would deal a different board for the same
/// seed on every launch. The key is derived from `Resource`'s string raw value,
/// which is stable across processes and platforms.
private func terrainSortKey(_ kind: TileKind) -> String {
    switch kind {
    case .desert: return "desert"
    case .resource(let resource): return "resource.\(resource.rawValue)"
    }
}

/// Spreads counted groups evenly through one array, in a fixed order.
///
/// Concatenating the groups would deal five solid wedges of one terrain and a
/// board nobody wants to play. So each of a group's `n` items claims the
/// fraction `(2j + 1) / 2n` of the board - the midpoint of its share - and the
/// items are laid down in order of those fractions. Three grain and two brick
/// therefore land as grain, brick, grain, brick, grain rather than as two runs.
///
/// Deterministic by construction: `groups` arrives already sorted, the
/// fractions are compared by integer cross-multiplication rather than by
/// floating point, and equal fractions are broken by the group's position, so
/// the total order does not depend on `sort` being stable (Swift's is not).
private func interleaved<Element>(_ groups: [(element: Element, count: Int)]) -> [Element] {
    var slots: [(numerator: Int, denominator: Int, group: Int)] = []
    for (group, entry) in groups.enumerated() where entry.count > 0 {
        for item in 0..<entry.count {
            slots.append((numerator: 2 * item + 1, denominator: 2 * entry.count, group: group))
        }
    }
    slots.sort { lhs, rhs in
        let left = lhs.numerator * rhs.denominator
        let right = rhs.numerator * lhs.denominator
        return left == right ? lhs.group < rhs.group : left < right
    }
    return slots.map { groups[$0.group].element }
}

// MARK: Derived ports

extension BoardGenerator {
    /// Places `kinds.count` ports evenly around the coastline.
    ///
    /// A coastal edge is an edge of an on-board tile whose neighbour in that
    /// direction is off the board. Walking tiles in spiral order and directions
    /// in index order visits the outer ring the way the ring is wound, so
    /// consecutive coastal edges are physically adjacent and an even stride
    /// spreads ports around the shore rather than clumping them.
    ///
    /// Deterministic by construction: no `Set` is iterated and the stride is
    /// integer arithmetic. No RNG - ports stay put while terrain and tokens
    /// shuffle, exactly as on the classic board.
    static func derivedPorts(kinds: [PortKind], tiles: [Tile]) -> [Port] {
        guard !kinds.isEmpty else { return [] }
        let onBoard = Set(tiles.map(\.coordinate))
        var coastal: [EdgeID] = []
        for tile in tiles {
            let edges = HexGeometry.edges(of: tile.coordinate)
            for direction in 0..<6 where !onBoard.contains(tile.coordinate.neighbor(direction)) {
                // `edges(of:)` indexes edge `i` as the one shared with the
                // neighbour in direction `i`.
                coastal.append(edges[direction])
            }
        }
        precondition(coastal.count >= kinds.count,
                     "coastline holds \(coastal.count) edges, cannot place \(kinds.count) ports")
        let stride = coastal.count / kinds.count
        return kinds.enumerated().map { offset, kind in
            let edge = coastal[offset * stride]
            return Port(vertexA: edge.a, vertexB: edge.b, kind: kind)
        }
    }
}
