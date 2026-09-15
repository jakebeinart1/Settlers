import CatanEngine

/// The board derivations every seat's standing needs, computed once per
/// position instead of once per seat.
///
/// ## Why this is a type and not a few local variables
/// `PositionEvaluator.evaluate` scores every seat at the table, and a search
/// evaluates a position per candidate move. Without this, a four-player
/// evaluation rebuilt the tile dictionary and the occupied-vertex set four
/// times, and a thirty-candidate decision rebuilt them a hundred and twenty.
/// The planner's predecessor lost most of a 360ms decision to exactly this
/// class of repetition.
///
/// Everything here is public information: where the tiles are and which
/// vertices have buildings on them are both visible to everyone.
public struct BoardIndex: Sendable {

    /// Tiles by coordinate, for production lookups.
    public let tiles: [HexCoordinate: Tile]

    /// Every vertex holding any player's settlement or city.
    public let occupied: Set<VertexID>

    public init(state: GameState) {
        tiles = ProductionModel.tileIndex(of: state.board)
        var taken: Set<VertexID> = []
        for player in state.players {
            taken.formUnion(player.settlements)
            taken.formUnion(player.cities)
        }
        occupied = taken
    }

    /// Legal settlement sites `player` can reach along its own roads.
    ///
    /// ## Why not `Building.canBuildSettlement`
    /// That is the authority on legality and this must agree with it, but it
    /// rebuilds the occupied set on every call - so asking it about every
    /// vertex on the board would rebuild that set fifty-four times per seat
    /// per evaluated position. This walks outward from the player's own roads
    /// instead, which is the far smaller set, and applies the same two rules:
    /// the vertex is free, and no neighbour of it is occupied.
    ///
    /// Returned sorted. The caller takes a maximum over these, and a tie
    /// between two equal sites must break the same way in every process.
    public func buildableSites(for player: PlayerID, in state: GameState) -> [VertexID] {
        guard let owner = state.players.first(where: { $0.id == player }) else { return [] }
        guard owner.settlements.count < state.rules.pieceLimit(for: .settlement) else { return [] }

        var reachable: Set<VertexID> = []
        for edge in owner.roads {
            let (a, b) = state.board.vertices(of: edge)
            reachable.insert(a)
            reachable.insert(b)
        }

        return reachable
            .filter { vertex in
                guard !occupied.contains(vertex) else { return false }
                return !state.board.adjacentVertices(of: vertex).contains { occupied.contains($0) }
            }
            .sorted()
    }

    /// Legal settlement sites `player` could reach by building roads, each with
    /// the number of roads it would take, out to `limit`.
    ///
    /// ## Why sites beyond the road network have to be visible
    /// `buildableSites` answers only "where can I settle today", and it was the
    /// only expansion signal the evaluator had. A road that brings a site one
    /// step closer changed nothing it could see, so it scored as nothing - and
    /// once every site next to a seat's roads was gone, no sequence of moves
    /// the bot could evaluate led anywhere. Classic games end before the board
    /// fills, so this never showed. Expanded games between Expert bots did not:
    /// seats sat at 24 of 25 with cities maxed, the development deck empty and
    /// both bonuses settled - the only way to the last point was a settlement
    /// two roads away - and proposed refused trades until the move cap.
    ///
    /// ## What a road may not pass
    /// Breadth-first over free edges, never through an opponent's road or an
    /// opponent's building. The engine forbids extending a road past an
    /// opponent's settlement (`Building.canBuildRoad`), so a search that walked
    /// through one would point the bot at a site it cannot reach - which is
    /// just a different stall. Sorted enumeration throughout, because this
    /// feeds a floating-point maximum and `Set` order is seeded per process.
    public func approachableSites(
        for player: PlayerID,
        in state: GameState,
        limit: Int
    ) -> [(vertex: VertexID, roads: Int)] {
        guard let owner = state.players.first(where: { $0.id == player }) else { return [] }
        guard owner.settlements.count < state.rules.pieceLimit(for: .settlement) else { return [] }
        let roadsLeft = state.rules.maxRoadsPerPlayer - owner.roads.count
        let reach = min(limit, roadsLeft)
        guard reach > 0 else { return [] }

        let distances = roadDistances(from: owner, in: state, limit: reach)
        return distances
            .filter { $0.value >= 1 && isSettlementSite($0.key, in: state) }
            .map { (vertex: $0.key, roads: $0.value) }
            .sorted { $0.roads != $1.roads ? $0.roads < $1.roads : $0.vertex < $1.vertex }
    }

    /// Whether a settlement could stand at `vertex` under the distance rule.
    private func isSettlementSite(_ vertex: VertexID, in state: GameState) -> Bool {
        guard !occupied.contains(vertex) else { return false }
        return !state.board.adjacentVertices(of: vertex).contains { occupied.contains($0) }
    }

    /// Roads needed to reach each vertex from `owner`'s network, to `limit`.
    private func roadDistances(from owner: Player, in state: GameState, limit: Int) -> [VertexID: Int] {
        let theirRoads = state.players
            .filter { $0.id != owner.id }
            .reduce(into: Set<EdgeID>()) { $0.formUnion($1.roads) }
        let ownBuildings = owner.settlements.union(owner.cities)
        let theirBuildings = occupied.subtracting(ownBuildings)

        var distances: [VertexID: Int] = [:]
        var frontier: [VertexID] = []
        let seeds = owner.roads.flatMap { [$0.a, $0.b] } + Array(ownBuildings)
        for vertex in Set(seeds).sorted() where !theirBuildings.contains(vertex) {
            distances[vertex] = 0
            frontier.append(vertex)
        }

        var index = 0
        while index < frontier.count {
            let vertex = frontier[index]
            index += 1
            let distance = distances[vertex] ?? 0
            guard distance < limit else { continue }
            for edge in state.board.edgesTouching(vertex).sorted() where !theirRoads.contains(edge) {
                let (a, b) = state.board.vertices(of: edge)
                let next = a == vertex ? b : a
                guard distances[next] == nil, !theirBuildings.contains(next) else { continue }
                distances[next] = distance + 1
                frontier.append(next)
            }
        }
        return distances
    }
}
