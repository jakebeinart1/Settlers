/// Costs and placement-legality checks for roads, settlements, and cities.
public enum Building {
    public static let roadCost: [Resource: Int] = [.brick: 1, .lumber: 1]
    public static let settlementCost: [Resource: Int] = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1]
    public static let cityCost: [Resource: Int] = [.ore: 3, .grain: 2]
    public static let devCardCost: [Resource: Int] = [.ore: 1, .grain: 1, .wool: 1]

    // MARK: - Piece supply
    //
    // Each player owns a fixed set of physical pieces in the boxed game, and
    // running out is a real strategic constraint - it is what stops a runaway
    // player from simply building forever, and it forces the settlement→city
    // upgrade rather than endless sprawl.
    //
    // No supply check existed at all before this: a 30-game sweep found 17
    // games exceeding these limits, peaking at 23 roads and 9 settlements.
    // Half of all games were therefore running a ruleset that was not Catan,
    // which also means every tuned constant in `CatanAI` was fitted against
    // the wrong game.
    //
    // Cities are *upgrades*: building one returns a settlement to the supply,
    // so a player can hold at most 5 settlements and 4 cities simultaneously.
    public static let maxRoadsPerPlayer = 15
    public static let maxSettlementsPerPlayer = 5
    public static let maxCitiesPerPlayer = 4

    public static func cost(for kind: BuildingKind) -> [Resource: Int] {
        switch kind {
        case .settlement: return settlementCost
        case .city: return cityCost
        }
    }

    /// Roads must sit on an unoccupied on-board edge and connect to the
    /// player's existing road/settlement/city network.
    ///
    /// An opponent's settlement/city at a vertex cuts the road network there
    /// (matches real Catan rules): reaching a vertex through your own road
    /// only counts as connectivity if that vertex isn't occupied by another
    /// player's building - otherwise you could keep extending a road straight
    /// through/past an opponent's settlement. Ending a road *at* that vertex
    /// is still fine (that's a distance-rule/city question elsewhere, not a
    /// road-building one); what's blocked is treating it as a through-point
    /// for a *further* road on the other side.
    public static func canBuildRoad(_ edge: EdgeID, for player: PlayerID, in state: GameState) -> Bool {
        guard state.board.onBoardEdges.contains(edge) else { return false }
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }
        guard owner.roads.count < maxRoadsPerPlayer else { return false }
        let allRoads = Set(state.players.flatMap { $0.roads })
        guard !allRoads.contains(edge) else { return false }

        let opponentBuildings = state.players
            .filter { $0.id != player }
            .flatMap { $0.settlements.union($0.cities) }
        let opponentOccupied = Set(opponentBuildings)

        let (a, b) = state.board.vertices(of: edge)
        let touchesOwnBuilding = owner.settlements.contains(a) || owner.settlements.contains(b)
            || owner.cities.contains(a) || owner.cities.contains(b)

        func connectsThroughOwnRoad(at vertex: VertexID) -> Bool {
            guard !opponentOccupied.contains(vertex) else { return false }
            return state.board.edgesTouching(vertex).contains { owner.roads.contains($0) }
        }
        let touchesOwnRoad = connectsThroughOwnRoad(at: a) || connectsThroughOwnRoad(at: b)

        return touchesOwnBuilding || touchesOwnRoad
    }

    /// Distance rule (no adjacent building) plus - outside setup - must
    /// connect to the player's own road network.
    public static func canBuildSettlement(_ vertex: VertexID, for player: PlayerID, in state: GameState) -> Bool {
        guard state.board.onBoardVertices.contains(vertex) else { return false }
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }
        guard owner.settlements.count < maxSettlementsPerPlayer else { return false }

        let occupied = Set(state.players.flatMap { $0.settlements.union($0.cities) })
        guard !occupied.contains(vertex) else { return false }
        let adjacentOccupied = state.board.adjacentVertices(of: vertex).contains { occupied.contains($0) }
        guard !adjacentOccupied else { return false }

        switch state.phase {
        case .setupForward, .setupBackward:
            return true
        default:
            return state.board.edgesTouching(vertex).contains { owner.roads.contains($0) }
        }
    }

    /// Cities may only be built on a vertex already holding that player's
    /// own settlement.
    public static func canBuildCity(_ vertex: VertexID, for player: PlayerID, in state: GameState) -> Bool {
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }
        guard owner.cities.count < maxCitiesPerPlayer else { return false }
        return owner.settlements.contains(vertex)
    }
}
