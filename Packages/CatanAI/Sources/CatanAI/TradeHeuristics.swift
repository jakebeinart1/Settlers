import CatanEngine

/// Decides whether to accept a proposed trade, and what trades to propose,
/// by valuing each resource relative to the receiving player's current
/// "closest" build target rather than treating all resources as equal.
public enum TradeHeuristics {
    /// Build targets in priority order, favoring settlements/cities (which
    /// score higher below) over roads/dev cards. `expansionBias` decides
    /// whether a settlement or a city upgrade is this player's likelier
    /// next move.
    private static func buildTargets(personality: BotPersonality) -> [(cost: [Resource: Int], weight: Double)] {
        let settlement = (Building.settlementCost, 3.0)
        let city = (Building.cityCost, 2.5)
        let devCard = (Building.devCardCost, 1.5)
        let road = (Building.roadCost, 1.0)
        // Cautious bots (low expansionBias) prioritize upgrading to cities;
        // aggressive/balanced bots prioritize planting new settlements.
        return personality.expansionBias >= 0.5
            ? [settlement, city, devCard, road]
            : [city, settlement, devCard, road]
    }

    /// Marginal value of one more `resource` card to `player`, based on how
    /// pivotal it is to completing the nearest (fewest total deficit)
    /// build target: a resource that's the *only* thing standing between
    /// this player and a build is worth far more than one they already have
    /// plenty of, or one that isn't blocking anything.
    private static func resourceValue(_ resource: Resource, for player: Player, personality: BotPersonality) -> Double {
        var value = 0.0
        for target in buildTargets(personality: personality) {
            guard let needed = target.cost[resource], needed > 0 else { continue }
            let have = player.resources[resource] ?? 0
            let deficit = max(0, needed - have)
            guard deficit > 0 else { continue }

            let otherDeficits = target.cost.reduce(0) { partial, entry in
                let (otherResource, otherAmount) = entry
                guard otherResource != resource else { return partial }
                return partial + max(0, otherAmount - (player.resources[otherResource] ?? 0))
            }
            // The fewer other resources still block this target, the more
            // pivotal this one is to completing it right now.
            let closeness = 1.0 / (1.0 + Double(otherDeficits))
            value += target.weight * closeness
        }
        return value
    }

    /// Accepts `offer` if what `receiver` would gain (`offer.give`) is worth
    /// more to their current build plan than what they'd give up
    /// (`offer.want`), with the bar lowered the more trade-willing their
    /// personality is (a very willing bot accepts even a mild net loss; a
    /// reluctant one demands a clear net gain).
    public static func evaluate(offer: TradeOffer, receiver: PlayerID, state: GameState, personality: BotPersonality) -> Bool {
        guard let receiverPlayer = state.players.first(where: { $0.id == receiver }) else { return false }

        let gainValue = offer.give.reduce(0.0) { partial, entry in
            partial + resourceValue(entry.key, for: receiverPlayer, personality: personality) * Double(entry.value)
        }
        let costValue = offer.want.reduce(0.0) { partial, entry in
            partial + resourceValue(entry.key, for: receiverPlayer, personality: personality) * Double(entry.value)
        }

        let netGain = gainValue - costValue
        let threshold = 0.5 - personality.tradeWillingness
        return netGain > threshold
    }

