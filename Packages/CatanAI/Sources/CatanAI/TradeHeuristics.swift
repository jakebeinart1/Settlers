import CatanEngine

/// Decides whether to accept a proposed trade, and what trades to propose,
/// by valuing each resource relative to the receiving player's current
/// "closest" build target rather than treating all resources as equal.
public enum TradeHeuristics {
    /// Build targets in priority order, favoring settlements/cities (which
    /// score higher below) over roads/dev cards. `expansionBias` decides
    /// whether a settlement or a city upgrade is this player's likelier
    /// next move.
    private static func buildTargets(
        personality: BotPersonality,
        weights: BotWeights
    ) -> [(cost: [Resource: Int], weight: Double)] {
        let settlement = (Building.settlementCost, weights.tradeTargetSettlementWeight)
        let city = (Building.cityCost, weights.tradeTargetCityWeight)
        let devCard = (Building.devCardCost, weights.tradeTargetDevCardWeight)
        let road = (Building.roadCost, weights.tradeTargetRoadWeight)
        // Cautious bots (low expansionBias) prioritize upgrading to cities;
        // aggressive/balanced bots prioritize planting new settlements.
        return personality.expansionBias >= weights.cityFirstExpansionBiasPivot
            ? [settlement, city, devCard, road]
            : [city, settlement, devCard, road]
    }

