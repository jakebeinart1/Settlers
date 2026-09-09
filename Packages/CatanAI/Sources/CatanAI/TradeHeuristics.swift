import CatanEngine

/// Decides whether to accept a proposed trade, and what trades to propose,
/// by valuing each resource relative to the receiving player's current
/// "closest" build target rather than treating all resources as equal.
public enum TradeHeuristics {
    private struct BuildTarget {
        let name: String
        let cost: [Resource: Int]
        let weight: Double
    }

    /// Build targets in priority order, favoring settlements/cities (which
    /// score higher below) over roads/dev cards. `expansionBias` decides
    /// whether a settlement or a city upgrade is this player's likelier
    /// next move.
    private static func buildTargets(
        personality: BotPersonality,
        weights: BotWeights
    ) -> [BuildTarget] {
        let settlement = BuildTarget(name: "settlement", cost: Building.settlementCost, weight: weights.tradeTargetSettlementWeight)
        let city = BuildTarget(name: "city", cost: Building.cityCost, weight: weights.tradeTargetCityWeight)
        let devCard = BuildTarget(name: "devCard", cost: Building.devCardCost, weight: weights.tradeTargetDevCardWeight)
        let road = BuildTarget(name: "road", cost: Building.roadCost, weight: weights.tradeTargetRoadWeight)
        // Cautious bots (low expansionBias) prioritize upgrading to cities;
        // aggressive/balanced bots prioritize planting new settlements.
        return personality.expansionBias >= weights.cityFirstExpansionBiasPivot
            ? [settlement, city, devCard, road]
            : [city, settlement, devCard, road]
    }

    /// Experimental, uncalibrated inventory potential for joint trade accounting.
    /// The fixed factor two makes one-card-short completion earn the target's
    /// weight. This is not legal-build availability: board, pieces, deck and
    /// future play are deliberately absent. Baseline scoring never calls it.
    static func jointTargetPotential(holding: [Resource: Int], cost: [Resource: Int], weight: Double) -> Double {
        let missing = Resource.allCases.reduce(0) { total, resource in
            total + max(0, cost[resource, default: 0] - holding[resource, default: 0])
        }
        return 2 * weight / (1 + Double(missing))
    }

    /// Reuse native targets and match the offline formula's alphabetical
    /// target order and per-target subtraction; subtracting large aggregate
    /// potentials can round differently at an acceptance threshold.
    static func jointInventoryDelta(
        before: [Resource: Int], after: [Resource: Int],
        personality: BotPersonality, weights: BotWeights = .default
    ) -> Double {
        buildTargets(personality: personality, weights: weights).sorted { $0.name < $1.name }.reduce(0.0) { delta, target in
            let beforeValue = jointTargetPotential(holding: before, cost: target.cost, weight: target.weight)
            let afterValue = jointTargetPotential(holding: after, cost: target.cost, weight: target.weight)
            return delta + (afterValue - beforeValue)
        }
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
        var targets: [TradeTargetContribution]?
        return resourceValue(resource, for: player, personality: personality, weights: weights, targets: &targets)
    }

    /// Shares the numeric path with ordinary scoring. A nil collector skips
    /// target allocation and the extra deficit work for zero-valued targets.
    private static func resourceValue(
        _ resource: Resource, for player: Player, personality: BotPersonality,
        weights: BotWeights, targets: inout [TradeTargetContribution]?
    ) -> Double {
        var value = 0.0
        for target in buildTargets(personality: personality, weights: weights) {
            let needed = target.cost[resource] ?? 0
            let have = player.resources[resource] ?? 0
            let deficit = max(0, needed - have)
            let contributes = needed > 0 && deficit > 0
            guard contributes || targets != nil else { continue }

            let otherDeficits = target.cost.reduce(0) { partial, entry in
                let (otherResource, otherAmount) = entry
                guard otherResource != resource else { return partial }
                return partial + max(0, otherAmount - (player.resources[otherResource] ?? 0))
            }
            // The fewer other resources still block this target, the more
            // pivotal this one is to completing it right now.
            var contribution = 0.0
            if contributes {
                let closeness = 1.0 / (1.0 + Double(otherDeficits))
                contribution = target.weight * closeness
                value += contribution
            }
            targets?.append(TradeTargetContribution(
                targetName: target.name, held: have, required: needed, deficit: deficit,
                otherDeficits: otherDeficits, weight: target.weight, contribution: contribution
            ))
        }
        return value
    }

    /// Records terms while reducing, never sorts or reconstructs the scalar
    /// from diagnostic data. Optional chaining avoids building components
    /// (including their target arrays) on the default evaluation path.
    private static func resourceTotal(
        _ resources: [Resource: Int], direction: TradeResourceContribution.Direction,
        for player: Player, personality: BotPersonality, weights: BotWeights,
        contributions: inout [TradeResourceContribution]?
    ) -> Double {
        resources.reduce(0.0) { partial, entry in
            var targets: [TradeTargetContribution]? = contributions == nil ? nil : []
            let unit = resourceValue(entry.key, for: player, personality: personality, weights: weights, targets: &targets)
            let total = unit * Double(entry.value)
            contributions?.append(TradeResourceContribution(
                resource: entry.key, quantity: entry.value, direction: direction,
                unitValue: unit, totalValue: total, targets: targets!
            ))
            return partial + total
        }
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
        assessment(offer: offer, receiver: receiver, state: state, personality: personality, weights: weights)?.accepted ?? false
    }

