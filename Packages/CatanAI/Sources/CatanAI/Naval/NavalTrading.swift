import CatanEngine
import Foundation

extension NavalDecisionContext {
    /// Compose bundles that finish an actual purchase instead of being limited
    /// to the engine's single-resource proposal enumeration. Sources remain
    /// surplus AFTER reserving that purchase's ingredients.
    func composedProposals() -> [GameMove] {
        guard canProposeTrade,
              observation.legalMoves.contains(where: { if case .proposeTrade = $0 { true } else { false } }) else {
            return []
        }
        var results: [GameMove] = []
        var seen: Set<GameMove> = []
        for target in purchaseTargets {
            let want = Resource.allCases.reduce(into: [Resource: Int]()) { requested, resource in
                let deficit = max(0, target.cost[resource, default: 0] - me.resources[resource, default: 0])
                if deficit > 0 { requested[resource] = deficit }
            }
            let needed = Resource.allCases.reduce(0) { $0 + want[$1, default: 0] }
            guard (1...2).contains(needed) else { continue }
            let sources = Resource.allCases.filter {
                want[$0] == nil && me.resources[$0, default: 0] > target.cost[$0, default: 0]
            }
            for give in composedPayments(sources: sources, preserving: target.cost) {
                let move = GameMove.proposeTrade(TradeOffer.enumerated(from: seat, give: give, want: want))
                guard seen.insert(move).inserted,
                      !observation.legalMoves.contains(move),
                      RulesEngine.isPermittedComposedProposal(move, by: seat, in: state, legal: observation.legalMoves) else { continue }
                results.append(move)
            }
        }
        return results
    }

    private func composedPayments(sources: [Resource], preserving cost: [Resource: Int]) -> [[Resource: Int]] {
        var results: [[Resource: Int]] = []
        for (index, first) in sources.enumerated() {
            let firstLimit = min(3, me.resources[first, default: 0] - cost[first, default: 0])
            for amount in 1...firstLimit { results.append([first: amount]) }
            for second in sources.dropFirst(index + 1) {
                let secondLimit = min(2, me.resources[second, default: 0] - cost[second, default: 0])
                for firstAmount in 1...min(2, firstLimit) {
                    for secondAmount in 1...secondLimit {
                        results.append([first: firstAmount, second: secondAmount])
                    }
                }
            }
        }
        return results
    }

    func tradeGain(give: [Resource: Int], get: [Resource: Int]) -> Double {
        var after = spending(give, from: me.resources)
        for resource in Resource.allCases { after[resource, default: 0] += get[resource] ?? 0 }
        return inventoryValue(after) - inventoryValue(me.resources) - 0.025
    }

    func acceptanceValue(_ offerID: UUID) -> Double {
        guard let offer = state.pendingTradeOffers.first(where: { $0.id == offerID }) else {
            return Self.negativeScore
        }
        let gain = tradeGain(give: offer.want, get: offer.give)
        guard gain > 0 else { return Self.negativeScore }
        let rivalGift = max(0, rivalTradeBenefit(offer, rival: offer.from, proposing: true))
        let rivalry = tier == .expert ? 0.48 : 0.10 + personality.aggressiveness * 0.12
        return gain - rivalry * rivalGift - (0.06 - personality.tradeWillingness * 0.025)
    }

    func proposalValue(_ offer: TradeOffer) -> Double {
        guard canProposeTrade else { return Self.negativeScore }
        let gain = tradeGain(give: offer.give, get: offer.want)
        guard gain > 0.035 else { return Self.negativeScore }
        let refusals = state.declinedTradeOffersThisTurn[seat] ?? []
        guard !refusals.contains(where: { $0.give == offer.give && $0.want == offer.want }) else {
            return Self.negativeScore
        }
        var best: Double?
        for rival in state.players.sorted(by: { $0.id < $1.id }) where rival.id != seat {
            let belief = ledger.belief(of: rival.id)
            let wanted = Resource.allCases.reduce(0) { $0 + (offer.want[$1] ?? 0) }
            guard belief.maxTotal >= wanted else { continue }
            let benefit = rivalTradeBenefit(offer, rival: rival.id, proposing: false)
            guard benefit > -0.01 else { continue }
            let points = state.publicVictoryPoints(for: rival.id)
            let threat = Double(points) / Double(max(1, state.victoryPointTarget))
            let gift = tier == .expert ? max(0, benefit) * threat * 0.35 : 0
            let score = gain * 0.62 - gift - 0.055
            if best == nil || score > best! { best = score }
        }
        return best ?? Self.negativeScore
    }

    /// Direct Bot/HeuristicPolicy callers may supply the unscoped engine mask.
    /// Honor the session's policy pacing there too, rather than enqueueing the
    /// same negotiation repeatedly while its first answer is still pending.
    var canProposeTrade: Bool {
        !state.pendingTradeOffers.contains { $0.from == seat }
            && (state.declinedTradeOffersThisTurn[seat]?.count ?? 0) < RulesEngine.maxTradeProposalsPerTurn
    }

    /// Beliefs, production and public buildings price the counterparty. No
    /// authoritative composition is consulted, even for a promising exchange.
    func rivalTradeBenefit(_ offer: TradeOffer, rival: PlayerID, proposing: Bool) -> Double {
        let rate = ProductionModel.rate(for: rival, in: state, tiles: tiles)
        let belief = ledger.belief(of: rival)
        let getting = proposing ? offer.want : offer.give
        let paying = proposing ? offer.give : offer.want
        return Resource.allCases.reduce(0.0) { total, resource in
            let known = belief.known[resource] ?? 0
            let needed = known < 2 ? 1.0 : 0.35
            let scarcity = rate[resource] == 0 ? 1.6 : 1
            let unit = 0.13 * needed * scarcity
            return total + Double((getting[resource] ?? 0) - (paying[resource] ?? 0)) * unit
        }
    }
}
