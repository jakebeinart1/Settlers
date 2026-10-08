import CatanEngine
import Foundation

extension NavalDecisionContext {
    /// Funding one colony within the next owner turn is a useful reason to
    /// wait. A remote unfunded recipe is not: v1 held such a coast indefinitely,
    /// refusing even voyages with real discoveries. This is a planning horizon,
    /// not an assumption about a guaranteed future dice roll or rival trade.
    private static let colonyReservationTurns = 1.0

    func scoutingSailingGain(shipID: Int, to coordinate: HexCoordinate) -> Double {
        guard let ship = ownedShips.first(where: { $0.id == shipID }),
              let route = Naval.sailingRoute(for: ship, to: coordinate, in: state) else { return Self.negativeScore }
        if tier == .expert, canAfford(Building.settlementCost, from: me.resources),
           reachesWinningColony(from: coordinate, steps: ship.stepsRemaining - route.count),
           winningColonyDistance(from: coordinate) < winningColonyDistance(from: ship.coordinate) { return 18_500 }
        if unproductiveReturn(ship: ship, route: route, to: coordinate) { return Self.negativeScore }
        if reservesLanding(ship), !improvesLanding(from: ship.coordinate, to: coordinate) { return Self.negativeScore }
        let discovery = Double(unknownCellsSeen(along: route)) * (tier == .expert ? 0.075 : 0.10)
        let weight = tier == .expert ? 1.35 : 1.10
        let frontier = frontierPotential(at: ship.coordinate)
        let covered = ownedShips.contains { friend in
            friend.id != shipID && colonySites.contains { $0.touchingTiles.contains(friend.coordinate) }
        }
        // Select one public objective for this hull, then compare both endpoints
        // against that same scalar. Maximizing separate progress differences
        // rewarded opposite gradients in both directions without a discovery.
        let scouting = frontier > 0 && (!canSupplyColonySoon || covered)
        let before = scouting ? frontier : voyagePotential(at: ship.coordinate, shipID: shipID)
        let after = scouting ? frontierPotential(at: coordinate) : voyagePotential(at: coordinate, shipID: shipID)
        return (after - before) * weight + discovery - 0.005
    }

    /// Our own purchases can change funding and flip the travel objective.
    /// Preserve public turn history across those purchases, while permitting
    /// actual discoveries and an immediately affordable improved landing.
    private func unproductiveReturn(ship: Ship, route: [HexCoordinate], to coordinate: HexCoordinate) -> Bool {
        guard let origin = ship.previousSailingOrigin, route.contains(origin), unknownCellsSeen(along: route) == 0 else { return false }
        guard canAfford(Building.settlementCost, from: me.resources),
              let next = landingSites(at: coordinate).map(settlementValue).max() else { return true }
        let current = landingSites(at: ship.coordinate).map(settlementValue).max() ?? 0
        return next <= current + 0.001
    }

    /// A friend's hull can preserve this exact building opportunity regardless
    /// of its remaining movement. After one ship departs, recomputing the next
    /// decision reserves the last hull; there is no persistent hidden plan.
    func reservesLanding(_ ship: Ship) -> Bool {
        guard let site = landingSites(at: ship.coordinate).max(by: { settlementValue($0) < settlementValue($1) }) else { return false }
        let covered = ownedShips.contains { $0.id != ship.id && site.touchingTiles.contains($0.coordinate) }
        guard !covered else { return false }
        return canSupplyColonySoon
    }

    private var canSupplyColonySoon: Bool {
        if canAfford(Building.settlementCost, from: me.resources) { return true }
        guard Resource.allCases.allSatisfy({
            me.resources[$0, default: 0] >= Building.settlementCost[$0, default: 0] || state.bank[$0, default: 0] > 0
        }) else { return false }
        let rolls = recipeRolls(Building.settlementCost, hand: me.resources,
                                fixed: fixedProduction, flexible: flexibleProduction)
        return rolls / Double(state.players.count) <= Self.colonyReservationTurns
    }

    private func landingSites(at coordinate: HexCoordinate) -> [VertexID] {
        colonySites.filter { $0.touchingTiles.contains(coordinate) }
    }

    private func improvesLanding(from origin: HexCoordinate, to destination: HexCoordinate) -> Bool {
        guard let current = landingSites(at: origin).map(settlementValue).max(),
              let next = landingSites(at: destination).map(settlementValue).max() else { return false }
        return next > current + 0.001
    }

    /// Only public sea routes contribute to this frontier. A rival blockade,
    /// a coastline and the board envelope keep unknown terrain unreachable;
    /// the bot never assumes an unrevealed hex is water or useful land.
    func frontierPotential(at coordinate: HexCoordinate) -> Double {
        let distances = seaDistances(from: coordinate)
        return (distances.keys.sorted().map { candidate -> Double in
            let unknown = unknownCellsSeen(from: candidate)
            guard unknown > 0 else { return 0 }
            return Double(unknown) * 0.11 / pow(1.3, Double(distances[candidate] ?? 0))
        }.max() ?? 0) * 1.65
    }
}
