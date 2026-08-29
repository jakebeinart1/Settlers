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
    /// Why `give` → `get` is not a legal bank trade for `player`, or `nil` if
    /// it is legal. Pure - it reads state and decides nothing else.
    ///
    /// ## Why this is separate from `bankTrade`
    /// The trade popup used to mirror this rule with its own copy of the
    /// ratio arithmetic in order to decide whether to enable the "Trade with
    /// Bank" button. The copy checked the rates but **not whether the bank
    /// still held the requested resource**, so with a depleted bank the
    /// button went gold, the hint read "Ready to trade", and the tap came
    /// back "You don't have enough resources for that" - which is a lie
    /// about whose resources are missing, and reads as the button being
    /// broken. (That is the bug reported against commit `8add51f`, which
    /// shipped a QA hook after testing only a full-bank 4:1 trade.) Resources
    /// genuinely run out once cities are producing, so it is not exotic.
    ///
    /// Exposing the engine's own answer means the button and the move can no
    /// longer disagree, and the caller gets an error specific enough to
    /// explain itself.
    public static func bankTradeProblem(give: [Resource: Int],
                                        get: [Resource: Int],
                                        by player: PlayerID,
                                        state: GameState) -> MoveError? {
        guard let playerIndex = state.players.firstIndex(where: { $0.id == player }) else {
            return .other("unknown player")
        }
        // Every entry must be a strictly-positive count of an actual
        // exchange - zero/negative amounts would let the `-=`/`+=` in
        // `bankTrade` run backwards and mint or steal resources for free.
        guard give.values.allSatisfy({ $0 > 0 }), get.values.allSatisfy({ $0 > 0 }) else {
            return .illegalPlacement
        }
        let giveTotal = give.values.reduce(0, +)
        let getTotal = get.values.reduce(0, +)
        guard giveTotal > 0, getTotal > 0 else { return .illegalPlacement }

        // Trading a resource for itself is always a strict loss and is never
        // something a player means to do, but the rate arithmetic alone
        // happily accepts it (8 brick for 2 brick balances at 4:1).
        guard Set(give.keys).isDisjoint(with: get.keys) else { return .illegalPlacement }

        // Each given resource must be offered in a quantity that's a whole
        // multiple of its own best rate, and the total given must convert to
        // exactly the total requested at those rates.
        var convertedTotal = 0
        for (resource, amount) in give {
            let rate = bestRate(for: resource, player: player, state: state)
            guard amount % rate == 0 else { return .illegalPlacement }
            convertedTotal += amount / rate
        }
        guard convertedTotal == getTotal else { return .illegalPlacement }

        guard RulesEngine.canAfford(give, player: state.players[playerIndex]) else {
            return .insufficientResources
        }
        for resource in Resource.allCases where (get[resource] ?? 0) > 0 {
            guard (state.bank[resource] ?? 0) >= (get[resource] ?? 0) else {
                return .bankCannotSupply(resource)
            }
        }
        return nil
    }

    public static func bankTrade(give: [Resource: Int], get: [Resource: Int], by player: PlayerID, state: inout GameState) throws {
        if let problem = bankTradeProblem(give: give, get: get, by: player, state: state) {
            throw problem
        }
        let playerIndex = state.players.firstIndex(where: { $0.id == player })!

        for (resource, amount) in give {
            state.players[playerIndex].resources[resource, default: 0] -= amount
            state.bank[resource, default: 0] += amount
        }
        for (resource, amount) in get {
            state.players[playerIndex].resources[resource, default: 0] += amount
            state.bank[resource, default: 0] -= amount
        }
    }

    /// Whether both sides can still honour `offer` right now.
    ///
    /// Either side may have spent or traded the cards since the offer was
    /// made, so an offer that was legal when proposed can stop being so
    /// without anyone responding to it. `respond` re-validates the same two
    /// conditions and throws otherwise, and `RulesEngine.legalMoves` gates on
    /// them - so any UI deciding whether to still show an offer has to agree
    /// with this, and should ask rather than re-deriving it.
    public static func bothSidesCanHonour(_ offer: TradeOffer, responder: PlayerID, state: GameState) -> Bool {
        guard let proposer = state.players.first(where: { $0.id == offer.from }),
              let responderPlayer = state.players.first(where: { $0.id == responder })
        else { return false }
        return RulesEngine.canAfford(offer.want, player: responderPlayer)
            && RulesEngine.canAfford(offer.give, player: proposer)
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
            state.tradesAcceptedThisTurn[offer.from, default: 0] += 1
        }

        state.pendingTradeOffers.removeAll { $0.id == offerID }
    }
}
