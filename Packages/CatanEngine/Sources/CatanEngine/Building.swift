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
    // so a player can hold at most as many settlements and cities
    // simultaneously as this mode's ruleset allows.
    //
    // The actual numbers live in `Ruleset` (`state.rules.maxRoadsPerPlayer`,
    // `state.rules.pieceLimit(for:)`) rather than here, so a second mode with
    // different supplies is a `Ruleset` entry rather than a change to these
    // guards.

    public static func cost(for kind: BuildingKind) -> [Resource: Int] {
        switch kind {
        case .settlement: return settlementCost
        case .city: return cityCost
        }
    }

    /// Roads must sit on an unoccupied on-board edge and connect to the
    /// player's existing road/settlement/city network.
    ///
    /// Naval v6 may extend through a rival's town to claim the free edges beyond
    /// it. Other matches stop at rival towns. This is construction connectivity;
    /// rival towns still interrupt Longest Road in every mode.
    public static func canBuildRoad(_ edge: EdgeID, for player: PlayerID, in state: GameState) -> Bool {
        guard state.board.onBoardEdges.contains(edge) else { return false }
        if state.naval != nil && !Naval.roadIsKnownLand(edge, in: state) { return false }
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }
        guard owner.roads.count < state.rules.maxRoadsPerPlayer else { return false }
        // Asked directly of each seat's own `Set` rather than by building one
        // combined `Set` of every road and every opponent building: this runs
        // once per on-board edge inside `RulesEngine.legalMoves`, so the two
        // throwaway sets were allocated a few hundred times per decision and
        // were a quarter of the bots' time on the 61-tile board.
        guard !state.players.contains(where: { $0.roads.contains(edge) }) else { return false }

        let (a, b) = state.board.vertices(of: edge)
        let touchesOwnBuilding = owner.settlements.contains(a) || owner.settlements.contains(b)
            || owner.cities.contains(a) || owner.cities.contains(b)

        func connectsThroughOwnRoad(at vertex: VertexID) -> Bool {
            guard roadCanExtendThrough(vertex, for: player, in: state) else { return false }
            return state.board.edgesTouching(vertex).contains { owner.roads.contains($0) }
        }
        let touchesOwnRoad = connectsThroughOwnRoad(at: a) || connectsThroughOwnRoad(at: b)

        return touchesOwnBuilding || touchesOwnRoad
    }

    /// Whether a town stops construction along an already connected road.
    /// This does not supply a road connection or authorize an occupied/fogged
    /// edge. Expansion planning shares it so both Naval tiers can see the same
    /// routes players can build. Longest Road uses its separate scoring rule.
    public static func roadCanExtendThrough(_ vertex: VertexID, for player: PlayerID, in state: GameState) -> Bool {
        if state.mode == .naval, let version = state.naval?.rulesVersion,
           version >= Naval.roadContinuationRulesVersion { return true }
        return !state.players.contains {
            $0.id != player && ($0.settlements.contains(vertex) || $0.cities.contains(vertex))
        }
    }

    /// Distance rule (no adjacent building) plus - outside setup - must
    /// connect to the player's own road network.
    public static func canBuildSettlement(_ vertex: VertexID, for player: PlayerID, in state: GameState) -> Bool {
        guard state.board.onBoardVertices.contains(vertex) else { return false }
        if state.naval != nil && !Naval.settlementSiteIsAvailable(vertex, by: player, in: state) { return false }
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }
        guard owner.settlements.count < state.rules.pieceLimit(for: .settlement) else { return false }

        // Asked seat by seat rather than through one combined `Set`, for the
        // reason spelled out in `canBuildRoad`: `legalMoves` calls this once
        // per on-board vertex, and the set was rebuilt every time.
        func anyoneBuilds(at candidate: VertexID) -> Bool {
            state.players.contains { $0.settlements.contains(candidate) || $0.cities.contains(candidate) }
        }
        guard !anyoneBuilds(at: vertex) else { return false }
        let adjacentOccupied = state.board.adjacentVertices(of: vertex).contains { anyoneBuilds(at: $0) }
        guard !adjacentOccupied else { return false }

        switch state.phase {
        case .setupForward, .setupBackward:
            return true
        default:
            return state.board.edgesTouching(vertex).contains { owner.roads.contains($0) }
                || Naval.canFoundColony(at: vertex, by: player, in: state)
        }
    }

    /// Cities may only be built on a vertex already holding that player's
    /// own settlement.
    public static func canBuildCity(_ vertex: VertexID, for player: PlayerID, in state: GameState) -> Bool {
        guard let owner = state.players.first(where: { $0.id == player }) else { return false }
        guard owner.cities.count < state.rules.pieceLimit(for: .city) else { return false }
        return owner.settlements.contains(vertex)
    }
}
