import CatanEngine

extension NavalDecisionContext {
    func robberValue(at coordinate: HexCoordinate, victim: PlayerID?) -> Double {
        guard let tile = tiles[coordinate], let token = tile.numberToken else { return 0 }
        let probability = Double(DiceOdds.pips(for: token)) / 36
        let corners = state.board.corners(of: coordinate)
        let disruption = state.players.sorted { $0.id < $1.id }.reduce(0.0) { sum, player in
            let buildings = corners.reduce(0) { $0 + (player.cities.contains($1) ? 2 : player.settlements.contains($1) ? 1 : 0) }
            let threat = 1 + Double(state.publicVictoryPoints(for: player.id)) / Double(state.victoryPointTarget)
            return sum + Double(buildings) * (player.id == seat ? -1.8 : threat)
        }
        let steal = victim.map { observation.handCounts[$0, default: 0] > 0 ? 0.18 : 0 } ?? 0
        return disruption * probability * (1.5 + personality.aggressiveness) + steal
    }

    func knightValue(at coordinate: HexCoordinate, victim: PlayerID?) -> Double {
        let newArmy = me.playedKnights + 1
        let rivalArmy = state.players.filter { $0.id != seat }.map(\.playedKnights).max() ?? 0
        let claims = state.largestArmyPlayer != seat && newArmy >= state.rules.largestArmyMinimum && newArmy > rivalArmy
        let points = claims ? state.rules.largestArmyBonus : 0
        if state.victoryPoints(for: seat) + points >= state.victoryPointTarget { return sureWinScore }
        return robberValue(at: coordinate, victim: victim) + Double(points) * 1.5
            + (newArmy < state.rules.largestArmyMinimum ? 0.12 : 0) - 0.04
    }

    func roadBuildingValue(_ first: EdgeID, _ second: EdgeID) -> Double {
        var next = state
        next.players[seat.index].roads.formUnion([first, second])
        let claims = state.longestRoadPlayer != seat && LongestRoad.compute(for: next) == seat
        let points = claims ? state.rules.longestRoadBonus : 0
        if state.victoryPoints(for: seat) + points >= state.victoryPointTarget { return sureWinScore }
        return max(0, roadGain(first)) + max(0, roadGain(second)) + Double(points) * 1.3 - 0.03
    }

    func devCardValue() -> Double {
        let remaining = state.victoryPointTarget - state.victoryPoints(for: seat)
        if remaining == 1, tier != .expert || victoryDrawChance > 0 { return finishingDrawValue }
        let progress = remaining <= 3 ? 1.1 : 0.50
        let army = me.playedKnights < state.rules.largestArmyMinimum ? 0.15 : 0
        return purchaseScore(value: progress + army, cost: Building.devCardCost, points: 0)
    }

    var victoryDrawChance: Double {
        let ownedVictoryCards = me.devCards.filter { $0 == .victoryPoint }.count
        let availableVictoryCards = max(0, (state.rules.devCardDeck[.victoryPoint] ?? 0) - ownedVictoryCards)
        let publicKnights = state.players.sorted { $0.id < $1.id }.reduce(0) { $0 + $1.playedKnights }
        let unknownCards = max(1, state.rules.devCardDeckSize - me.devCards.count - publicKnights)
        return min(1, Double(availableVictoryCards) / Double(unknownCards))
    }

    var finishingDrawValue: Double {
        victoryDrawChance == 1 ? sureWinScore + 0.1 : 10_000 * victoryDrawChance + 0.1
    }

    /// Unknown cards are distributed using public production, with a uniform
    /// residual prior when the rival has no production of the chosen type.
    func monopolyValue(_ resource: Resource) -> Double {
        let expected = state.players.filter { $0.id != seat }.sorted { $0.id < $1.id }.reduce(0.0) { sum, rival in
            let belief = ledger.belief(of: rival.id)
            let known = Resource.allCases.reduce(0) { $0 + belief.known[$1, default: 0] }
            let unknown = max(0, belief.maxTotal - known)
            let rate = ProductionModel.rate(for: rival.id, in: state, tiles: tiles)
            let share = (rate[resource] + 0.04) / (rate.total + 0.20)
            return sum + Double(belief.known[resource, default: 0]) + Double(unknown) * share
        }
        guard expected >= 1 else { return -0.03 }
        let harvest = max(1, Int(expected.rounded(.down)))
        return addingValue([resource: harvest]) + expected * 0.025 - 0.12
    }
}