    /// Proposes at most one trade this turn: if `player` is blocked on their
    /// nearest build target by a shortage of one resource, offers up
    /// whichever card is worth *least* to them right now for one of
    /// whichever resource is scarcest relative to that target - and only if
    /// that's a genuinely self-favorable deal (see the value check below).
    /// Returns `[]` if nothing is blocking (nothing to trade for), there's
    /// no real surplus to give up, or the only surplus available isn't
    /// actually worth less to us than what we'd get back.
    public static func proposeTrades(state: GameState, player: PlayerID, personality: BotPersonality) -> [TradeOffer] {
        guard let me = state.players.first(where: { $0.id == player }) else { return [] }
        guard let target = nearestBlockedTarget(personality: personality, holding: me.resources) else { return [] }

        let deficits = target.cost.compactMap { resource, amount -> (Resource, Int)? in
            let need = amount - (me.resources[resource] ?? 0)
            return need > 0 ? (resource, need) : nil
        }
        guard let mostNeeded = deficits.max(by: { $0.1 < $1.1 })?.0 else { return [] }

        // Give up whichever resource is worth *least* to us right now (not
        // just whichever we happen to hold the most of - quantity and
        // marginal value aren't the same thing: holding 3 ore isn't
        // "surplus" if ore is what's blocking our next build). Must
        // genuinely be a surplus (more than one card) - `RulesEngine` only
        // ever enumerates `.proposeTrade` as legal for resources held in
        // that quantity, so anything less would never match a legal move.
        guard let give = me.resources
            .filter({ $0.key != mostNeeded && $0.value > 1 })
            .min(by: { resourceValue($0.key, for: me, personality: personality) < resourceValue($1.key, for: me, personality: personality) })?
            .key
        else { return [] }

        // Only propose a trade that's clearly in *our own* favor - what
        // we're asking for has to be worth more to us than what we're
        // giving up, using the same value function `evaluate` judges
        // incoming offers by. Without this, a bot could offer away
        // something it actually needs more than what it's asking for,
        // handing the recipient the better end of the deal for no reason.
        guard resourceValue(mostNeeded, for: me, personality: personality) > resourceValue(give, for: me, personality: personality) else {
            return []
        }

        // Don't re-propose an offer that's functionally identical to one of
        // this player's own offers still sitting in `pendingTradeOffers`.
        // Nothing removes a pending offer except an explicit accept/reject
        // response (`Trading.respond`) - it survives `endTurn` - and as long
        // as `me.resources`/the build target haven't changed, this method
        // would otherwise keep generating a "new" offer (fresh `UUID`, same
        // give/want) forever: once every other bot has already declined to
        // accept it, nothing else in this state ever changes to make them
        // reconsider. That both starves `Bot.decideMainTurn` into never
        // reaching `.endTurn` on its own (see `GameViewModel
        // .runBotTurnIfNeeded`'s `sameBotActionCap` backstop) and piles up
        // unbounded duplicate offers in persisted `GameState`.
        let give1 = [give: 1]
        let want1 = [mostNeeded: 1]
        let alreadyPending = state.pendingTradeOffers.contains { offer in
            offer.from == player && offer.give == give1 && offer.want == want1
        }
        guard !alreadyPending else { return [] }

        return [TradeOffer(from: player, give: give1, want: want1)]
    }

    /// A one-shot bank/port trade that would help `player`'s current
    /// nearest build target, if a good one exists - bots previously only
    /// ever traded with other players; a real player would readily fall
    /// back to the bank (or a port) to unblock a build when no one else
    /// offers a good deal, so this gives bots the same option. Gives up
    /// whichever *other* resource `player` holds the largest surplus of
    /// (and doesn't itself still owe toward this same target), at
    /// whatever rate `Trading.bestRate` gets them (2:1/3:1 port, or 4:1
    /// with no port) - never a resource this target still needs.
    public static func bestBankTrade(state: GameState, player: PlayerID, personality: BotPersonality) -> (give: Resource, get: Resource, rate: Int)? {
        guard let me = state.players.first(where: { $0.id == player }) else { return nil }
        guard let target = nearestBlockedTarget(personality: personality, holding: me.resources) else { return nil }

        let deficits = target.cost.compactMap { resource, amount -> (Resource, Int)? in
            let need = amount - (me.resources[resource] ?? 0)
            return need > 0 ? (resource, need) : nil
        }
        guard let mostNeeded = deficits.max(by: { $0.1 < $1.1 })?.0 else { return nil }

        let candidates = Resource.allCases
            .filter { $0 != mostNeeded && (target.cost[$0] ?? 0) <= (me.resources[$0] ?? 0) }
            .compactMap { resource -> (resource: Resource, rate: Int)? in
                let rate = Trading.bestRate(for: resource, player: player, state: state)
                guard (me.resources[resource] ?? 0) >= rate else { return nil }
                return (resource, rate)
            }

        guard let best = candidates.max(by: { (me.resources[$0.resource] ?? 0) < (me.resources[$1.resource] ?? 0) }) else { return nil }
        return (give: best.resource, get: mostNeeded, rate: best.rate)
    }

    /// The build target `proposeTrades`/`bestBankTrade` should be trading
    /// toward: whichever target has the smallest total deficit *among
    /// those still actually missing something*. Excluding already-
    /// affordable targets matters: without it, an already-affordable cheap
    /// target (a road needing nothing further) has a deficit of zero and
    /// would win outright over a settlement genuinely blocked by one
    /// missing card, even though the settlement is the real thing worth
    /// trading for - `BuildPlanner`/`RulesEngine.legalMoves` already offer
    /// the affordable target directly, so trading logic has nothing useful
    /// to add there.
    private static func nearestBlockedTarget(personality: BotPersonality, holding: [Resource: Int]) -> (cost: [Resource: Int], weight: Double)? {
        buildTargets(personality: personality)
            .filter { totalDeficit($0.cost, holding: holding) > 0 }
            .min { totalDeficit($0.cost, holding: holding) < totalDeficit($1.cost, holding: holding) }
    }

    private static func totalDeficit(_ cost: [Resource: Int], holding: [Resource: Int]) -> Int {
        cost.reduce(0) { partial, entry in
            let (resource, amount) = entry
            return partial + max(0, amount - (holding[resource] ?? 0))
        }
    }
}
