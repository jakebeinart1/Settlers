import Foundation

/// Authoritative naval rules and public geometry. UI and policies share these predicates.
public enum Naval {
    /// Version 4 makes rival ships block entry, passage and launching in their sea hex.
    /// Version 3 introduced two-hex destination sailing; earlier saves retain three adjacent moves,
    /// and version 1 also retains its original land-centered building vision.
    public static let currentRulesVersion = 4
    public static let oldestSupportedRulesVersion = 1
    public static let currentMapVersion = 1
    public static let movementPerTurn = 2
    public static let destinationSailingRulesVersion = 3
    public static let blockadeRulesVersion = 4
    private static let legacyMovementPerTurn = 3
    public static let viewingRange = 2
    public static let hullsPerBuilder = 6
    public static let maximumColonyPoints = 2
    public static let worldRadius = 7
    public static let homeRadius = 2
    public static let shipCost: [Resource: Int] = [.lumber: 2, .wool: 1, .ore: 2]

    public static func newGame(seed: UInt64, playerCount: Int = 4,
                               options: NavalOptions = NavalOptions()) -> GameState {
        var rng = RandomSource(seed: seed)
        let map = NavalMapGenerator.generate(using: &rng, options: options)
        var state = GameSetup.newGame(board: map.board, rng: &rng, playerCount: playerCount, mode: .naval)
        state.naval = NavalState(options: options, mapFamily: map.family)
        state.naval?.islandByHex = map.islandByHex
        state.naval?.generationAttempts = map.generationAttempts
        state.naval?.usedFallback = map.usedFallback
        let opening = map.board.tiles.filter { $0.coordinate.distance(to: HexCoordinate(q: 0, r: 0)) <= homeRadius }
        state.naval?.revealed = Set((options.fogEnabled ? opening : map.board.tiles).map(\.coordinate))
        return state
    }

    public static func colonyPoints(for player: PlayerID, in state: GameState) -> Int {
        state.naval?.colonyPoints[player, default: 0] ?? 0
    }

    public static func shipsBuilt(by player: PlayerID, in state: GameState) -> Int {
        state.naval?.hullsBuilt[player, default: 0] ?? 0
    }

    public static func isRevealed(_ coordinate: HexCoordinate, in state: GameState) -> Bool {
        guard let naval = state.naval else { return true }
        return naval.revealed.contains(coordinate)
    }

    public static func isCoastal(_ vertex: VertexID, in state: GameState) -> Bool {
        let kinds = state.board.tiles.filter { vertex.touchingTiles.contains($0.coordinate) }.map(\.kind)
        return kinds.contains(where: \.isLand) && kinds.contains(.sea)
    }

    public static func isKnownLand(_ coordinate: HexCoordinate, in state: GameState) -> Bool {
        isRevealed(coordinate, in: state) && state.board.tiles.contains { $0.coordinate == coordinate && $0.kind.isLand }
    }

    /// Rival ownership blocks entry, regardless of remaining movement. Earlier matches keep
    /// their original overlap rules. Friendly ships may stack; capture may create a mixed stack,
    /// whose ships can leave because route searches test entry rather than their starting hex.
    public static func isBlockaded(_ coordinate: HexCoordinate, by player: PlayerID, in state: GameState) -> Bool {
        guard let naval = state.naval, naval.rulesVersion >= blockadeRulesVersion else { return false }
        return naval.ships.contains { $0.owner != player && $0.coordinate == coordinate }
    }

    /// Every available launch sea hex touches an owned building, is publicly known, and has no rival ship.
    public static func launchSites(for player: PlayerID, in state: GameState) -> [HexCoordinate] {
        coastalLaunchSites(for: player, in: state).filter { !isBlockaded($0, by: player, in: state) }
    }

    /// Otherwise valid launches prevented by rival ships. UI explanations share the exact
    /// ownership, charted coast and hull-supply checks used by legal moves and move application.
    public static func blockadedLaunchSites(for player: PlayerID, in state: GameState) -> [HexCoordinate] {
        coastalLaunchSites(for: player, in: state).filter { isBlockaded($0, by: player, in: state) }
    }

