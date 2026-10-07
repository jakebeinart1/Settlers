import CatanEngine
import Foundation

struct NavalPurchaseTarget {
    let cost: [Resource: Int]
    let value: Double
}

extension NavalDecisionContext {
    /// Flexible production contributes one expected card per entitlement. Its
    /// option value is modestly higher, but it is never copied into five rates.
    func siteValue(_ vertex: VertexID) -> Double {
        state.board.neighborTiles(of: vertex).sorted().reduce(0.0) { total, coordinate in
            guard let tile = tiles[coordinate], let token = tile.numberToken else { return total }
            let probability = Double(DiceOdds.pips(for: token)) / 36
            switch tile.kind {
            case .resource(let resource):
                let scarcity = fixedProduction[resource] == 0 ? 1.18 : 1
                return total + probability * 4.2 * scarcity
            case .resourceChoice:
                return total + probability * 4.2 * 1.32
            case .sea, .fog, .desert:
                return total
            }
        }
    }

    func settlementValue(_ vertex: VertexID) -> Double {
        if let cached = cachedSettlementValues[vertex] { return cached }
        let overseas = vertex.touchingTiles.contains { max(abs($0.q), abs($0.r), abs($0.q + $0.r)) >= 5 }
        let publicColonyPoints = Naval.colonyPoints(for: seat, in: state)
        let newComponent = !knownComponentHasOurBuilding(at: vertex)
        let colony = overseas && newComponent && publicColonyPoints < 2 ? 0.95 : 0
        let value = 1.7 + siteValue(vertex) * (0.85 + personality.expansionBias * 0.3) + colony
        cachedSettlementValues[vertex] = value
        return value
    }

    /// A closed public land component proves its first-colony bonus. Unknown
    /// neighbouring terrain may connect it to an existing colony, so fog never
    /// earns a guaranteed point by consulting the concealed component IDs.
    func colonyPoints(_ vertex: VertexID) -> Int {
        if let cached = cachedColonyPoints[vertex] { return cached }
        let points = provenColonyPoints(vertex)
        cachedColonyPoints[vertex] = points
        return points
    }

