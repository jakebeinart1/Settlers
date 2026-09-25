import CatanEngine
import Foundation

/// Jake's trade design for Expert, as he set it on 2026-09-15:
///
/// 1. Offer a trade the table would plausibly accept, that helps this turn.
/// 2. If refused, offer a more desperate one.
/// 3. Then more desperate still - only while it still leaves the bot ahead.
///
/// "The bot may not always reach the most desperate trade and might sometimes
/// not offer a trade at all." And it should "know what to request from the
/// table to help it on the turn", while still being free to make a pure-value
/// trade with nothing to build - including lopsided bundles like two brick and
/// two wood for the one wheat that finishes a city.
///
/// ## What replaced what
/// Round three picked, among the engine's single-resource offers, the one
/// best *for itself*. That is the offer least likely to be accepted, so the
/// turn's first ask was its weakest, and escalation only happened because
/// refused offers were filtered out. The cascade inverts the order: the first
/// ask is the least generous offer the table would plausibly take, and each
/// refusal raises the bar.
///
/// ## "Desperation", concretely
/// An offer's appeal is how much its most eager plausible payer's standing
/// rises - the bot's public model of whether someone says yes. The first offer
/// is the lowest appeal above zero; every later one must beat the appeal of
/// everything already refused this turn. The bot's own evaluation must still
/// improve against its worst plausible payer, which is where "benefit the bot
/// more than the other players" lives: the evaluation already charges for
/// helping whoever is closest to winning, and charges nothing for helping a
/// seat that cannot, which is Jake's "three wood for one, when you know that
/// person will not win".
extension EvaluationPolicy {

    /// The proposal the cascade makes now, with this seat's score for it, or
    /// `nil` if no offer both helps the bot and clears everything refused.
    func cascadeProposal(
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator,
        legal: [GameMove]
    ) -> (offer: TradeOffer, score: Double)? {
        let seat = evaluator.seat
        guard legal.contains(where: { if case .proposeTrade = $0 { true } else { false } }),
              let me = state.players.first(where: { $0.id == seat }) else { return nil }

        let valuation = TradeValuation(evaluator: evaluator, state: state, ledger: ledger)
        let payers = PlannerTradeEvaluator(seat: seat)
        let refused = state.declinedTradeOffersThisTurn[seat] ?? []
        let floor = refused.compactMap { appeal(of: $0, payers: payers, valuation: valuation)?.appeal }.max()
        var purchases = PurchaseGains(valuation: valuation)
        let baseline = valuation.standingStill + purchases.gain(with: me.resources)

        var chosen: (offer: TradeOffer, score: Double, appeal: Double)?
        for offer in TradeComposer.offers(from: me) where !refused.contains(where: { $0.sameProposition(as: offer) }) {
            guard let judged = appeal(of: offer, payers: payers, valuation: valuation) else { continue }
            // The ladder forces each refusal to be answered with a more
            // generous offer. `worthIt` drops that: an offer stands on its own
            // worth, and the bar it clears rises with what it gives away.
            if tradeModel == .current, judged.appeal <= (floor ?? -.greatestFiniteMagnitude) { continue }
            let total = judged.worst + purchases.gain(with: me.resources.trading(offer))
            guard total > baseline + requiredGain(for: offer, weights: evaluator.weights) else { continue }
            if isBetter((total, judged.appeal), than: chosen) {
                chosen = (offer, total, judged.appeal)
            }
        }
        guard let chosen,
              legal.contains(.proposeTrade(chosen.offer))
                || RulesEngine.isPermittedComposedProposal(.proposeTrade(chosen.offer), by: seat, in: state, legal: legal)
        else { return nil }
        return (chosen.offer, chosen.score)
    }

