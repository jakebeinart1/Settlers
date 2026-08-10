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
    /// nearest build target by a shortage of one resource, offers a
    /// currently-surplus resource for one card of whichever resource is
    /// scarcest relative to that target. Returns `[]` if nothing is
    /// blocking (nothing to trade for) or there's no surplus to give up.
    public static func proposeTrades(state: GameState, player: PlayerID, personality: BotPersonality) -> [TradeOffer] {
        guard let me = state.players.first(where: { $0.id == player }) else { return [] }

        // The "current build plan" is whichever target has the smallest
        // total deficit - i.e. the one this player is closest to affording.
        guard let target = buildTargets(personality: personality).min(by: { a, b in
            totalDeficit(a.cost, holding: me.resources) < totalDeficit(b.cost, holding: me.resources)
        }) else { return [] }

        let deficits = target.cost.compactMap { resource, amount -> (Resource, Int)? in
            let need = amount - (me.resources[resource] ?? 0)
            return need > 0 ? (resource, need) : nil
        }
        guard let mostNeeded = deficits.max(by: { $0.1 < $1.1 })?.0 else { return [] }

        // Must genuinely be a surplus (more than one card) - `RulesEngine`
        // only ever enumerates `.proposeTrade` as legal for resources held
        // in that quantity, so anything less would never match a legal move.
        guard let give = me.resources.filter({ $0.key != mostNeeded && $0.value > 1 }).max(by: { $0.value < $1.value })?.key else {
            return []
        }

        return [TradeOffer(from: player, give: [give: 1], want: [mostNeeded: 1])]
    }

    private static func totalDeficit(_ cost: [Resource: Int], holding: [Resource: Int]) -> Int {
        cost.reduce(0) { partial, entry in
            let (resource, amount) = entry
            return partial + max(0, amount - (holding[resource] ?? 0))
        }
    }
}