    private static func coastalLaunchSites(for player: PlayerID, in state: GameState) -> [HexCoordinate] {
        guard let owner = state.players.first(where: { $0.id == player }), let naval = state.naval,
              naval.hullsBuilt[player, default: 0] < hullsPerBuilder else { return [] }
        let buildings = owner.settlements.union(owner.cities)
        return state.board.tiles.filter { tile in
            tile.kind == .sea && isRevealed(tile.coordinate, in: state)
                && buildings.contains { $0.touchingTiles.contains(tile.coordinate) }
        }.map(\.coordinate).sorted()
    }

    /// The allowance belongs to the saved match, so updating the app cannot change its replay.
    public static func movementPerTurn(in state: GameState) -> Int {
        (state.naval?.rulesVersion ?? currentRulesVersion) < destinationSailingRulesVersion
            ? legacyMovementPerTurn : movementPerTurn
    }

    /// Public future landing sites ignore current ship presence, but retain real placement rules.
    public static func potentialColonySites(for player: PlayerID, in state: GameState) -> [VertexID] {
        state.board.onBoardVertices.filter {
            canFoundColony(at: $0, by: player, in: state, requiresShip: false)
        }.sorted()
    }

    public static func canFoundColony(at vertex: VertexID, by player: PlayerID,
                                      in state: GameState, requiresShip: Bool = true) -> Bool {
        guard state.naval != nil, isCoastal(vertex, in: state), settlementSiteIsAvailable(vertex, by: player, in: state) else {
            return false
        }
        return !requiresShip || state.naval?.ships.contains {
            $0.owner == player && vertex.touchingTiles.contains($0.coordinate)
        } == true
    }

    /// Shared distance/supply predicate deliberately does not require an existing road.
    static func settlementSiteIsAvailable(_ vertex: VertexID, by player: PlayerID, in state: GameState) -> Bool {
        guard state.board.onBoardVertices.contains(vertex),
              let owner = state.players.first(where: { $0.id == player }),
              owner.settlements.count < state.rules.pieceLimit(for: .settlement) else { return false }
        let touching = state.board.tiles.filter { vertex.touchingTiles.contains($0.coordinate) }
        let setup = state.phase.isSetup
        guard touching.contains(where: { $0.kind.isLand }),
              touching.allSatisfy({ tile in
                  (isRevealed(tile.coordinate, in: state) && tile.kind != .fog) || (setup && tile.kind == .sea)
              }) else { return false }
        let forbidden = Set(state.players.flatMap { $0.settlements.union($0.cities) })
        return !forbidden.contains(vertex) && !state.board.adjacentVertices(of: vertex).contains(where: forbidden.contains)
    }

    static func roadIsKnownLand(_ edge: EdgeID, in state: GameState) -> Bool {
        let touching = Set(edge.a.touchingTiles).intersection(edge.b.touchingTiles)
        return state.board.tiles.contains { touching.contains($0.coordinate) && isKnownLand($0.coordinate, in: state) }
    }

    static func isHomeSite(_ vertex: VertexID, in state: GameState) -> Bool {
        vertex.touchingTiles.contains { isKnownLand($0, in: state) && $0.distance(to: HexCoordinate(q: 0, r: 0)) <= homeRadius }
    }

    /// A real sea/land coast differs from the envelope boundary used by older all-land maps.
    static func landBoard(tiles: [Tile], ports: [Port], robber: HexCoordinate) -> Board {
        let land = tiles.filter { $0.kind.isLand }
        let edges = Set(land.flatMap { HexGeometry.edges(of: $0.coordinate) })
        return Board(tiles: tiles, ports: ports, onBoardVertices: Set(edges.flatMap { [$0.a, $0.b] }),
                     onBoardEdges: edges, robberTile: robber)
    }
}