    /// How much an offer must gain before it is worth making.
    ///
    /// Under the ladder every beneficial offer qualifies, because the ladder
    /// itself is what stops the bot conceding endlessly. Under `worthIt` there
    /// is no ladder, so the bar does that job: each card handed over raises
    /// what the trade has to be worth. A city finished by giving four cards
    /// clears it easily; a four-card hand-dump for a marginal gain does not.
    private func requiredGain(for offer: TradeOffer, weights: EvaluationWeights) -> Double {
        guard tradeModel == .worthIt else { return weights.tradeMargin }
        let given = Resource.allCases.reduce(0) { $0 + (offer.give[$1] ?? 0) }
        return weights.tradeMargin + Double(given) * weights.concessionPerCard
    }

    /// The best offer for this seat wins; ties go to the offer the table would
    /// like more, and after that to composition order, which is fixed.
    ///
    /// ## Why not "the least generous offer someone would accept"
    /// That was the first shape of this, taken straight from Jake's step one,
    /// and it cost twenty points against the shipping bots: 65.5% to 45.7%
    /// over 624 rotated held-out games. It raised the acceptance rate on the
    /// bot's own offers from 39% to 62% and still lost, because it made 515
    /// offers where the old policy made 1,237, and the number of trades that
    /// actually land is what this policy's strength runs on.
    ///
    /// The flaw was using *our* model of an opponent to decide what they would
    /// accept. The shipping heuristic values cards by its own table and
    /// happily takes offers this evaluation scores as no use to it - and those
    /// are exactly the offers that are best for us. Opening with the offer
    /// this seat likes most keeps the cascade - every refusal still forces a
    /// strictly more appealing offer next - without pre-emptively conceding to
    /// a model of an opponent that is not the opponent.
    private func isBetter(
        _ judged: (worst: Double, appeal: Double),
        than chosen: (offer: TradeOffer, score: Double, appeal: Double)?
    ) -> Bool {
        guard let chosen else { return true }
        if judged.worst != chosen.score { return judged.worst > chosen.score }
        return judged.appeal > chosen.appeal
    }

    /// This seat's worst score over plausible payers, and the best payer gain.
    func appeal(
        of offer: TradeOffer,
        payers: PlannerTradeEvaluator,
        valuation: TradeValuation
    ) -> (worst: Double, appeal: Double)? {
        let candidates = payers.plausiblePayers(of: offer, state: valuation.state, ledger: valuation.ledger)
        let values = candidates.map { valuation.value(of: offer, payer: $0) }
        guard let worst = values.map(\.score).min(), let appeal = values.map(\.payerGain).max() else { return nil }
        return (worst, appeal)
    }
}

/// The offers a hand can make: asks for what a purchase is missing, and
/// single-card asks for pure value, each against every give the hand can
/// spare.
enum TradeComposer {

    /// What a seat might ask for, most useful first.
    ///
    /// For each purchase, exactly the cards it is short - "one wheat short of a
    /// city" asks for one wheat. Then one of each resource, for a trade that
    /// finishes nothing and is still worth making.
    static func wants(for hand: [Resource: Int]) -> [(want: [Resource: Int], keep: [Resource: Int])] {
        var result: [(want: [Resource: Int], keep: [Resource: Int])] = []
        for cost in [Building.cityCost, Building.settlementCost, Building.devCardCost, Building.roadCost] {
            var want: [Resource: Int] = [:]
            var keep: [Resource: Int] = [:]
            for resource in Resource.allCases {
                let needed = cost[resource] ?? 0
                let held = hand[resource] ?? 0
                if needed > held { want[resource] = needed - held }
                if needed > 0 { keep[resource] = min(needed, held) }
            }
            let asked = Resource.allCases.reduce(0) { $0 + (want[$1] ?? 0) }
            if asked > 0, asked <= RulesEngine.maxComposedTradeWant, !result.contains(where: { $0.want == want }) {
                result.append((want, keep))
            }
        }
        // Pure value, and the two-card ask the engine's own enumeration makes.
        // Leaving these out narrowed the offer set below what the policy this
        // replaces could express, which cost more than bundles gained.
        for count in 1...min(2, RulesEngine.maxComposedTradeWant) {
            for resource in Resource.allCases where !result.contains(where: { $0.want == [resource: count] }) {
                result.append(([resource: count], [:]))
            }
        }
        return result
    }

