import CatanEngine

/// Generates the successors of a route node, and prices each one.
///
/// Shared by both planners so that the exact oracle and the beam search are
/// searching the *same* graph. If they expanded differently, the oracle would
/// not be testing the beam - it would be testing a second implementation, and
/// agreement between them would mean nothing.
public struct RouteExpansion: Sendable {
    public let context: RouteContext
    /// The seat's hand at the moment planning began.
    public let startingHand: [Resource: Double]

    public init(context: RouteContext, startingHand: [Resource: Double]) {
        self.context = context
        self.startingHand = startingHand
    }

    /// Every purchase legal from `node`, with the expected turns each costs.
    ///
    /// Enumerated over `RoutePurchase.allCases`, which is a fixed order, so the
    /// successor list is a pure function of the node.
    public func successors(of node: RouteNode) -> [(purchase: RoutePurchase, node: RouteNode, cost: Double)] {
        RoutePurchase.allCases.compactMap { purchase in
            guard let next = apply(purchase, to: node) else { return nil }
            return (purchase, next, cost(of: purchase, from: node))
        }
    }

    /// Expected turns to afford `purchase` from `node`.
    public func cost(of purchase: RoutePurchase, from node: RouteNode) -> Double {
        ClockModel.turnsToAfford(
            price(of: purchase),
            holding: node.residualHand(startingFrom: startingHand),
            rate: node.rate,
            bankRates: context.bankRates
        )
    }

    func price(of purchase: RoutePurchase) -> [Resource: Int] {
        switch purchase {
        case .road: return Building.roadCost
        case .settlement: return Building.settlementCost
        case .city: return Building.cityCost
        case .devCard: return Building.devCardCost
        }
    }

    /// The node reached by making `purchase`, or `nil` when it is not
    /// available - no pieces left, no candidate site, no deck.
    public func apply(_ purchase: RoutePurchase, to node: RouteNode) -> RouteNode? {
        switch purchase {
        case .road: return buildingRoad(from: node)
        case .settlement: return buildingSettlement(from: node)
        case .city: return buildingCity(from: node)
        case .devCard: return buyingDevCard(from: node)
        }
    }

    // MARK: - Transitions

    private func buildingRoad(from node: RouteNode) -> RouteNode? {
        guard node.roadsBuilt < context.roadsRemaining else { return nil }
        var next = node
        next.roadsBuilt += 1
        next.roadLength += 1
        next.spend(price(of: .road))
        next.lastPurchase = .road
        claimLongestRoadIfEarned(&next)
        return next
    }

    private func buildingSettlement(from node: RouteNode) -> RouteNode? {
        guard node.settlementsBuilt < context.settlementsRemaining,
              node.settlementsBuilt < context.settlementCandidates.count else { return nil }
        let candidate = context.settlementCandidates[node.settlementsBuilt]
        // The route must already have paid for the roads that reach it.
        guard node.roadsBuilt >= candidate.roadsRequired else { return nil }

        var next = node
        next.settlementsBuilt += 1
        next.rate = next.rate.adding(candidate.rateGain)
        next.victoryPoints += Double(context.rules.victoryPoints(for: .settlement))
        next.spend(price(of: .settlement))
        next.lastPurchase = .settlement
        return next
    }

    private func buildingCity(from node: RouteNode) -> RouteNode? {
        guard node.citiesBuilt < context.citiesRemaining else { return nil }
        // A city upgrades a settlement: one already on the board, or one this
        // route has built.
        guard node.citiesBuilt < context.cityCandidates.count + node.settlementsBuilt else { return nil }

        var next = node
        next.rate = next.rate.adding(cityGain(at: node.citiesBuilt, node: node))
        next.citiesBuilt += 1
        next.victoryPoints += Double(
            context.rules.victoryPoints(for: .city) - context.rules.victoryPoints(for: .settlement)
        )
        next.spend(price(of: .city))
        next.lastPurchase = .city
        return next
    }

    private func buyingDevCard(from node: RouteNode) -> RouteNode? {
        guard node.devCardsBought < context.devCardsAvailable else { return nil }
        var next = node
        next.devCardsBought += 1
        next.victoryPoints += context.devCardVictoryPointChance
        next.knights += context.devCardKnightChance
        next.spend(price(of: .devCard))
        next.lastPurchase = .devCard
        claimLargestArmyIfEarned(&next)
        return next
    }

    /// The production an upgrade adds: an existing settlement's yield if one is
    /// left, otherwise the yield of a settlement this route built.
    private func cityGain(at index: Int, node: RouteNode) -> ProductionRate {
        if index < context.cityCandidates.count {
            return context.cityCandidates[index].rateGain
        }
        let builtIndex = index - context.cityCandidates.count
        guard builtIndex < context.settlementCandidates.count else { return ProductionRate() }
        return context.settlementCandidates[builtIndex].rateGain
    }

    private func claimLongestRoadIfEarned(_ node: inout RouteNode) {
        guard !node.holdsLongestRoad,
              node.roadLength >= context.rules.longestRoadMinimum,
              node.roadLength > context.longestRoadToBeat else { return }
        node.holdsLongestRoad = true
        node.victoryPoints += Double(context.rules.longestRoadBonus)
    }

    private func claimLargestArmyIfEarned(_ node: inout RouteNode) {
        guard !node.holdsLargestArmy else { return }
        let needed = Double(max(context.rules.largestArmyMinimum, context.largestArmyToBeat + 1))
        guard node.knights >= needed else { return }
        node.holdsLargestArmy = true
        node.victoryPoints += Double(context.rules.largestArmyBonus)
    }

    private func sum(_ lhs: ProductionRate, _ rhs: ProductionRate) -> ProductionRate {
        var total = lhs
        for resource in Resource.allCases { total[resource] += rhs[resource] }
        return total
    }
}

extension RouteNode {
    mutating func spend(_ cost: [Resource: Int]) {
        for (resource, amount) in cost { spent[resource, default: 0] += amount }
    }
}