    /// Pure acceptance scoring shared with `evaluate`; returns `nil` only
    /// when the receiver is absent. Captures the actual intermediate scalars
    /// without re-evaluating policy or changing the existing arithmetic order.
    /// Offer dictionary reductions deliberately retain their original order.
    /// `includeContributions` adds per-resource/target details only when
    /// requested by diagnostics; ordinary evaluation avoids those allocations.
    public static func assessment(
        offer: TradeOffer,
        receiver: PlayerID,
        state: GameState,
        personality: BotPersonality,
        weights: BotWeights = .default,
        includeContributions: Bool = false
    ) -> TradeAssessment? {
        guard let receiverPlayer = state.players.first(where: { $0.id == receiver }) else { return nil }

        var contributions: [TradeResourceContribution]? = includeContributions ? [] : nil
        let gainValue = resourceTotal(
            offer.give, direction: .gain, for: receiverPlayer, personality: personality, weights: weights,
            contributions: &contributions
        )
        let costValue = resourceTotal(
            offer.want, direction: .cost, for: receiverPlayer, personality: personality, weights: weights,
            contributions: &contributions
        )

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

        // A deal that would newly cover the proposer's settlement/city cost
        // deserves real scrutiny beyond "is this good for me" - the
        // previous math only ever valued the receiver's
        // own resource need, so a proposer sitting one card short of a
        // build could complete it via a string of individually-plausible
        // one-for-one trades that nobody weighed against what it was
        // actually handing the opponent.
        let unlockShift = enablesImmediateBuild(offer: offer, state: state) ? weights.acceptUnlockShift : 0.0

        let threshold = max(0, baseThreshold + threatShift + standingShift + suspicionShift + unlockShift)
        return TradeAssessment(
            offer: offer, receiver: receiver, gainValue: gainValue, costValue: costValue, netGain: netGain,
            baseThreshold: baseThreshold, threatShift: threatShift, standingShift: standingShift,
            suspicionShift: suspicionShift, unlockShift: unlockShift, threshold: threshold, accepted: netGain > threshold,
            resourceContributions: contributions
        )
    }

    /// Whether accepting `offer` (from the proposer's side: losing `give`,
    /// gaining `want`) would newly cover a settlement/city resource cost.
    /// Does not check legal placement, remaining pieces, or victory. Only
    /// checks the two high-value builds - a road or dev card slipping through is a much
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
    /// `pendingTradeOffers` this turn (`ordinaryOffer`). Once every ordinary
    /// candidate for the two highest-value targets (settlement/city) has been
    /// declined, it escalates quantity via `generousUnlockOffer`. Gives up
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
        let requested = (resource: mostNeeded, count: wantCount)

        let rankedGive = rankedGiveCandidates(excluding: mostNeeded, belowValue: wantValue, for: me,
                                               personality: personality, weights: weights)

