import CatanEngine

/// The board facts a route is planned against, resolved once per seat per
/// planning pass.
///
/// ## Why this exists separately from the search
/// A route node is deliberately abstract - a victory-point total, a production
/// rate, pieces remaining - so that the search can dedupe states instead of
/// drowning in board permutations. But "buy a settlement" has to be priced
/// against a *real vertex*, or the rate it adds is invented. This type is the
/// bridge: it resolves the actual candidate vertices once, best first, and the
/// k-th settlement on a route is priced at the k-th best candidate.
///
/// That is an approximation - it assumes a seat takes its candidates in value
/// order and that nobody takes them first. The second half is handled
/// elsewhere, by `ContestModel`, which discounts a candidate by how likely an
/// opponent is to reach it first.
///
/// Every field here is derived from public information only.
public struct RouteContext: Sendable {

    /// One place this seat could put a settlement, and what it would cost to
    /// get there.
    public struct SettlementCandidate: Sendable, Equatable {
        public let vertex: VertexID
        /// What a settlement here adds to production.
        public let rateGain: ProductionRate
        /// Roads that must be built first. Zero when the network already
        /// touches the vertex.
        public let roadsRequired: Int
    }

    /// An owned settlement that could be upgraded, and what the upgrade adds.
    public struct CityCandidate: Sendable, Equatable {
        public let vertex: VertexID
        /// A city doubles a settlement's yield, so the gain equals the
        /// vertex's existing production.
        public let rateGain: ProductionRate
    }

    public let seat: PlayerID
    public let rules: Ruleset
    public let victoryPointTarget: Int

    public let startingRate: ProductionRate
    public let startingVictoryPoints: Int
    public let bankRates: [Resource: Int]

    /// Best first. The search consumes these in order.
    public let settlementCandidates: [SettlementCandidate]
    public let cityCandidates: [CityCandidate]

    public let settlementsRemaining: Int
    public let citiesRemaining: Int
    public let roadsRemaining: Int

    public let roadLength: Int
    public let knightsPlayed: Int
    public let holdsLongestRoad: Bool
    public let holdsLargestArmy: Bool

    /// Road length and knight count this seat must *beat* to take each bonus.
    public let longestRoadToBeat: Int
    public let largestArmyToBeat: Int

    /// Chance a bought development card is a victory point, and that it is a
    /// knight, from the composition of what is left in the deck.
    public let devCardVictoryPointChance: Double
    public let devCardKnightChance: Double
    public let devCardsAvailable: Int

    /// Development cards already held but not yet played, by count. Their
    /// faces are private for an opponent, so this is a count only and the
    /// planner prices them at deck expectation.
    public let devCardsHeld: Int

    // MARK: - Construction

    /// Resolves the context for `seat` from public information.
    ///
    /// `ledger` supplies opponents' believed hands; `state` supplies the board,
    /// the buildings, and the bonuses, all of which are public by nature.
    /// Whether candidate sites are discounted by the risk of losing the race
    /// for them.
    ///
    /// Contest pricing costs one breadth-first search per rival, and a clock is
    /// computed once per seat per candidate move - so paying for it on every
    /// evaluation multiplies out to hundreds of searches per decision. It
    /// changes which *route* is worth planning far more than which move is
    /// better right now, so the full plan pays for it and per-move comparisons
    /// do not.
    public enum ContestPricing: Sendable {
        case discountContestedSites
        case ignoreContest
    }

    /// - Parameter rivalDistances: precomputed rival road-distance maps. Pass
    ///   the same maps to every context built during one decision: they are
    ///   what contest pricing is derived from, and a baseline priced with them
    ///   compared against a candidate priced without adds a constant offset to
    ///   every score, which swamps the differences being compared.
    public static func build(
        for seat: PlayerID,
        in state: GameState,
        ledger: PublicLedger,
        contest: ContestPricing = .discountContestedSites,
        rivalDistances: [[VertexID: Int]]? = nil
    ) -> RouteContext {
        let rules = state.rules
        let player = state.players.first { $0.id == seat }
        let occupiedByAnyone = allOccupiedVertices(in: state)
        let reach = roadDistances(for: seat, in: state)
        let tiles = ProductionModel.tileIndex(of: state.board)

        let settlements = settlementCandidates(
            for: seat,
            in: state,
            occupied: occupiedByAnyone,
            distances: reach,
            tiles: tiles,
            rivalDistances: contest == .discountContestedSites
                ? (rivalDistances ?? ContestModel.rivalDistanceMaps(excluding: seat, in: state))
                : []
        )
        let cities = cityCandidates(for: seat, in: state, tiles: tiles)

        let deck = state.devCardDeck
        let deckSize = max(1, deck.count)

        return RouteContext(
            seat: seat,
            rules: rules,
            victoryPointTarget: state.victoryPointTarget,
            startingRate: ProductionModel.rate(for: seat, in: state, tiles: tiles),
            startingVictoryPoints: state.publicVictoryPoints(for: seat),
            bankRates: ProductionModel.bankRates(for: seat, in: state),
            settlementCandidates: settlements,
            cityCandidates: cities,
            settlementsRemaining: max(0, rules.pieceLimit(for: .settlement) - (player?.settlements.count ?? 0)),
            citiesRemaining: max(0, rules.pieceLimit(for: .city) - (player?.cities.count ?? 0)),
            roadsRemaining: max(0, rules.maxRoadsPerPlayer - (player?.roads.count ?? 0)),
            roadLength: player.map { LongestRoad.length(for: $0, in: state) } ?? 0,
            knightsPlayed: player?.playedKnights ?? 0,
            holdsLongestRoad: state.longestRoadPlayer == seat,
            holdsLargestArmy: state.largestArmyPlayer == seat,
            longestRoadToBeat: bestOpposingRoadLength(excluding: seat, in: state),
            largestArmyToBeat: bestOpposingKnightCount(excluding: seat, in: state),
            devCardVictoryPointChance: Double(deck.filter { $0 == .victoryPoint }.count) / Double(deckSize),
            devCardKnightChance: Double(deck.filter { $0 == .knight }.count) / Double(deckSize),
            devCardsAvailable: deck.count,
            devCardsHeld: ledger.belief(of: seat).devCardCount
        )
    }

