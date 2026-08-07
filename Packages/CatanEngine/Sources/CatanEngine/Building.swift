/// Costs and placement-legality checks for roads, settlements, and cities.
public enum Building {
    public static let roadCost: [Resource: Int] = [.brick: 1, .lumber: 1]
    public static let settlementCost: [Resource: Int] = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1]
    public static let cityCost: [Resource: Int] = [.ore: 3, .grain: 2]
    public static let devCardCost: [Resource: Int] = [.ore: 1, .grain: 1, .wool: 1]

    public static func cost(for kind: BuildingKind) -> [Resource: Int] {
        switch kind {
        case .settlement: return settlementCost
        case .city: return cityCost
        }
    }

    /// Roads must sit on an unoccupied on-board edge and connect to the
    /// player's existing road/settlement/city network.
    public static func canBuildRoad(_ edge: EdgeID, for player: PlayerID, in state: GameState) -> Bool {
        guard state.board.onBoardEdges.contains(edge) else { return false }
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }
        guard !owner.roads.contains(edge) else { return false }

        let (a, b) = state.board.vertices(of: edge)
        let touchesOwnBuilding = owner.settlements.contains(a) || owner.settlements.contains(b)
            || owner.cities.contains(a) || owner.cities.contains(b)
        let touchesOwnRoad = state.board.edgesTouching(a).contains { owner.roads.contains($0) }
            || state.board.edgesTouching(b).contains { owner.roads.contains($0) }
        return touchesOwnBuilding || touchesOwnRoad
    }

    /// Distance rule (no adjacent building) plus - outside setup - must
    /// connect to the player's own road network.
    public static func canBuildSettlement(_ vertex: VertexID, for player: PlayerID, in state: GameState) -> Bool {
        guard state.board.onBoardVertices.contains(vertex) else { return false }
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }

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
        return owner.settlements.contains(vertex)
    }
}
