import Foundation

extension Naval {
    /// Fog uses the full public envelope so camera fit never exposes a hidden coastline.
    public static func visibleBoard(in state: GameState) -> Board {
        guard let naval = state.naval else { return state.board }
        let tiles = state.board.tiles.map { tile in
            naval.revealed.contains(tile.coordinate)
                ? tile : Tile(coordinate: tile.coordinate, kind: .fog, numberToken: nil)
        }
        // Harbors on charted land are public even while nearby sea stays fogged.
        // Only the shared edge's known land matters: consulting concealed sea
        // here would let private terrain change an otherwise identical observation.
        let ports = state.board.ports.filter { port in
            Set(port.vertexA.touchingTiles).intersection(port.vertexB.touchingTiles)
                .contains { isKnownLand($0, in: state) }
        }
        let robber = naval.revealed.contains(state.board.robberTile) ? state.board.robberTile : HexCoordinate(q: 0, r: 0)
        return landBoard(tiles: tiles, ports: ports, robber: robber)
    }

    /// Replay only the former harbor projection when validating a stored queued
    /// reply. Its sampled decision survives the update; undiscovered terrain and
    /// every other public/private observation field must still match exactly.
    static func legacyHarborBoard(in state: GameState) -> Board {
        let board = visibleBoard(in: state)
        let ports = state.board.ports.filter { port in
            Set(port.vertexA.touchingTiles).union(port.vertexB.touchingTiles).allSatisfy { coordinate in
                !state.board.tiles.contains(where: { $0.coordinate == coordinate }) || isRevealed(coordinate, in: state)
            }
        }
        return landBoard(tiles: board.tiles, ports: ports, robber: board.robberTile)
    }

    /// Naval policies receive only public world/hand information and their own private cards.
    /// Older modes retain their deliberately existing observation behavior.
    public static func observationState(_ state: GameState, for observer: PlayerID) -> GameState {
        guard state.naval != nil else { return state }
        var result = state
        result.board = visibleBoard(in: state)
        result.rng = RandomSource(seed: 0)
        result.devCardDeck = []
        result.armyDeck = []
        result.armyHands = [:]
        result.garrisons = [:]
        result.devCardsBoughtThisTurn = state.devCardsBoughtThisTurn.filter { $0.key == observer }
        for index in result.players.indices where result.players[index].id != observer {
            result.players[index].resources = [:]
            result.players[index].devCards = []
        }
        result.naval?.islandByHex = [:]
        result.naval?.colonizedIslands = [:]
        result.naval?.generationAttempts = 0
        result.naval?.usedFallback = false
        if result.naval?.options.mapFamily == nil { result.naval?.mapFamily = .archipelago }
        return result
    }

    @discardableResult
    static func reveal(around centers: [HexCoordinate], by player: PlayerID,
                       in state: inout GameState) -> [GameEvent] {
        reveal(by: player, in: &state) { coordinate in
            centers.contains { coordinate.distance(to: $0) <= viewingRange }
        }
    }

    /// Already discovered terrain stays public even when a piece leaves, or an older save has a wider footprint.
    private static func reveal(by player: PlayerID, in state: inout GameState,
                               matching isWithinRange: (HexCoordinate) -> Bool) -> [GameEvent] {
        guard let naval = state.naval else { return [] }
        let discovered = state.board.tiles.map(\.coordinate).filter { coordinate in
            !naval.revealed.contains(coordinate) && isWithinRange(coordinate)
        }.sorted()
        state.naval?.revealed.formUnion(discovered)
        return discovered.isEmpty ? [] : [.discovered(player, hexes: discovered)]
    }

    static func revealBuilding(at vertex: VertexID, by player: PlayerID, in state: inout GameState) -> [GameEvent] {
        guard let naval = state.naval else { return [] }
        if naval.rulesVersion == oldestSupportedRulesVersion {
            let centers = state.board.tiles.filter { vertex.touchingTiles.contains($0.coordinate) && $0.kind.isLand }.map(\.coordinate)
            return reveal(around: centers, by: player, in: &state)
        }
        return reveal(by: player, in: &state) { isWithinViewingRange($0, of: vertex) }
    }

    static func awardColony(at vertex: VertexID, by player: PlayerID, in state: inout GameState) -> [GameEvent] {
        guard let naval = state.naval else { return [] }
        let islands = vertex.touchingTiles.compactMap { naval.islandByHex[$0] }.filter { $0 != 0 }.sorted()
        guard let island = islands.first, !(naval.colonizedIslands[player] ?? []).contains(island) else { return [] }
        state.naval?.colonizedIslands[player, default: []].insert(island)
        let previous = naval.colonyPoints[player, default: 0]
        guard previous < maximumColonyPoints else { return [] }
        state.naval?.colonyPoints[player] = previous + 1
        return [.earnedColonyPoint(player, total: previous + 1)]
    }
}
