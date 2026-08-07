public enum RulesEngine {
    public static func legalMoves(for state: GameState) -> [GameMove] {
        switch state.phase {
        case .setupForward, .setupBackward:
            return SetupPhase.legalMoves(for: state)

        case .rollDice:
            return [.rollDice]

        case .mainTurn(let playerIndex):
            let player = state.players[playerIndex]
            var moves: [GameMove] = [.endTurn]

            if canAfford(Building.roadCost, player: player) {
                moves.append(contentsOf: state.board.onBoardEdges
                    .filter { Building.canBuildRoad($0, for: player.id, in: state) }
                    .map { .buildRoad($0) })
            }
            if canAfford(Building.settlementCost, player: player) {
                moves.append(contentsOf: state.board.onBoardVertices
                    .filter { Building.canBuildSettlement($0, for: player.id, in: state) }
                    .map { .buildSettlement($0) })
            }
            if canAfford(Building.cityCost, player: player) {
                moves.append(contentsOf: player.settlements
                    .filter { Building.canBuildCity($0, for: player.id, in: state) }
                    .map { .buildCity($0) })
            }
            return moves

        default:
            // Later tasks extend this switch for the other phases.
            return []
        }
    }

    public static func apply(_ move: GameMove, by player: PlayerID, to state: inout GameState) throws {
        switch state.phase {
        case .setupForward, .setupBackward:
            switch move {
            case .placeInitialSettlement, .placeInitialRoad:
                try SetupPhase.apply(move, by: player, to: &state)
            default:
                throw MoveError.wrongPhase
            }

        case .rollDice(let playerIndex):
            guard player.index == playerIndex else { throw MoveError.notYourTurn }
            guard case .rollDice = move else { throw MoveError.wrongPhase }
            let roll = Int.random(in: 1...6) + Int.random(in: 1...6)
            MainPhase.rollDice(state: &state, roll: roll)
            if roll != 7 {
                state.phase = .mainTurn(playerIndex: playerIndex)
            }
            // A roll of 7 routes into .discarding or .movingRobber, already
            // set by MainPhase.rollDice.

        case .discarding(let pending):
            guard pending.contains(player) else { throw MoveError.notYourTurn }
            guard case .discard(let discarded) = move else { throw MoveError.wrongPhase }
            guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
                throw MoveError.other("unknown player")
            }
            let total = discarded.values.reduce(0, +)
            guard total == Robber.discardCount(for: state.players[playerIndex]) else {
                throw MoveError.illegalPlacement
            }
            try deduct(discarded, from: &state, playerIndex: playerIndex)

            var remainingPending = pending
            remainingPending.remove(player)
            if remainingPending.isEmpty {
                state.phase = .movingRobber(playerIndex: state.robberMoverIndex ?? playerIndex)
                state.robberMoverIndex = nil
            } else {
                state.phase = .discarding(pending: remainingPending)
            }

        case .movingRobber(let playerIndex):
            guard player.index == playerIndex else { throw MoveError.notYourTurn }
            guard case .moveRobber(let target, let stealFrom) = move else { throw MoveError.wrongPhase }
            try Robber.apply(move: target, stealFrom: stealFrom, by: player, to: &state)
            state.phase = .mainTurn(playerIndex: playerIndex)

        case .mainTurn(let playerIndex):
            guard player.index == playerIndex else { throw MoveError.notYourTurn }

            switch move {
            case .buildRoad(let edge):
                guard Building.canBuildRoad(edge, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.roadCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].roads.insert(edge)
                state.longestRoadPlayer = LongestRoad.compute(for: state)

            case .buildSettlement(let vertex):
                guard Building.canBuildSettlement(vertex, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.settlementCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].settlements.insert(vertex)

            case .buildCity(let vertex):
                guard Building.canBuildCity(vertex, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.cityCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].settlements.remove(vertex)
                state.players[playerIndex].cities.insert(vertex)

            case .endTurn:
                let nextIndex = (playerIndex + 1) % state.players.count
                state.phase = .rollDice(playerIndex: nextIndex)

            default:
                // Trading and dev cards are later tasks.
                throw MoveError.wrongPhase
            }

        default:
            // Later tasks extend this switch for the other phases.
            throw MoveError.wrongPhase
        }
    }

    // MARK: - Helpers

    private static func canAfford(_ cost: [Resource: Int], player: Player) -> Bool {
        cost.allSatisfy { resource, amount in (player.resources[resource] ?? 0) >= amount }
    }

    private static func deduct(_ cost: [Resource: Int], from state: inout GameState, playerIndex: Int) throws {
        guard canAfford(cost, player: state.players[playerIndex]) else { throw MoveError.insufficientResources }
        for (resource, amount) in cost {
            state.players[playerIndex].resources[resource, default: 0] -= amount
            state.bank[resource, default: 0] += amount
        }
    }
}