        if let ordinary = ordinaryOffer(rankedGive: rankedGive, requested: requested, player: player,
                                         me: me, state: state, declined: declined, weights: weights) {
            return [ordinary]
        }
        guard target.cost == Building.settlementCost || target.cost == Building.cityCost,
              let generous = generousUnlockOffer(rankedGive: rankedGive, requested: requested, player: player,
                                                  me: me, state: state, declined: declined, weights: weights)
        else { return [] }
        return [generous]
    }

    /// Every give resource that's a genuine surplus (more than one card) AND
    /// genuinely worth less to us than what we're asking for - the same
    /// self-favorable bar this always enforced, just applied per-candidate
    /// instead of to one pre-chosen resource, so a retry can rank past the
    /// first candidate instead of only ever considering it. Sorted cheapest-
    /// to-us first; `Resource.allCases` breaks ties the same way every time
    /// (see the file-level note on why `min(by:)` over a dictionary wasn't
    /// safe here).
    private static func rankedGiveCandidates(
        excluding mostNeeded: Resource,
        belowValue wantValue: Double,
        for me: Player,
        personality: BotPersonality,
        weights: BotWeights
    ) -> [Resource] {
        Resource.allCases
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
    }

    /// Whether `give`/`giveCount` for `want`/`wantCount` from `player` hasn't
    /// already been proposed-and-declined or isn't already sitting in
    /// `pendingTradeOffers` this turn - shared by both the ordinary and
    /// generous-unlock passes so neither regenerates a rejected offer.
    private static func untried(
        give: Resource, giveCount: Int, want: Resource, wantCount: Int,
        player: PlayerID, state: GameState, declined: [TradeOffer]
    ) -> TradeOffer? {
        let giveTable = [give: giveCount]
        let wantTable = [want: wantCount]
        let alreadyTried = declined.contains { $0.give == giveTable && $0.want == wantTable }
            || state.pendingTradeOffers.contains { $0.from == player && $0.give == giveTable && $0.want == wantTable }
        return alreadyTried ? nil : TradeOffer.enumerated(from: player, give: giveTable, want: wantTable)
    }

    /// Ordinary pass: walk ranked candidates at the usual 1-2 card quantity -
    /// unchanged from before, just no longer limited to a single pre-chosen
    /// candidate, so a decline can move to the next-cheapest resource instead
    /// of regenerating the same offer forever.
    private static func ordinaryOffer(
        rankedGive: [Resource], requested: (resource: Resource, count: Int),
        player: PlayerID, me: Player, state: GameState, declined: [TradeOffer], weights: BotWeights
    ) -> TradeOffer? {
        for give in rankedGive {
            let giveCount = ordinaryGiveCount(for: give, me: me, weights: weights)
            if let offer = untried(give: give, giveCount: giveCount,
                                    want: requested.resource, wantCount: requested.count,
                                    player: player, state: state, declined: declined) {
                return offer
            }
        }
        return nil
    }

    /// The give quantity the ordinary pass would use for `give`, at whatever
    /// `me` currently holds - factored out of `ordinaryOffer` so
    /// `generousUnlockOffer` can compare its own escalated quantity against
    /// this and refuse to "escalate" to something no better (see the
    /// `giveCount > ordinary` guard there, and the design-doc incident this
    /// closes: a 2:1-port bot's escalation ceiling collapsed *below* the
    /// ordinary quantity, offering a strictly worse re-ask that could only
    /// ever be declined again).
    private static func ordinaryGiveCount(for give: Resource, me: Player, weights: BotWeights) -> Int {
        let held = me.resources[give] ?? 0
        let generous = held >= weights.generousOfferSurplusThreshold
        return min(generous ? 2 : 1, max(1, held - 1), RulesEngine.maxEnumeratedTradeQuantity)
    }

    /// Generous-unlock pass: every ordinary candidate for this target has
    /// already been proposed-and-declined this turn. For the two highest-
    /// value targets only (settlement/city - same scope
    /// `enablesImmediateBuild` uses elsewhere in this file), escalate
    /// quantity - not favorability, which every candidate above already
    /// cleared - up to one card better than this bot's own best bank/port
    /// rate for the cheapest candidate. See the design doc for why this
    /// bound, not "uncapped": `Trading.bestRate` is the ceiling a rational
    /// bot would never trade a *player* worse than, since the bank always
    /// says yes.
    ///
    /// Three guards keep this from firing when it shouldn't:
    /// - `declined` must be non-empty: an ordinary offer can also return
    ///   `nil` merely because it's already sitting un-answered in
    ///   `pendingTradeOffers` (nobody has rejected it yet), and that case
    ///   must stay silent, not escalate - retrying is only for a genuine
    ///   decline, never for "still waiting to hear back."
    /// - The reserve is `held`, not `held - 1`: unlike the ordinary pass
    ///   (which keeps one card of a resource it might still want), the give
    ///   resource here is one `rankedGive`'s value filter already proved the
    ///   target doesn't need at all, so there's no reason to keep a reserve
    ///   of it - offering literally all of it is the point (the bot sitting
    ///   on exactly 3 ore for a 1-lumber settlement should offer all 3, not
    ///   2, per `TODO.md`).
    /// - `giveCount` must exceed what the ordinary pass would have offered
    ///   for this same resource, or this pass isn't "generous" at all - with
    ///   a 2:1 port, `bestRate - 1 == 1`, which is *less* than the ordinary
    ///   offer's own 2, and re-asking for less after a decline is guaranteed
    ///   to be declined again for no better reason. When escalating can't
    ///   improve on the ordinary ask, this returns `nil` (no escalation)
    ///   rather than a worse one.
    private static func generousUnlockOffer(
        rankedGive: [Resource], requested: (resource: Resource, count: Int),
        player: PlayerID, me: Player, state: GameState, declined: [TradeOffer], weights: BotWeights
    ) -> TradeOffer? {
        guard !declined.isEmpty, let cheapest = rankedGive.first else { return nil }
        let held = me.resources[cheapest] ?? 0
        let ceiling = max(0, Trading.bestRate(for: cheapest, player: player, state: state) - 1)
        let giveCount = min(ceiling, held)
        let ordinaryCount = ordinaryGiveCount(for: cheapest, me: me, weights: weights)
        guard giveCount > ordinaryCount else { return nil }
        return untried(give: cheapest, giveCount: giveCount,
                       want: requested.resource, wantCount: requested.count,
                       player: player, state: state, declined: declined)
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
    private static func mostNeededResource(for target: BuildTarget,
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
    ) -> BuildTarget? {
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
