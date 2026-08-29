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
    /// Returns the resource actually stolen, or `nil` if nothing was taken.
    /// Only the engine knows which card the robber drew, so it has to say -
    /// otherwise a recorded game cannot report it and a replay cannot check it.
    @discardableResult
    public static func apply(
        move robberTo: HexCoordinate,
        stealFrom: PlayerID?,
        by player: PlayerID,
        to state: inout GameState
    ) throws -> Resource? {
        guard robberTo != state.board.robberTile else { throw MoveError.illegalPlacement }

        if let victimID = stealFrom {
            guard victimID != player else { throw MoveError.illegalPlacement }
            guard eligibleVictims(for: robberTo, thief: player, in: state).contains(victimID) else {
                throw MoveError.illegalPlacement
            }
            let victimIndex = state.players.firstIndex(where: { $0.id == victimID })!
            let thiefIndex = state.players.firstIndex(where: { $0.id == player })!

            // Built by iterating `Resource.allCases` rather than the victim's
            // `resources` dictionary: dictionary iteration order is seeded
            // per-process by Swift, so pooling straight from it would make the
            // stolen card vary between runs even with an identical generator
            // state - the pool order has to be stable for the draw to be.
            var pool: [Resource] = []
            for resource in Resource.allCases {
                let count = state.players[victimIndex].resources[resource] ?? 0
                pool.append(contentsOf: repeatElement(resource, count: count))
            }
            // Safe to force-unwrap: `eligibleVictims` above already required
            // the victim to hold at least one card.
            let stolen = pool.randomElement(using: &state.rng)!
            state.players[victimIndex].resources[stolen, default: 0] -= 1
            state.players[thiefIndex].resources[stolen, default: 0] += 1
            state.board.robberTile = robberTo
            return stolen
        }

        state.board.robberTile = robberTo
        return nil
    }

    /// Players eligible to be stolen from once the robber sits on `tile`:
    /// everyone but `thief` with a settlement/city on one of `tile`'s
    /// corners and at least one resource card. Shared by `apply` (to
    /// validate a proposed `stealFrom`) and `RulesEngine.legalMoves` (to
    /// enumerate every legal `.moveRobber` target/victim pairing).
    public static func eligibleVictims(for tile: HexCoordinate, thief: PlayerID, in state: GameState) -> [PlayerID] {
        let corners = HexGeometry.corners(of: tile)
        return state.players.compactMap { candidate in
            guard candidate.id != thief, totalResources(candidate) > 0 else { return nil }
            let borders = corners.contains { candidate.settlements.contains($0) || candidate.cities.contains($0) }
            return borders ? candidate.id : nil
        }
    }

    private static func totalResources(_ player: Player) -> Int {
        player.resources.values.reduce(0, +)
    }
}
