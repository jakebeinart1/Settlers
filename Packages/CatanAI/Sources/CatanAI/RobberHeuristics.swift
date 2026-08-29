import CatanEngine

/// Picks where to park the robber and (optionally) who to steal from.
public enum RobberHeuristics {
    /// Chooses the tile that maximizes disruption to opponents, weighted by
    /// each occupant's relative threat (see `ThreatAssessment`) and scaled
    /// by how aggressively this bot leans into robber play, while avoiding
    /// tiles that touch the bot's own settlements/cities whenever an
    /// alternative tile exists. Returns the chosen tile plus whichever
    /// occupant is the best victim to name (the highest-threat occupant, or
    /// whoever holds the most resources if threat is a tie).
    ///
    /// This only decides intent - callers (e.g. `Bot.decide`) are
    /// responsible for matching the result against `RulesEngine.legalMoves`,
    /// since a desired victim may not actually be eligible to steal from
    /// (e.g. holds zero resource cards).
    public static func chooseRobberTarget(state: GameState, player: PlayerID, personality: BotPersonality) -> (HexCoordinate, PlayerID?) {
        let candidateTiles = state.board.tiles.map(\.coordinate).filter { $0 != state.board.robberTile }
        guard !candidateTiles.isEmpty else { return (state.board.robberTile, nil) }

        func verticesTouching(_ tile: HexCoordinate) -> [VertexID] {
            state.board.onBoardVertices.filter { $0.touchingTiles.contains(tile) }
        }

        func touchesOwn(_ tile: HexCoordinate) -> Bool {
            guard let me = state.players.first(where: { $0.id == player }) else { return false }
            return verticesTouching(tile).contains { me.settlements.contains($0) || me.cities.contains($0) }
        }

        // Disruption score for `tile`: opponent building weight there,
        // scaled by each occupant's threat relative to the average
        // opponent and by how aggressively this bot leans into robber play.
        func disruption(_ tile: HexCoordinate) -> Double {
            var value = 0.0
            for vertex in verticesTouching(tile) {
                for other in state.players where other.id != player {
                    let weight = 1.0 + ThreatAssessment.relativeWeight(for: other.id, excluding: player, in: state) * personality.aggressiveness * 2.0
                    if other.cities.contains(vertex) {
                        value += 2.0 * weight
                    } else if other.settlements.contains(vertex) {
                        value += 1.0 * weight
                    }
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
        let threatRanking = ThreatAssessment.scores(excluding: player, in: state)
        let victim = threatRanking
            .first { ranked in occupants.contains { $0.id == ranked.player } }
            .map { $0.player }
            ?? occupants.max(by: { $0.resources.values.reduce(0, +) < $1.resources.values.reduce(0, +) })?.id

        return (bestTile, victim)
    }
}
