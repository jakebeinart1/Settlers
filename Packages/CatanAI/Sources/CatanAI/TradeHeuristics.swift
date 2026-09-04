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
    /// nearest build target by a shortage of one resource, ranks every
    /// genuinely self-favorable give candidate (worth less to us than what
    /// we're asking for) cheapest-first and returns the first one that
    /// hasn't already been proposed-and-declined or isn't already sitting in
    /// `pendingTradeOffers` this turn. Once every ordinary candidate for the
    /// two highest-value targets (settlement/city) has been declined, it
    /// escalates quantity - not favorability - up to one card better than
    /// this bot's own best bank/port rate, on the theory that a genuinely
    /// generous offer might land where a merely-fair one didn't. Gives up
    /// entirely, returning `[]`, once `RulesEngine.maxTradeProposalsPerTurn`
    /// proposals have already been declined this turn - a bot that's been
    /// turned down that many times has exhausted its options for now rather
    /// than looping forever regenerating the same handful of candidates.
    public static func proposeTrades(
        state: GameState,
        player: PlayerID,
        personality: BotPersonality,
        weights: BotWeights = .default
    ) -> [TradeOffer] {
        guard let me = state.players.first(where: { $0.id == player }) else { return [] }
        let declined = state.declinedTradeOffersThisTurn[player] ?? []
        guard declined.count < RulesEngine.maxTradeProposalsPerTurn else { return [] }

        guard let target = nearestBlockedTarget(personality: personality, holding: me.resources, weights: weights)
        else { return [] }
        guard let mostNeeded = mostNeededResource(for: target, holding: me.resources) else { return [] }
        let wantValue = resourceValue(mostNeeded, for: me, personality: personality, weights: weights)

        let deficit = max(0, (target.cost[mostNeeded] ?? 0) - (me.resources[mostNeeded] ?? 0))
        let wantCount = min(max(1, deficit), RulesEngine.maxEnumeratedTradeQuantity)

        // Every give resource that's a genuine surplus (more than one card) AND
        // genuinely worth less to us than what we're asking for - the same
        // self-favorable bar this always enforced, just applied per-candidate
        // instead of to one pre-chosen resource, so a retry can rank past the
        // first candidate instead of only ever considering it. Sorted cheapest-
        // to-us first; `Resource.allCases` breaks ties the same way every time
        // (see the file-level note on why `min(by:)` over a dictionary wasn't
        // safe here).
        let rankedGive = Resource.allCases
            .filter {
                $0 != mostNeeded && (me.resources[$0] ?? 0) > 1
                    && resourceValue($0, for: me, personality: personality, weights: weights) < wantValue
            }
            .sorted {
                let (lhs, rhs) = (resourceValue($0, for: me, personality: personality, weights: weights),
                                   resourceValue($1, for: me, personality: personality, weights: weights))
                return lhs == rhs ? Resource.allCases.firstIndex(of: $0)! < Resource.allCases.firstIndex(of: $1)!
                                  : lhs < rhs
            }

        func untried(give: Resource, giveCount: Int) -> TradeOffer? {
            let giveTable = [give: giveCount]
            let wantTable = [mostNeeded: wantCount]
            let alreadyTried = declined.contains { $0.give == giveTable && $0.want == wantTable }
                || state.pendingTradeOffers.contains { $0.from == player && $0.give == giveTable && $0.want == wantTable }
            return alreadyTried ? nil : TradeOffer.enumerated(from: player, give: giveTable, want: wantTable)
        }

        // Ordinary pass: walk ranked candidates at the usual 1-2 card quantity -
        // unchanged from before, just no longer limited to a single pre-chosen
        // candidate, so a decline can move to the next-cheapest resource instead
        // of regenerating the same offer forever.
        for give in rankedGive {
            let held = me.resources[give] ?? 0
            let generous = held >= weights.generousOfferSurplusThreshold
            let giveCount = min(generous ? 2 : 1, max(1, held - 1), RulesEngine.maxEnumeratedTradeQuantity)
            if let offer = untried(give: give, giveCount: giveCount) { return [offer] }
        }

        // Generous-unlock pass: every ordinary candidate for this target has
        // already been proposed-and-declined this turn. For the two highest-
        // value targets only (settlement/city - same scope
        // `enablesImmediateBuild` uses elsewhere in this file), escalate
        // quantity - not favorability, which every candidate above already
        // cleared - up to one card better than this bot's own best bank/port
        // rate for the cheapest candidate. See the design doc for why this
        // bound, not "uncapped": `Trading.bestRate` is the ceiling a rational
        // bot would never trade a *player* worse than, since the bank always
        // says yes.
        guard target.cost == Building.settlementCost || target.cost == Building.cityCost,
              let cheapest = rankedGive.first else { return [] }
        let held = me.resources[cheapest] ?? 0
        let ceiling = max(0, Trading.bestRate(for: cheapest, player: player, state: state) - 1)
        let giveCount = min(ceiling, max(1, held - 1))
        guard giveCount > 0, let offer = untried(give: cheapest, giveCount: giveCount) else { return [] }
        return [offer]
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