    private func provenColonyPoints(_ vertex: VertexID) -> Int {
        guard Naval.colonyPoints(for: seat, in: state) < 2,
              let first = vertex.touchingTiles.sorted().first(where: {
                  isLand($0) && $0.distance(to: HexCoordinate(q: 0, r: 0)) >= 5
              }) else { return 1 }
        var visited: Set<HexCoordinate> = [first]
        var queue = [first]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            if state.board.corners(of: current).contains(where: {
                me.settlements.contains($0) || me.cities.contains($0)
            }) { return 1 }
            for direction in 0..<6 {
                let next = current.neighbor(direction)
                if tiles[next]?.kind == .fog { return 1 }
                if isLand(next), visited.insert(next).inserted { queue.append(next) }
            }
        }
        return 2
    }

    func knownComponentHasOurBuilding(at vertex: VertexID) -> Bool {
        let starts = vertex.touchingTiles.sorted().filter { isLand($0) }
        guard let first = starts.first else { return false }
        var visited: Set<HexCoordinate> = [first]
        var queue = [first]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            if state.board.corners(of: current).contains(where: {
                me.settlements.contains($0) || me.cities.contains($0)
            }) { return true }
            for direction in 0..<6 {
                let next = current.neighbor(direction)
                if isLand(next), visited.insert(next).inserted { queue.append(next) }
            }
        }
        return false
    }

    func isLand(_ coordinate: HexCoordinate) -> Bool {
        guard let kind = tiles[coordinate]?.kind else { return false }
        switch kind {
        case .resource, .resourceChoice, .desert: return true
        case .sea, .fog: return false
        }
    }

    func makePurchaseTargets() -> [NavalPurchaseTarget] {
        var targets: [NavalPurchaseTarget] = []
        let settlements = state.board.onBoardVertices.sorted().filter {
            Building.canBuildSettlement($0, for: seat, in: state)
        }
        let bestSettlement = settlements.map { settlementValue($0) + pointPremium(colonyPoints($0)) }.max()
        if let bestSettlement { targets.append(NavalPurchaseTarget(cost: Building.settlementCost, value: bestSettlement)) }
        if me.cities.count < state.rules.pieceLimit(for: .city),
           let best = me.settlements.sorted().map({ 1.5 + siteValue($0) + pointPremium(1) }).max() {
            targets.append(NavalPurchaseTarget(cost: Building.cityCost, value: best))
        }
        if let bestLaunch = launchCoordinates().map({ shipValue(at: $0) }).max(), bestLaunch > 0 {
            targets.append(NavalPurchaseTarget(cost: Self.shipCost, value: bestLaunch))
        }
        if me.roads.count < state.rules.maxRoadsPerPlayer,
           let best = roadApproaches.map({ settlementValue($0.vertex) / Double($0.roads + 1) }).max() {
            targets.append(NavalPurchaseTarget(cost: Building.roadCost, value: best))
        }
        if tier == .expert, me.roads.count >= state.rules.longestRoadMinimum - 1 {
            let points = state.board.onBoardEdges.sorted().filter {
                Building.canBuildRoad($0, for: seat, in: state)
            }.map(roadPoints).max() ?? 0
            if points > 0 {
                targets.append(NavalPurchaseTarget(cost: Building.roadCost,
                    value: Double(points) * 1.5 + pointPremium(points)))
            }
        }
        if observation.devCardDeckCount > 0 {
            let remaining = state.victoryPointTarget - state.victoryPoints(for: seat)
            let finishingDraw = tier == .expert && remaining == 1
            let value = finishingDraw ? finishingDrawValue : remaining <= 2 ? 2 : 0.65
            targets.append(NavalPurchaseTarget(cost: Building.devCardCost, value: value))
        }
        // A ship not yet at its coast still needs settlement funding. Without
        // this target the fleet explores while its owner trades away the supplies.
        if !ownedShips.isEmpty, tier == .expert || bestSettlement == nil,
           let best = colonySites.map({ settlementValue($0) + pointPremium(colonyPoints($0)) }).max() {
            targets.append(NavalPurchaseTarget(cost: Building.settlementCost, value: best * 0.85))
        }
        return targets
    }

    func launchCoordinates() -> [HexCoordinate] {
        voyagesEnabled ? Naval.launchSites(for: seat, in: state) : []
    }

    /// Recipe progress gives a trade/choice its eventual purchase value. Costs
    /// are actual whole-card deficits; scarce production breaks otherwise equal
    /// funding plans without assuming an unrevealed island's resources.
    func inventoryValue(_ hand: [Resource: Int]) -> Double {
        let key = Resource.allCases.map { hand[$0, default: 0] }
        if let cached = cachedInventoryValues[key] { return cached }
        let cards = Resource.allCases.reduce(0) { $0 + max(0, hand[$1] ?? 0) }
        let progress = purchaseTargets.map { target in
            let missing = Resource.allCases.reduce(0) {
                $0 + max(0, target.cost[$1, default: 0] - hand[$1, default: 0])
            }
            if tier == .expert {
                let turns = recipeRolls(target.cost, hand: hand, fixed: fixedProduction,
                                        flexible: flexibleProduction) / Double(state.players.count)
                // Equivalent bank funding is valuable, but holding the exact
                // ingredients avoids the additional exchange actions and risk.
                return target.value / (1 + turns + Double(missing) * 0.09)
            }
            return target.value / pow(1 + Double(missing), 1.05)
        }.max() ?? 0
        let ordinary = Resource.allCases.reduce(0.0) { total, resource in
            let held = max(0, hand[resource] ?? 0)
            let need = purchaseTargets.contains { ($0.cost[resource] ?? 0) > held }
            return total + Double(held) * (need && fixedProduction[resource] == 0 ? 0.095 : 0.055)
        }
        let exposure = max(0, cards - state.rules.discardThreshold)
        let value = progress + ordinary - Double(exposure) * 0.10
        cachedInventoryValues[key] = value
        return value
    }

    func addingValue(_ cards: [Resource: Int]) -> Double {
        var after = me.resources
        for resource in Resource.allCases { after[resource, default: 0] += cards[resource] ?? 0 }
        return inventoryValue(after) - inventoryValue(me.resources)
    }

    func discardValue(_ amounts: [Resource: Int]) -> Double {
        inventoryValue(spending(amounts, from: me.resources))
    }

    func roadPoints(_ edge: EdgeID) -> Int {
        if let cached = cachedRoadPoints[edge] { return cached }
        guard state.longestRoadPlayer != seat else { return 0 }
        var next = state
        next.players[seat.index].roads.insert(edge)
        let points = LongestRoad.compute(for: next) == seat ? state.rules.longestRoadBonus : 0
        cachedRoadPoints[edge] = points
        return points
    }

    func roadGain(_ edge: EdgeID) -> Double {
        if let cached = cachedRoadGains[edge] { return cached }
        let before = roadApproaches.map { settlementValue($0.vertex) / Double($0.roads + 1) }.max() ?? 0
        var next = state
        next.players[seat.index].roads.insert(edge)
        let after = BoardIndex(state: next).approachableSites(for: seat, in: next, limit: 4)
            .map { settlementValue($0.vertex) / Double($0.roads + 1) }.max() ?? 0
        let opened = next.board.onBoardVertices.sorted().filter {
            Building.canBuildSettlement($0, for: seat, in: next)
                && !Building.canBuildSettlement($0, for: seat, in: state)
        }.map(settlementValue).max() ?? 0
        let points = Double(roadPoints(edge))
        let gain = max(0, after - before) * 1.4 + opened * 0.55 + points * 1.5 - 0.02
        cachedRoadGains[edge] = gain
        return gain
    }

    var flexibleProduction: Double {
        me.settlements.sorted().reduce(0) { $0 + flexibleYield(at: $1) }
            + me.cities.sorted().reduce(0) { $0 + 2 * flexibleYield(at: $1) }
    }

    func flexibleYield(at vertex: VertexID) -> Double {
        vertex.touchingTiles.sorted().reduce(0.0) { total, coordinate in
            guard let tile = tiles[coordinate], tile.kind == .resourceChoice,
                  coordinate != state.board.robberTile, let token = tile.numberToken else { return total }
            return total + Double(DiceOdds.pips(for: token)) / 36
        }
    }

    /// Solve a purchase's expected funding time, allocating flexible production
    /// once across remaining deficits. Ordinary surplus may pay actual bank
    /// rates only after reserving the recipe's own ingredient requirements.
    func recipeRolls(_ cost: [Resource: Int], hand: [Resource: Int],
                     fixed: ProductionRate, flexible: Double) -> Double {
        func funded(after rolls: Double) -> Bool {
            var deficit = 0.0
            var exchange = 0.0
            for resource in Resource.allCases {
                let balance = Double(hand[resource] ?? 0) + rolls * fixed[resource] - Double(cost[resource] ?? 0)
                deficit += max(0, -balance)
                exchange += max(0, balance) / Double(bankRates[resource, default: 4])
            }
            return deficit <= rolls * flexible + exchange
        }
        if funded(after: 0) { return 0 }
        var lower = 0.0
        var upper = 60.0
        for _ in 0..<14 {
            let middle = (lower + upper) / 2
            if funded(after: middle) { upper = middle } else { lower = middle }
        }
        return upper
    }

    func productionImprovement(at vertex: VertexID) -> Double {
        guard tier == .expert else { return 0 }
        let after = fixedProduction.adding(ProductionModel.rateGain(at: vertex, yield: 1, in: state, tiles: tiles))
        let flexible = flexibleProduction + flexibleYield(at: vertex)
        let recipes = [Building.settlementCost, Building.cityCost, Self.shipCost]
        return recipes.reduce(0.0) { total, recipe in
            let beforeRolls = recipeRolls(recipe, hand: [:], fixed: fixedProduction, flexible: flexibleProduction)
            let afterRolls = recipeRolls(recipe, hand: [:], fixed: after, flexible: flexible)
            return total + 2.4 * (1 / (1 + afterRolls) - 1 / (1 + beforeRolls))
        }
    }
}
