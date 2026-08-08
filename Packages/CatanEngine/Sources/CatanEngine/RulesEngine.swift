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
            if canAfford(Building.devCardCost, player: player) && !state.devCardDeck.isEmpty {
                moves.append(.buyDevCard)
            }
            if DevCards.canPlay(.knight, by: player.id, in: state) {
                for tile in state.board.tiles.map(\.coordinate) where tile != state.board.robberTile {
                    moves.append(.playKnight(moveRobberTo: tile, stealFrom: nil))
                    moves.append(contentsOf: Robber.eligibleVictims(for: tile, thief: player.id, in: state)
                        .map { .playKnight(moveRobberTo: tile, stealFrom: $0) })
                }
            }
            if DevCards.canPlay(.roadBuilding, by: player.id, in: state) {
                let legalEdges = state.board.onBoardEdges.filter { Building.canBuildRoad($0, for: player.id, in: state) }
                for e1 in legalEdges {
                    var afterE1 = state
                    afterE1.players[playerIndex].roads.insert(e1)
                    for e2 in state.board.onBoardEdges where e2 != e1 && Building.canBuildRoad(e2, for: player.id, in: afterE1) {
                        moves.append(.playRoadBuilding(e1, e2))
                    }
                }
            }
            if DevCards.canPlay(.yearOfPlenty, by: player.id, in: state) {
                for r1 in Resource.allCases {
                    for r2 in Resource.allCases {
                        moves.append(.playYearOfPlenty(r1, r2))
                    }
                }
            }
            if DevCards.canPlay(.monopoly, by: player.id, in: state) {
                moves.append(contentsOf: Resource.allCases.map { .playMonopoly($0) })
            }
            for resource in Resource.allCases {
                let rate = Trading.bestRate(for: resource, player: player.id, state: state)
                guard (player.resources[resource] ?? 0) >= rate else { continue }
                for other in Resource.allCases where other != resource && (state.bank[other] ?? 0) >= 1 {
                    moves.append(.bankTrade(give: [resource: rate], get: [other: 1]))
                }
            }
            for offer in state.pendingTradeOffers where offer.from != player.id {
                // Accepting is only actually legal if the responder currently
                // holds what's wanted and the proposer still holds what they
                // offered (either side may have spent/traded cards since the
                // offer was made) - `Trading.respond` re-validates both and
                // throws otherwise, so `legalMoves` must match.
                if let proposer = state.players.first(where: { $0.id == offer.from }),
                   canAfford(offer.want, player: player),
                   canAfford(offer.give, player: proposer) {
                    moves.append(.respondToTrade(offerID: offer.id, accept: true))
                }
                moves.append(.respondToTrade(offerID: offer.id, accept: false))
            }
            // Pragmatic proposal enumeration: for each resource the player
            // has a surplus of (more than one card), offer trading exactly
            // one of it to each other player for each resource type - not
            // exhaustive over quantities/combinations, just enough for bots
            // to have real proposals to consider.
            for (resource, amount) in player.resources where amount > 1 {
                for other in state.players where other.id != player.id {
                    for wanted in Resource.allCases where wanted != resource {
                        moves.append(.proposeTrade(TradeOffer(from: player.id, give: [resource: 1], want: [wanted: 1])))
                    }
                }
            }
            return moves

        case .discarding(let pending):
            // No single "acting player" is embedded in this phase - any
            // player in `pending` may discard whenever they're ready - so
            // this returns the union of every legal `.discard` combination
            // across all of them.
            var moves: [GameMove] = []
            for pid in pending {
                guard let playerIndex = state.players.firstIndex(where: { $0.id == pid }) else { continue }
                let player = state.players[playerIndex]
                let count = Robber.discardCount(for: player)
                moves.append(contentsOf: discardCombinations(holding: player.resources, count: count).map { .discard($0) })
            }
            return moves

        case .movingRobber(let playerIndex):
            let thief = state.players[playerIndex].id
            var moves: [GameMove] = []
            for tile in state.board.tiles.map(\.coordinate) where tile != state.board.robberTile {
                moves.append(.moveRobber(tile, stealFrom: nil))
                moves.append(contentsOf: Robber.eligibleVictims(for: tile, thief: thief, in: state)
                    .map { .moveRobber(tile, stealFrom: $0) })
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
            guard discarded.values.allSatisfy({ $0 >= 0 }) else { throw MoveError.illegalPlacement }
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
            state.robberMoverIndex = nil
            state.phase = .mainTurn(playerIndex: playerIndex)

        case .mainTurn(let playerIndex):
            // Trade responses come from whichever player the offer is
            // directed at, not necessarily the active turn player, so this
            // is handled before the "is it your turn" guard below.
            if case .respondToTrade(let offerID, let accept) = move {
                try Trading.respond(offerID: offerID, accept: accept, by: player, state: &state)
                return
            }

            guard player.index == playerIndex else { throw MoveError.notYourTurn }

            switch move {
            case .buildRoad(let edge):
                guard Building.canBuildRoad(edge, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.roadCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].roads.insert(edge)
                state.longestRoadPlayer = LongestRoad.compute(for: state)
                WinCondition.checkForWinner(&state)

            case .buildSettlement(let vertex):
                guard Building.canBuildSettlement(vertex, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.settlementCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].settlements.insert(vertex)
                WinCondition.checkForWinner(&state)

            case .buildCity(let vertex):
                guard Building.canBuildCity(vertex, for: player, in: state) else { throw MoveError.illegalPlacement }
                try deduct(Building.cityCost, from: &state, playerIndex: playerIndex)
                state.players[playerIndex].settlements.remove(vertex)
                state.players[playerIndex].cities.insert(vertex)
                WinCondition.checkForWinner(&state)

            case .buyDevCard:
                try DevCards.buy(by: player, state: &state)
                // A bought VP card counts toward victory points immediately
                // (it's the "playing" of a knight/road-building/etc. card
                // that's deferred a turn, not VP cards being counted), so a
                // win can trigger right here even though the card can't be
                // "played".
                WinCondition.checkForWinner(&state)

            case .playKnight(let moveRobberTo, let stealFrom):
                try DevCards.playKnight(moveRobberTo: moveRobberTo, stealFrom: stealFrom, by: player, state: &state)
                WinCondition.checkForWinner(&state)

            case .playRoadBuilding(let e1, let e2):
                try DevCards.playRoadBuilding(e1, e2, by: player, state: &state)
                WinCondition.checkForWinner(&state)

            case .playYearOfPlenty(let r1, let r2):
                try DevCards.playYearOfPlenty(r1, r2, by: player, state: &state)

            case .playMonopoly(let resource):
                try DevCards.playMonopoly(resource, by: player, state: &state)

            case .bankTrade(let give, let get):
                try Trading.bankTrade(give: give, get: get, by: player, state: &state)

            case .proposeTrade(let offer):
                guard offer.from == player else { throw MoveError.notYourTurn }
                try Trading.proposeTrade(offer, state: &state)

            case .endTurn:
                state.devCardsBoughtThisTurn = [:]
                let nextIndex = (playerIndex + 1) % state.players.count
                state.phase = .rollDice(playerIndex: nextIndex)

            default:
                throw MoveError.wrongPhase
            }

        default:
            // Later tasks extend this switch for the other phases.
            throw MoveError.wrongPhase
        }
    }

    // MARK: - Helpers

    static func canAfford(_ cost: [Resource: Int], player: Player) -> Bool {
        cost.allSatisfy { resource, amount in (player.resources[resource] ?? 0) >= amount }
    }

    static func deduct(_ cost: [Resource: Int], from state: inout GameState, playerIndex: Int) throws {
        guard canAfford(cost, player: state.players[playerIndex]) else { throw MoveError.insufficientResources }
        for (resource, amount) in cost {
            state.players[playerIndex].resources[resource, default: 0] -= amount
            state.bank[resource, default: 0] += amount
        }
    }

    /// Every way to pick exactly `count` cards from `holding` (a resource ->
    /// count map), one resource type at a time via backtracking. Used to
    /// enumerate legal `.discard` combinations - small enough hands (at most
    /// ~18 cards over 5 resource types) that this never blows up.
    private static func discardCombinations(holding: [Resource: Int], count: Int) -> [[Resource: Int]] {
        let resources = Resource.allCases
        var results: [[Resource: Int]] = []

        func backtrack(index: Int, remaining: Int, chosen: [Resource: Int]) {
            if remaining == 0 {
                results.append(chosen)
                return
            }
            guard index < resources.count else { return }
            let resource = resources[index]
            let maxTake = min(remaining, holding[resource] ?? 0)
            for take in 0...maxTake {
                var next = chosen
                if take > 0 { next[resource] = take }
                backtrack(index: index + 1, remaining: remaining - take, chosen: next)
            }
        }

        backtrack(index: 0, remaining: count, chosen: [:])
        return results
    }
}
