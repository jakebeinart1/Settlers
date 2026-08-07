/// Robber rules: who must discard on a 7-roll, how many cards, and moving
/// the robber (with an optional random steal from an adjacent player).
public enum Robber {
    /// Players currently holding more than 7 resource cards; each must
    /// discard half (rounded down) when a 7 is rolled.
    public static func playersWhoMustDiscard(_ state: GameState) -> Set<PlayerID> {
        Set(state.players.filter { totalResources($0) > 7 }.map(\.id))
    }

    /// Half of `player`'s total resource cards, rounded down.
    public static func discardCount(for player: Player) -> Int {
        totalResources(player) / 2
    }

    /// Moves the robber to `robberTo` and, if `stealFrom` is provided, moves
    /// one random resource card from that player's hand to `player`'s hand.
    /// `robberTo` must differ from the current robber tile; a non-nil
    /// `stealFrom` must name a player with a settlement/city touching
    /// `robberTo` and at least one resource card.
    public static func apply(
        move robberTo: HexCoordinate,
        stealFrom: PlayerID?,
        by player: PlayerID,
        to state: inout GameState
    ) throws {
        guard robberTo != state.board.robberTile else { throw MoveError.illegalPlacement }

        if let victimID = stealFrom {
            guard let victimIndex = state.players.firstIndex(where: { $0.id == victimID }) else {
                throw MoveError.illegalPlacement
            }
            let victim = state.players[victimIndex]
            let victimBorders = HexGeometry.corners(of: robberTo).contains { vertex in
                victim.settlements.contains(vertex) || victim.cities.contains(vertex)
            }
            guard victimBorders else { throw MoveError.illegalPlacement }
            guard totalResources(victim) > 0 else { throw MoveError.illegalPlacement }

            guard let thiefIndex = state.players.firstIndex(where: { $0.id == player }) else {
                throw MoveError.illegalPlacement
            }

            var pool: [Resource] = []
            for (resource, count) in victim.resources {
                pool.append(contentsOf: repeatElement(resource, count: count))
            }
            let stolen = pool.randomElement()!
            state.players[victimIndex].resources[stolen, default: 0] -= 1
            state.players[thiefIndex].resources[stolen, default: 0] += 1
        }

        state.board.robberTile = robberTo
    }

    private static func totalResources(_ player: Player) -> Int {
        player.resources.values.reduce(0, +)
    }
}
