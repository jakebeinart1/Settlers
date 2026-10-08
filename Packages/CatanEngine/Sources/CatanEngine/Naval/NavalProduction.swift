import Foundation

extension Naval {
    /// Fixed payouts have already been applied. Clockwise choice obligations precede capture.
    static func beginProduction(roll: Int, rollerIndex: Int, in state: inout GameState) {
        guard let naval = state.naval else { return }
        let choices = resourceChoices(for: roll, rollerIndex: rollerIndex, in: state)
        state.naval?.pendingResourceChoices = choices
        state.naval?.productionRollerIndex = rollerIndex
        state.naval?.capturePending = roll == 11 && naval.options.shipStealingEnabled
        advanceProduction(in: &state)
    }

    /// The board cannot change during choice resolution, so saves can verify its remaining suffix.
    static func resourceChoices(for roll: Int, rollerIndex: Int, in state: GameState) -> [NavalResourceChoice] {
        let ordered = (0..<state.players.count).map { (rollerIndex + $0) % state.players.count }
        return ordered.compactMap { index in
            let amount = harvestEntitlement(for: state.players[index], roll: roll, in: state).total
            return amount > 0 ? NavalResourceChoice(playerIndex: index, remaining: amount) : nil
        }
    }

    /// Only the seat resolving production receives progress. The same yield
    /// calculation creates and validates obligations, so presentation cannot
    /// mistake two settlements for a city or restart a partly collected harvest.
    public static func harvestProgress(for player: PlayerID, in state: GameState) -> NavalHarvestProgress? {
        guard case .choosingResource(let index) = state.phase, index == player.index,
              let pending = state.naval?.pendingResourceChoices.first, pending.playerIndex == index,
              let roll = state.lastDiceRoll else { return nil }
        let entitlement = harvestEntitlement(for: state.players[index], roll: roll, in: state)
        return NavalHarvestProgress(settlements: entitlement.settlements, cities: entitlement.cities,
                                    remaining: pending.remaining)
    }

    private static func harvestEntitlement(for player: Player, roll: Int, in state: GameState) -> NavalHarvestProgress {
        var settlements = 0
        var cities = 0
        for tile in state.board.tiles where tile.kind == .resourceChoice
            && tile.numberToken == roll && tile.coordinate != state.board.robberTile {
            let corners = Set(state.board.corners(of: tile.coordinate))
            settlements += player.settlements.intersection(corners).count
            cities += player.cities.intersection(corners).count
        }
        return NavalHarvestProgress(settlements: settlements, cities: cities)
    }

    static func resourceMoves(in state: GameState) -> [GameMove] {
        Resource.allCases.filter { state.bank[$0, default: 0] > 0 }.map { .chooseResource($0) }
    }

    static func choose(_ resource: Resource, by player: PlayerID, in state: inout GameState) throws -> [GameEvent] {
        guard let first = state.naval?.pendingResourceChoices.first, first.playerIndex == player.index,
              first.remaining > 0 else { throw MoveError.wrongPhase }
        guard state.bank[resource, default: 0] > 0 else { throw MoveError.bankCannotSupply(resource) }
        state.bank[resource, default: 0] -= 1
        state.players[player.index].resources[resource, default: 0] += 1
        state.naval?.pendingResourceChoices[0].remaining -= 1
        if first.remaining == 1 { state.naval?.pendingResourceChoices.removeFirst() }
        advanceProduction(in: &state)
        return [.choseResource(player, resource: resource)]
    }

    private static func advanceProduction(in state: inout GameState) {
        guard let naval = state.naval, let roller = naval.productionRollerIndex else { return }
        if !Resource.allCases.contains(where: { state.bank[$0, default: 0] > 0 }) {
            state.naval?.pendingResourceChoices = []
        }
        if let next = state.naval?.pendingResourceChoices.first {
            state.phase = .choosingResource(playerIndex: next.playerIndex)
        } else if naval.capturePending && naval.ships.contains(where: { $0.owner.index != roller }) {
            state.phase = .capturingShip(playerIndex: roller)
        } else {
            state.naval?.capturePending = false
            state.naval?.productionRollerIndex = nil
            state.phase = .mainTurn(playerIndex: roller)
        }
    }
}
