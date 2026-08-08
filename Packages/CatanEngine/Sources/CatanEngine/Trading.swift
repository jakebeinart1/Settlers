import Foundation

/// Bank/port trading and player-to-player (including bot) trade negotiation.
public enum Trading {
    /// The best (lowest) bank-trade rate `player` can get for `resource`:
    /// 2 if they own a 2:1 port for that resource, else 3 if they own a
    /// generic 3:1 port, else 4.
    public static func bestRate(for resource: Resource, player: PlayerID, state: GameState) -> Int {
        guard let p = state.players.first(where: { $0.id == player }) else { return 4 }
        let owned = p.settlements.union(p.cities)

        var sawGeneric = false
        for port in state.board.ports where owned.contains(port.vertexA) || owned.contains(port.vertexB) {
            switch port.kind {
            case .resource(let r) where r == resource:
                return 2
            case .generic:
                sawGeneric = true
            default:
                break
            }
        }
        return sawGeneric ? 3 : 4
    }

    /// Trades `give` for `get` with the bank, at `player`'s best rate for
    /// each given resource. Validates the ratio and that the bank can cover
    /// what's requested.
    public static func bankTrade(give: [Resource: Int], get: [Resource: Int], by player: PlayerID, state: inout GameState) throws {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            throw MoveError.other("unknown player")
        }
        // Every entry must be a strictly-positive count of an actual
        // exchange - zero/negative amounts would let `-=`/`+=` below run
        // backwards and mint or steal resources for free.
        guard give.values.allSatisfy({ $0 > 0 }), get.values.allSatisfy({ $0 > 0 }) else {
            throw MoveError.illegalPlacement
        }
        let giveTotal = give.values.reduce(0, +)
        let getTotal = get.values.reduce(0, +)
        guard giveTotal > 0, getTotal > 0 else { throw MoveError.illegalPlacement }

        // Each given resource must be offered in a quantity that's a whole
        // multiple of its own best rate, and the total given must convert to
        // exactly the total requested at those rates.
        var convertedTotal = 0
        for (resource, amount) in give {
            let rate = bestRate(for: resource, player: player, state: state)
            guard amount % rate == 0 else { throw MoveError.illegalPlacement }
            convertedTotal += amount / rate
        }
        guard convertedTotal == getTotal else { throw MoveError.illegalPlacement }

        guard RulesEngine.canAfford(give, player: state.players[playerIndex]) else {
            throw MoveError.insufficientResources
        }
        for (resource, amount) in get {
            guard (state.bank[resource] ?? 0) >= amount else { throw MoveError.insufficientResources }
        }

        for (resource, amount) in give {
            state.players[playerIndex].resources[resource, default: 0] -= amount
            state.bank[resource, default: 0] += amount
        }
        for (resource, amount) in get {
            state.players[playerIndex].resources[resource, default: 0] += amount
            state.bank[resource, default: 0] -= amount
        }
    }

    /// Adds `offer` to `state.pendingTradeOffers`, after verifying the
    /// proposer actually holds the cards they're offering to give.
    public static func proposeTrade(_ offer: TradeOffer, state: inout GameState) throws {
        guard let proposer = state.players.first(where: { $0.id == offer.from }) else {
            throw MoveError.other("unknown player")
        }
        // Strictly-positive amounts only - see `bankTrade` for why a
        // zero/negative entry is dangerous, not just meaningless.
        guard offer.give.values.allSatisfy({ $0 > 0 }), offer.want.values.allSatisfy({ $0 > 0 }) else {
            throw MoveError.illegalPlacement
        }
        guard RulesEngine.canAfford(offer.give, player: proposer) else {
            throw MoveError.insufficientResources
        }
        state.pendingTradeOffers.append(offer)
    }

    /// Resolves a pending trade offer. Accepting swaps `give`/`want` cards
    /// between the proposer and `responder` (after validating the responder
    /// actually holds the wanted cards); rejecting just drops the offer.
    /// Either way the offer is removed from `pendingTradeOffers`.
    public static func respond(offerID: UUID, accept: Bool, by responder: PlayerID, state: inout GameState) throws {
        guard let offer = state.pendingTradeOffers.first(where: { $0.id == offerID }) else {
            throw MoveError.invalidTradeTarget
        }
        guard responder != offer.from else { throw MoveError.invalidTradeTarget }
        guard let proposerIndex = state.players.firstIndex(where: { $0.id == offer.from }),
              let responderIndex = state.players.firstIndex(where: { $0.id == responder }) else {
            throw MoveError.other("unknown player")
        }

        if accept {
            // Re-check both sides' current holdings at acceptance time: the
            // proposer's cards were only validated when the offer was made,
            // and `pendingTradeOffers` survives `endTurn`, so the proposer
            // may have since spent what they offered.
            guard RulesEngine.canAfford(offer.give, player: state.players[proposerIndex]) else {
                throw MoveError.insufficientResources
            }
            guard RulesEngine.canAfford(offer.want, player: state.players[responderIndex]) else {
                throw MoveError.insufficientResources
            }
            for (resource, amount) in offer.give {
                state.players[proposerIndex].resources[resource, default: 0] -= amount
                state.players[responderIndex].resources[resource, default: 0] += amount
            }
            for (resource, amount) in offer.want {
                state.players[responderIndex].resources[resource, default: 0] -= amount
                state.players[proposerIndex].resources[resource, default: 0] += amount
            }
        }

        state.pendingTradeOffers.removeAll { $0.id == offerID }
    }
}
