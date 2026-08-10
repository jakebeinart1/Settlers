import CatanEngine

/// Picks where to park the robber and (optionally) who to steal from.
public enum RobberHeuristics {
    /// Chooses the tile that maximizes disruption to the leading opponent
    /// (highest total VP among everyone but `player`), while avoiding tiles
    /// that touch the bot's own settlements/cities whenever an alternative
    /// tile exists. Returns the chosen tile plus whichever player occupying
    /// it is the best victim to name (the leader if they're there, else
    /// whichever occupant holds the most resources, else `nil`).
    ///
    /// This only decides intent - callers (e.g. `Bot.decide`) are
    /// responsible for matching the result against `RulesEngine.legalMoves`,
    /// since a desired victim may not actually be eligible to steal from
    /// (e.g. holds zero resource cards).
    public static func chooseRobberTarget(state: GameState, player: PlayerID) -> (HexCoordinate, PlayerID?) {
        let candidateTiles = state.board.tiles.map(\.coordinate).filter { $0 != state.board.robberTile }
        guard !candidateTiles.isEmpty else { return (state.board.robberTile, nil) }

        let leader = state.players
            .filter { $0.id != player }
            .max { state.victoryPoints(for: $0.id) < state.victoryPoints(for: $1.id) }

        func verticesTouching(_ tile: HexCoordinate) -> [VertexID] {
            state.board.onBoardVertices.filter { $0.touchingTiles.contains(tile) }
        }

        func touchesOwn(_ tile: HexCoordinate) -> Bool {
            guard let me = state.players.first(where: { $0.id == player }) else { return false }
            return verticesTouching(tile).contains { me.settlements.contains($0) || me.cities.contains($0) }
        }

        // Disruption score for `tile`: opponent building weight there,
        // strongly favoring the leader's buildings over other opponents'.
        func disruption(_ tile: HexCoordinate) -> Int {
            var value = 0
            for vertex in verticesTouching(tile) {
                for other in state.players where other.id != player {
                    let weight = (other.id == leader?.id) ? 3 : 1
                    if other.cities.contains(vertex) { value += 2 * weight }
                    else if other.settlements.contains(vertex) { value += 1 * weight }
                }
            }
            return value
        }

        let notOwn = candidateTiles.filter { !touchesOwn($0) }
        let pool = notOwn.isEmpty ? candidateTiles : notOwn

        guard let bestTile = pool.max(by: { disruption($0) < disruption($1) }) else {
            return (candidateTiles[0], nil)
        }

        let occupants = state.players.filter { occupant in
            occupant.id != player && verticesTouching(bestTile).contains { occupant.settlements.contains($0) || occupant.cities.contains($0) }
        }
        let victim = occupants.first(where: { $0.id == leader?.id })
            ?? occupants.max(by: { $0.resources.values.reduce(0, +) < $1.resources.values.reduce(0, +) })

        return (bestTile, victim?.id)
    }
}
