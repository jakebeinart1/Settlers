import CatanEngine

/// Expected cards per turn, by resource, for one seat.
///
/// The unit throughout the planner is *this seat's turns*, not table turns: a
/// number token's pip count divided by 36 is the chance it comes up on one
/// roll, and a seat rolls once per own turn. Every cost in the route search is
/// denominated the same way, so the clocks of two seats are directly
/// comparable even at tables of different sizes.
public struct ProductionRate: Sendable, Equatable {
    /// One slot per resource, in `Resource.allCases` order.
    ///
    /// ## Why an array and not `[Resource: Double]`
    /// It was a dictionary, and that made the whole planner non-reproducible.
    /// `total` summed `values`, whose order a `Dictionary` seeds per process
    /// and varies with insertion history - and floating-point addition is not
    /// associative, so two rates built from the same tiles in a different
    /// order produced totals differing in the last bits. Those totals order
    /// the candidate list, so a tie broke differently and the game diverged.
    /// This is the fifth time that exact defect has been found in this
    /// repository; storing the rate positionally is what stops there being a
    /// sixth in this file.
    private var slots: [Double]

    public init() {
        slots = Array(repeating: 0, count: Resource.allCases.count)
    }

    public init(perTurn: [Resource: Double]) {
        self.init()
        for resource in Resource.allCases {
            slots[ProductionRate.index(of: resource)] = perTurn[resource] ?? 0
        }
    }

    static func index(of resource: Resource) -> Int {
        Resource.allCases.firstIndex(of: resource) ?? 0
    }

    public subscript(resource: Resource) -> Double {
        get { slots[ProductionRate.index(of: resource)] }
        set { slots[ProductionRate.index(of: resource)] = newValue }
    }

    /// Total expected cards per turn. Summed in slot order, which is fixed.
    public var total: Double { slots.reduce(0, +) }

    /// This rate with `amount` added to `resource`.
    public func adding(_ amount: Double, of resource: Resource) -> ProductionRate {
        var copy = self
        copy[resource] += amount
        return copy
    }

    /// Element-wise sum.
    public func adding(_ other: ProductionRate) -> ProductionRate {
        var copy = self
        for index in copy.slots.indices { copy.slots[index] += other.slots[index] }
        return copy
    }

    /// Every slot multiplied by `factor`.
    public func scaled(by factor: Double) -> ProductionRate {
        var copy = self
        for index in copy.slots.indices { copy.slots[index] *= factor }
        return copy
    }

    /// The slots, for hashing. Fixed length and fixed order.
    var components: [Double] { slots }
}

/// Everything about a seat's economy that is derivable from the board and the
/// buildings on it - all of it public information.
public enum ProductionModel {

    /// Chance that a given roll comes up, per roll of two dice.
    static func probability(ofToken token: Int) -> Double {
        Double(DiceOdds.pips(for: token)) / 36.0
    }

    /// Tiles by coordinate.
    ///
    /// Built once per planning pass and passed down. It used to be rebuilt
    /// inside `rateGain`, which is called once per candidate vertex - so a
    /// single context build constructed this dictionary fifty-four times on a
    /// Classic board and ninety-one times on an Expanded one, and a context is
    /// built once per seat per candidate move.
    public static func tileIndex(of board: Board) -> [HexCoordinate: Tile] {
        Dictionary(uniqueKeysWithValues: board.tiles.map { ($0.coordinate, $0) })
    }

    /// `seat`'s expected production, counting a settlement once and a city
    /// twice, and counting nothing under the robber.
    public static func rate(
        for seat: PlayerID,
        in state: GameState,
        tiles: [HexCoordinate: Tile]? = nil
    ) -> ProductionRate {
        guard let player = state.players.first(where: { $0.id == seat }) else { return ProductionRate() }
        var rate = ProductionRate()
        let tiles = tiles ?? tileIndex(of: state.board)

        for (vertex, yield) in buildings(of: player) {
            for coordinate in state.board.neighborTiles(of: vertex) where coordinate != state.board.robberTile {
                guard let tile = tiles[coordinate],
                      case .resource(let resource) = tile.kind,
                      let token = tile.numberToken else { continue }
                rate[resource] += Double(yield) * probability(ofToken: token)
            }
        }
        return rate
    }

    /// What one more building at `vertex` would add to `seat`'s rate.
    ///
    /// Used as a route edge's yield, which is what lets the search discover
    /// that an early city compounds: the edge that buys it also raises the
    /// rate every later edge is priced against.
    public static func rateGain(
        at vertex: VertexID,
        yield: Int,
        in state: GameState,
        tiles: [HexCoordinate: Tile]? = nil
    ) -> ProductionRate {
        var gain = ProductionRate()
        let tiles = tiles ?? tileIndex(of: state.board)
        for coordinate in state.board.neighborTiles(of: vertex) where coordinate != state.board.robberTile {
            guard let tile = tiles[coordinate],
                  case .resource(let resource) = tile.kind,
                  let token = tile.numberToken else { continue }
            gain[resource] += Double(yield) * probability(ofToken: token)
        }
        return gain
    }

    /// How many cards `seat` must give the bank for one of `resource`: 2 with
    /// the matching resource port, 3 with a generic one, 4 otherwise.
    ///
    /// Ports enter the route search through this number rather than through a
    /// hand-tuned placement bonus, so their value is whatever they actually
    /// save on the route being planned - a 2:1 ore port is worth a great deal
    /// on a city route and almost nothing on a road route.
    public static func bankRate(of resource: Resource, for seat: PlayerID, in state: GameState) -> Int {
        guard let player = state.players.first(where: { $0.id == seat }) else { return 4 }
        let occupied = player.settlements.union(player.cities)
        var best = 4
        for port in state.board.ports where occupied.contains(port.vertexA) || occupied.contains(port.vertexB) {
            switch port.kind {
            case .resource(let kind) where kind == resource: best = min(best, 2)
            case .generic: best = min(best, 3)
            case .resource: break
            }
        }
        return best
    }

    /// Every bank rate for `seat` in one pass, so the clock model does not
    /// re-walk the port list once per resource per route edge.
    public static func bankRates(for seat: PlayerID, in state: GameState) -> [Resource: Int] {
        var rates: [Resource: Int] = [:]
        for resource in Resource.allCases {
            rates[resource] = bankRate(of: resource, for: seat, in: state)
        }
        return rates
    }

    /// `(vertex, yield)` for each building a player owns.
    private static func buildings(of player: Player) -> [(VertexID, Int)] {
        player.settlements.sorted().map { ($0, 1) } + player.cities.sorted().map { ($0, 2) }
    }
}
