/// Dice-driven resource production. Roll-injectable so tests can be
/// deterministic; `RulesEngine.apply(.rollDice, ...)` generates the actual
/// random roll and calls this internally.
public enum MainPhase {
    /// Applies resource production for `roll` (2-12). Rolling a 7 produces
    /// nothing; instead it routes into the robber sequence - any player
    /// holding more than 7 cards must discard (`.discarding(pending:)`), or,
    /// if nobody must discard, the roller moves the robber immediately
    /// (`.movingRobber(playerIndex:)`). Otherwise, for each tile matching
    /// `roll` that isn't under the robber, every player with a settlement
    /// (1x) or city (2x) touching that tile earns that tile's resource,
    /// subject to bank depletion: if only one player demands a resource,
    /// they get whatever's left in the bank; if multiple players demand it
    /// and the bank can't cover the combined demand, no one gets that
    /// resource from this roll.
    public static func rollDice(state: inout GameState, roll: Int) {
        state.lastDiceRoll = roll
        guard roll != 7 else {
            let rollerIndex: Int
            if case .rollDice(let playerIndex) = state.phase {
                rollerIndex = playerIndex
            } else if case .mainTurn(let playerIndex) = state.phase {
                rollerIndex = playerIndex
            } else {
                rollerIndex = 0
            }
            state.robberMoverIndex = rollerIndex

            let pending = Robber.playersWhoMustDiscard(state)
            if pending.isEmpty {
                state.phase = .movingRobber(playerIndex: rollerIndex)
            } else {
                state.phase = .discarding(pending: pending)
            }
            return
        }

        for (playerIndex, gains) in payouts(for: roll, in: state) {
            for (resource, amount) in gains {
                state.players[playerIndex].resources[resource, default: 0] += amount
                state.bank[resource, default: 0] -= amount
            }
        }
    }

    /// What each seat earns from `roll`, without applying anything.
    ///
    /// Extracted from `rollDice` rather than copied beside it because this rule
    /// is derivable entirely from public information - the board, the robber,
    /// who owns which building, and the bank - and an observer that counts
    /// cards therefore needs the identical answer. A second payout formula
    /// written against the same inputs is a formula that can disagree with
    /// itself, which is precisely the defect the `playerLabel` copies caused.
    /// `CatanAI`'s `PublicLedger` folds this result; `rollDice` applies it.
    ///
    /// Keyed by index into `state.players`, matching how `rollDice` mutates.
    /// Returns an empty result for 7, which produces nothing.
    public static func payouts(for roll: Int, in state: GameState) -> [Int: [Resource: Int]] {
        guard roll != 7 else { return [:] }

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

        var granted: [Int: [Resource: Int]] = [:]
        for (resource, entries) in demand {
            let total = entries.reduce(0) { $0 + $1.amount }
            let distinctPlayers = Set(entries.map(\.playerIndex))
            let bankAmount = state.bank[resource] ?? 0

            if distinctPlayers.count == 1 {
                let amount = min(total, bankAmount)
                guard amount > 0 else { continue }
                granted[entries[0].playerIndex, default: [:]][resource, default: 0] += amount
            } else {
                // Contested and the bank cannot cover everyone: nobody is paid.
                guard bankAmount >= total else { continue }
                for entry in entries {
                    granted[entry.playerIndex, default: [:]][resource, default: 0] += entry.amount
                }
            }
        }
        return granted
    }
}