    /// Marginal value of one more `resource` card to `player`, based on how
    /// pivotal it is to completing the nearest (fewest total deficit)
    /// build target: a resource that's the *only* thing standing between
    /// this player and a build is worth far more than one they already have
    /// plenty of, or one that isn't blocking anything.
    private static func resourceValue(
        _ resource: Resource,
        for player: Player,
        personality: BotPersonality,
        weights: BotWeights
    ) -> Double {
        var value = 0.0
        for target in buildTargets(personality: personality, weights: weights) {
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

    /// Accepts `offer` if what `receiver` would gain (`offer.give`) clears a
    /// real, meaningfully-positive bar over what they'd give up
    /// (`offer.want`) - the bar shifts with how trade-willing their
    /// personality is (a more reluctant bot demands more), but every
    /// personality requires *some* genuine benefit, not just any margin
    /// above break-even. (A flat `0.5 - tradeWillingness`, clamped only at
    /// `0`, used to mean most personalities accepted literally any
    /// net-positive deal, however razor-thin - "bots accept trades too
    /// easily" - since `tradeWillingness >= 0.5` collapsed the bar straight
    /// to `0`. The `acceptThresholdFloor` weight keeps a floor no
    /// personality's willingness can erase.)
    ///
    /// The threshold also shifts with how threatening `offer.from` is
    /// relative to `receiver`'s other opponents (see `ThreatAssessment`) -
    /// accepting hands them resources, so a proposal from an above-average
    /// threat needs a correspondingly better deal to clear the bar.
    ///
    /// It also shifts with `receiver`'s own standing in the game
    /// (`ThreatAssessment.ownStanding`) - trading is only ever evaluated
    /// with winning in mind, not just "is this deal fair": a bot that's
    /// behind the field has real reason to take a genuinely fair trade to
    /// catch up, so the bar drops a little; a bot with a comfortable lead
    /// has less reason to hand any opponent resources over a merely-okay
    /// deal, since helping someone else catch up costs more than a fair
    /// trade is worth, so the bar rises a little.
    public static func evaluate(
        offer: TradeOffer,
        receiver: PlayerID,
        state: GameState,
        personality: BotPersonality,
        weights: BotWeights = .default
    ) -> Bool {
        guard let receiverPlayer = state.players.first(where: { $0.id == receiver }) else { return false }

        let gainValue = offer.give.reduce(0.0) { partial, entry in
            let unit = resourceValue(entry.key, for: receiverPlayer, personality: personality, weights: weights)
            return partial + unit * Double(entry.value)
        }
        let costValue = offer.want.reduce(0.0) { partial, entry in
            let unit = resourceValue(entry.key, for: receiverPlayer, personality: personality, weights: weights)
            return partial + unit * Double(entry.value)
        }

        let netGain = gainValue - costValue
        let proposerWeight = ThreatAssessment.relativeWeight(for: offer.from, excluding: receiver, in: state, weights: weights)
        let ownStanding = ThreatAssessment.ownStanding(for: receiver, in: state, weights: weights)
        let baseThreshold = max(
            weights.acceptThresholdFloor,
            weights.acceptThresholdBase - personality.tradeWillingness * weights.acceptThresholdWillingnessScale
        )
        let threatShift = (proposerWeight - 1.0) * weights.acceptThreatShiftScale
        let standingShift = (ownStanding - 1.0) * weights.acceptStandingShiftScale

        // A proposer who's already landed one trade this turn and is back
        // shopping for another gets more suspicious with each repeat - a
        // real opponent would notice a partner working the table, not just
        // judge every offer from them in isolation. Resets every turn (see
        // `RulesEngine`'s `.endTurn` handling), so it never carries a grudge
        // past the turn it was earned on.
        let priorAcceptsThisTurn = state.tradesAcceptedThisTurn[offer.from] ?? 0
        let suspicionShift = Double(priorAcceptsThisTurn) * weights.acceptSuspicionShiftPerTrade

        // A deal that would hand the proposer an immediate settlement/city
        // the instant it's accepted deserves real scrutiny beyond "is this
        // good for me" - the previous math only ever valued the receiver's
        // own resource need, so a proposer sitting one card short of a
        // build could complete it via a string of individually-plausible
        // one-for-one trades that nobody weighed against what it was
        // actually handing the opponent.
        let unlockShift = enablesImmediateBuild(offer: offer, state: state) ? weights.acceptUnlockShift : 0.0

        let threshold = max(0, baseThreshold + threatShift + standingShift + suspicionShift + unlockShift)
        return netGain > threshold
    }

    /// Whether accepting `offer` (from the proposer's side: losing `give`,
    /// gaining `want`) would take the proposer from unable to afford a
    /// settlement/city to able to, right now. Only checks the two
    /// high-value builds - a road or dev card slipping through is a much
    /// smaller swing, not worth raising every trade's bar over.
    private static func enablesImmediateBuild(offer: TradeOffer, state: GameState) -> Bool {
        guard let proposer = state.players.first(where: { $0.id == offer.from }) else { return false }

        var resulting = proposer.resources
        for (resource, amount) in offer.give { resulting[resource, default: 0] -= amount }
        for (resource, amount) in offer.want { resulting[resource, default: 0] += amount }

        return [Building.settlementCost, Building.cityCost].contains { cost in
            let currentlyAffordable = cost.allSatisfy { (proposer.resources[$0.key] ?? 0) >= $0.value }
            let becomesAffordable = cost.allSatisfy { (resulting[$0.key] ?? 0) >= $0.value }
            return !currentlyAffordable && becomesAffordable
        }
    }

    /// Proposes at most one trade this turn: if `player` is blocked on their
    /// nearest build target by a shortage of one resource, offers up
    /// whichever card is worth *least* to them right now for one of
    /// whichever resource is scarcest relative to that target - and only if
    /// that's a genuinely self-favorable deal (see the value check below).
    /// Returns `[]` if nothing is blocking (nothing to trade for), there's
    /// no real surplus to give up, or the only surplus available isn't
    /// actually worth less to us than what we'd get back.
    public static func proposeTrades(
        state: GameState,
        player: PlayerID,
        personality: BotPersonality,
        weights: BotWeights = .default
    ) -> [TradeOffer] {
        guard let me = state.players.first(where: { $0.id == player }) else { return [] }
        guard let target = nearestBlockedTarget(personality: personality, holding: me.resources, weights: weights)
        else { return [] }

        guard let mostNeeded = mostNeededResource(for: target, holding: me.resources) else { return [] }

        // Give up whichever resource is worth *least* to us right now (not
        // just whichever we happen to hold the most of - quantity and
        // marginal value aren't the same thing: holding 3 ore isn't
        // "surplus" if ore is what's blocking our next build). Must
        // genuinely be a surplus (more than one card) - `RulesEngine` only
        // ever enumerates `.proposeTrade` as legal for resources held in
        // that quantity, so anything less would never match a legal move.
        //
        // Selected by walking `Resource.allCases` rather than `min(by:)` over
        // the resources dictionary. Two resources frequently tie on value, and
        // `min(by:)` then returns whichever the dictionary happened to iterate
        // first - an order Swift seeds per process, so the same bot in the
        // same position offered a different card on every launch. Comparing
        // against `Resource.allCases` order breaks ties the same way every
        // time, which is what lets a seeded game reproduce move for move.
        let giveCandidates = Resource.allCases.filter { $0 != mostNeeded && (me.resources[$0] ?? 0) > 1 }
        guard let give = giveCandidates.min(by: {
            let (lhs, rhs) = (resourceValue($0, for: me, personality: personality, weights: weights),
                              resourceValue($1, for: me, personality: personality, weights: weights))
            return lhs == rhs ? false : lhs < rhs
        }) else { return [] }

        // Only propose a trade that's clearly in *our own* favor - what
        // we're asking for has to be worth more to us than what we're
        // giving up, using the same value function `evaluate` judges
        // incoming offers by. Without this, a bot could offer away
        // something it actually needs more than what it's asking for,
        // handing the recipient the better end of the deal for no reason.
        guard resourceValue(mostNeeded, for: me, personality: personality, weights: weights)
            > resourceValue(give, for: me, personality: personality, weights: weights) else {
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
        // How much to ask for, and how much to offer.
        //
        // This used to be hardcoded one-for-one, which meant a bot could never
        // express "two ore for a wheat" - and a lopsided offer is most of how
        // Catan is actually negotiated. Widening the enumeration in
        // `RulesEngine` alone changed nothing, because the bot composes its
        // own offer and then matches it against that list; the quantities have
        // to be decided here.
        //
        // Ask for what the target actually needs, up to the enumeration's
        // limit - asking for one card when two are missing just means coming
        // back again. Offer two only when genuinely rich in the give resource:
        // a bot down to its last spare card offering two of them is not
        // generous, it is desperate, and it hands the receiver the better half
        // of a deal it needed to win.
        let deficit = max(0, (target.cost[mostNeeded] ?? 0) - (me.resources[mostNeeded] ?? 0))
        let wantCount = min(max(1, deficit), RulesEngine.maxEnumeratedTradeQuantity)
        let held = me.resources[give] ?? 0
        let generous = held >= weights.generousOfferSurplusThreshold
        let giveCount = min(generous ? 2 : 1, max(1, held - 1), RulesEngine.maxEnumeratedTradeQuantity)

        let giveTable = [give: giveCount]
        let wantTable = [mostNeeded: wantCount]
        let alreadyPending = state.pendingTradeOffers.contains { offer in
            offer.from == player && offer.give == giveTable && offer.want == wantTable
        }
        guard !alreadyPending else { return [] }

        // Content-derived id, matching how `RulesEngine.legalMoves` enumerates
        // the same candidate - so the offer the bot proposes is identical to
        // the legal move it matched against, rather than a fresh random id.
        return [TradeOffer.enumerated(from: player, give: giveTable, want: wantTable)]
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
    public static func bestBankTrade(
        state: GameState,
        player: PlayerID,
        personality: BotPersonality,
        weights: BotWeights = .default
    ) -> (give: Resource, get: Resource, rate: Int)? {
        guard let me = state.players.first(where: { $0.id == player }) else { return nil }
        guard let target = nearestBlockedTarget(personality: personality, holding: me.resources, weights: weights)
        else { return nil }

        guard let mostNeeded = mostNeededResource(for: target, holding: me.resources) else { return nil }

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

    /// The resource `holding` is furthest short of for `target`'s cost, or
    /// `nil` if the target is already affordable.
    ///
    /// Deficits are walked in `Resource.allCases` order rather than by
    /// iterating `target.cost` directly. `cost` is a `[Resource: Int]`
    /// dictionary, so iterating it yields a per-process order, and when two
    /// resources are short by the same amount - which is the common case for
    /// a settlement, needing one each of four resources - `max(by:)` returned
    /// a different winner on every launch. That made the same bot in the same
    /// position ask for a different card run to run, which is enough on its
    /// own to stop a seeded game reproducing.
    ///
    /// Extracted because `proposeTrades` and `bestBankTrade` both derived this
    /// the same way and would otherwise have to be kept in sync by hand.
    private static func mostNeededResource(for target: (cost: [Resource: Int], weight: Double),
                                           holding: [Resource: Int]) -> Resource? {
        var best: (resource: Resource, need: Int)?
        for resource in Resource.allCases {
            let need = (target.cost[resource] ?? 0) - (holding[resource] ?? 0)
            guard need > 0 else { continue }
            if best == nil || need > best!.need { best = (resource, need) }
        }
        return best?.resource
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
    private static func nearestBlockedTarget(
        personality: BotPersonality,
        holding: [Resource: Int],
        weights: BotWeights
    ) -> (cost: [Resource: Int], weight: Double)? {
        buildTargets(personality: personality, weights: weights)
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
