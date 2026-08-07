/// Dice-driven resource production. Roll-injectable so tests can be
/// deterministic; `RulesEngine.apply(.rollDice, ...)` generates the actual
/// random roll and calls this internally.
public enum MainPhase {
    /// Applies resource production for `roll` (2-12; 7 produces nothing -
    /// robber handling is a later task). For each tile matching `roll` that
    /// isn't under the robber, every player with a settlement (1x) or city
    /// (2x) touching that tile earns that tile's resource, subject to bank
    /// depletion: if only one player demands a resource, they get whatever's
    /// left in the bank; if multiple players demand it and the bank can't
    /// cover the combined demand, no one gets that resource from this roll.
    public static func rollDice(state: inout GameState, roll: Int) {
        state.lastDiceRoll = roll
        guard roll != 7 else { return }

        var demand: [Resource: [(playerIndex: Int, amount: Int)]] = [:]
        for tile in state.board.tiles {
            guard tile.numberToken == roll, tile.coordinate != state.board.robberTile else { continue }
            guard case .resource(let resource) = tile.kind else { continue }

            for vertex in HexGeometry.corners(of: tile.coordinate) {
                for (index, player) in state.players.enumerated() {
                    if player.cities.contains(vertex) {
                        demand[resource, default: []].append((index, 2))
                    } else if player.settlements.contains(vertex) {
                        demand[resource, default: []].append((index, 1))
                    }
                }
            }
        }

        for (resource, entries) in demand {
            let total = entries.reduce(0) { $0 + $1.amount }
            let distinctPlayers = Set(entries.map(\.playerIndex))
            let bankAmount = state.bank[resource] ?? 0

            if distinctPlayers.count == 1 {
                let granted = min(total, bankAmount)
                guard granted > 0 else { continue }
                let playerIndex = entries[0].playerIndex
                state.players[playerIndex].resources[resource, default: 0] += granted
                state.bank[resource] = bankAmount - granted
            } else {
                guard bankAmount >= total else { continue }
                for entry in entries {
                    state.players[entry.playerIndex].resources[resource, default: 0] += entry.amount
                }
                state.bank[resource] = bankAmount - total
            }
        }
    }
}