    // MARK: - Board derivations

    /// Every vertex carrying a building, from any seat. Public by nature.
    static func allOccupiedVertices(in state: GameState) -> Set<VertexID> {
        state.players.reduce(into: Set<VertexID>()) { occupied, player in
            occupied.formUnion(player.settlements)
            occupied.formUnion(player.cities)
        }
    }

    /// How many roads `seat` must build to reach each vertex, by breadth-first
    /// search over edges an opponent's road does not already occupy.
    ///
    /// Sorted enumeration throughout: `Set` iteration order is seeded per
    /// process, and a distance map that differs between launches would make
    /// the whole planner non-reproducible.
    static func roadDistances(for seat: PlayerID, in state: GameState) -> [VertexID: Int] {
        guard let player = state.players.first(where: { $0.id == seat }) else { return [:] }

        let blocked = state.players
            .filter { $0.id != seat }
            .reduce(into: Set<EdgeID>()) { $0.formUnion($1.roads) }

        var frontier: [VertexID] = []
        var distances: [VertexID: Int] = [:]
        for edge in player.roads.sorted() {
            for vertex in [edge.a, edge.b] where distances[vertex] == nil {
                distances[vertex] = 0
                frontier.append(vertex)
            }
        }
        for vertex in player.settlements.union(player.cities).sorted() where distances[vertex] == nil {
            distances[vertex] = 0
            frontier.append(vertex)
        }

        var index = 0
        while index < frontier.count {
            let vertex = frontier[index]
            index += 1
            let distance = distances[vertex] ?? 0
            for edge in state.board.edgesTouching(vertex).sorted() where !blocked.contains(edge) {
                let (a, b) = state.board.vertices(of: edge)
                let next = a == vertex ? b : a
                guard distances[next] == nil else { continue }
                distances[next] = distance + 1
                frontier.append(next)
            }
        }
        return distances
    }

    /// Legal, reachable settlement sites ranked by production gained per road
    /// spent getting there.
    static func settlementCandidates(
        for seat: PlayerID,
        in state: GameState,
        occupied: Set<VertexID>,
        distances: [VertexID: Int],
        tiles: [HexCoordinate: Tile]? = nil,
        rivalDistances: [[VertexID: Int]] = []
    ) -> [SettlementCandidate] {
        let tiles = tiles ?? ProductionModel.tileIndex(of: state.board)
        var candidates: [SettlementCandidate] = []
        for vertex in state.board.onBoardVertices.sorted() {
            guard !occupied.contains(vertex) else { continue }
            // The distance rule: no settlement may touch another building.
            guard !state.board.adjacentVertices(of: vertex).contains(where: { occupied.contains($0) }) else {
                continue
            }
            guard let distance = distances[vertex] else { continue }
            // A site a rival reaches first is not worth what it looks worth.
            let reachableRivals = rivalDistances.compactMap { $0[vertex] }
            let claimChance = ContestModel.rivalClaimChance(
                myDistance: distance, rivalDistances: reachableRivals
            )
            let gain = ContestModel.discounted(
                ProductionModel.rateGain(at: vertex, yield: 1, in: state, tiles: tiles),
                byClaimChance: claimChance
            )
            candidates.append(
                SettlementCandidate(vertex: vertex, rateGain: gain, roadsRequired: distance)
            )
        }
        // Total production first, then fewest roads, then vertex order so the
        // ranking is a pure function of the position.
        return candidates.sorted {
            if $0.rateGain.total != $1.rateGain.total { return $0.rateGain.total > $1.rateGain.total }
            if $0.roadsRequired != $1.roadsRequired { return $0.roadsRequired < $1.roadsRequired }
            return $0.vertex < $1.vertex
        }
    }

    /// Owned settlements ranked by what upgrading them would add.
    static func cityCandidates(
        for seat: PlayerID,
        in state: GameState,
        tiles: [HexCoordinate: Tile]? = nil
    ) -> [CityCandidate] {
        guard let player = state.players.first(where: { $0.id == seat }) else { return [] }
        let tiles = tiles ?? ProductionModel.tileIndex(of: state.board)
        return player.settlements.sorted()
            .map {
                CityCandidate(
                    vertex: $0,
                    rateGain: ProductionModel.rateGain(at: $0, yield: 1, in: state, tiles: tiles)
                )
            }
            .sorted {
                $0.rateGain.total != $1.rateGain.total
                    ? $0.rateGain.total > $1.rateGain.total
                    : $0.vertex < $1.vertex
            }
    }

    static func bestOpposingRoadLength(excluding seat: PlayerID, in state: GameState) -> Int {
        state.players
            .filter { $0.id != seat }
            .map { LongestRoad.length(for: $0, in: state) }
            .max() ?? 0
    }

    static func bestOpposingKnightCount(excluding seat: PlayerID, in state: GameState) -> Int {
        state.players.filter { $0.id != seat }.map(\.playedKnights).max() ?? 0
    }
}
