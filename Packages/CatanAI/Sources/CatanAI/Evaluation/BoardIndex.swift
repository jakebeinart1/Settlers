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
}