    /// Every give drawn from what `hand` holds beyond `keep`, never including a
    /// resource the offer asks for, from one card up to the composed limit.
    /// Enumerated in `Resource.allCases` order so a seeded game composes the
    /// same offers in every process.
    static func gives(from hand: [Resource: Int], keeping keep: [Resource: Int], excluding want: [Resource: Int])
        -> [[Resource: Int]] {
        let pool = Resource.allCases.map { resource -> (Resource, Int) in
            guard want[resource] == nil else { return (resource, 0) }
            return (resource, max(0, (hand[resource] ?? 0) - (keep[resource] ?? 0)))
        }
        var result: [[Resource: Int]] = []
        func extend(_ index: Int, _ partial: [Resource: Int], _ total: Int) {
            guard index < pool.count else {
                if total > 0 { result.append(partial) }
                return
            }
            let (resource, available) = pool[index]
            for count in 0...min(available, RulesEngine.maxComposedTradeGive - total) {
                var next = partial
                if count > 0 { next[resource] = count }
                extend(index + 1, next, total + count)
            }
        }
        extend(0, [:], 0)
        return result
    }

    /// Every offer `player` could compose, deduplicated by content.
    static func offers(from player: Player) -> [TradeOffer] {
        var seen: Set<UUID> = []
        var result: [TradeOffer] = []
        for (want, keep) in wants(for: player.resources) {
            // Both with and without the cards a purchase is holding back. The
            // reservation is a good default - do not trade away the ore your
            // city needs for the wheat that finishes it - but it is only a
            // default, and a hand with three spare ore should still be able to
            // offer one. Scoring decides; the composer only supplies.
            for reserved in [keep, [:]] {
                for give in gives(from: player.resources, keeping: reserved, excluding: want) {
                    let offer = TradeOffer.enumerated(from: player.id, give: give, want: want)
                    if seen.insert(offer.id).inserted { result.append(offer) }
                }
            }
        }
        return result
    }
}

/// `TradeValuation.bestPurchaseGain`, memoised by hand for one decision.
///
/// Most composed offers leave a hand that buys nothing, and those are answered
/// without building a single position; the rest share hands often enough that
/// each distinct one is priced once.
struct PurchaseGains {
    let valuation: TradeValuation
    private var cache: [[Resource: Int]: Double] = [:]

    init(valuation: TradeValuation) {
        self.valuation = valuation
    }

    mutating func gain(with hand: [Resource: Int]) -> Double {
        let affordsSomething = [Building.cityCost, Building.settlementCost].contains { cost in
            Resource.allCases.allSatisfy { (hand[$0] ?? 0) >= (cost[$0] ?? 0) }
        }
        guard affordsSomething else { return 0 }
        if let known = cache[hand] { return known }
        let gain = valuation.bestPurchaseGain(with: hand)
        cache[hand] = gain
        return gain
    }
}

extension Dictionary where Key == Resource, Value == Int {
    /// This hand after proposing `offer` and having it accepted.
    func trading(_ offer: TradeOffer) -> [Resource: Int] {
        var hand = self
        for resource in Resource.allCases {
            let after = (hand[resource] ?? 0) - (offer.give[resource] ?? 0) + (offer.want[resource] ?? 0)
            hand[resource] = after > 0 ? after : nil
        }
        return hand
    }
}

extension TradeOffer {
    /// The same trade, however each was built. Ids differ between an offer a
    /// person made and one the composer regenerated; content does not.
    func sameProposition(as other: TradeOffer) -> Bool {
        from == other.from && give == other.give && want == other.want
    }
}
