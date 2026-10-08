import CatanEngine
import Foundation

extension NavalDecisionContext {
    /// Shortest routes through the public sea graph. Fog is not treated as
    /// guaranteed water; new information is available only after committed sailing.
    /// Enemy hulls cut version 4 routes. Seeding, rather than unblocking, the
    /// origin permits a captured ship to leave a mixed-owner stack once.
    func seaDistances(from origin: HexCoordinate) -> [HexCoordinate: Int] {
        if let cached = cachedSeaDistances[origin] { return cached }
        var distances: [HexCoordinate: Int] = [origin: 0]
        var queue = [origin]
        var cursor = 0
        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for direction in 0..<6 {
                let next = current.neighbor(direction)
                guard tiles[next]?.kind == .sea, distances[next] == nil,
                      !Naval.isBlockaded(next, by: seat, in: state) else { continue }
                distances[next] = (distances[current] ?? 0) + 1
                queue.append(next)
            }
        }
        cachedSeaDistances[origin] = distances
        return distances
    }

    func unknownCellsSeen(from coordinate: HexCoordinate) -> Int {
        if let cached = cachedDiscoveryCounts[coordinate] { return cached }
        let count = state.board.tiles.reduce(0) { total, tile in
            let deltaQ = tile.coordinate.q - coordinate.q
            let deltaR = tile.coordinate.r - coordinate.r
            let distance = max(abs(deltaQ), abs(deltaR), abs(deltaQ + deltaR))
            return total + (tile.kind == .fog && distance <= Naval.viewingRange ? 1 : 0)
        }
        cachedDiscoveryCounts[coordinate] = count
        return count
    }

    /// A voyage discovers the union of sight along its canonical route, counting each unknown hex once.
    func unknownCellsSeen(along route: [HexCoordinate]) -> Int {
        if route.count == 1 { return unknownCellsSeen(from: route[0]) }
        return state.board.tiles.reduce(0) { total, tile in
            let discovered = tile.kind == .fog && route.contains { tile.coordinate.distance(to: $0) <= Naval.viewingRange }
            return total + (discovered ? 1 : 0)
        }
    }

    func voyagePotential(at coordinate: HexCoordinate, shipID: Int?) -> Double {
        let distances = seaDistances(from: coordinate)
        let colony = colonySites.map { site -> Double in
            let landingDistance = site.touchingTiles.sorted().compactMap { distances[$0] }.min()
            guard let landingDistance else { return 0 }
            let otherShipNear = ownedShips.contains { ship in
                ship.id != shipID && site.touchingTiles.contains(ship.coordinate)
            }
            let competition = otherShipNear ? 0.32 : 1.0
            return settlementValue(site) * competition / pow(1.28, Double(landingDistance))
        }.max() ?? 0
        let frontier = distances.keys.sorted().map { candidate -> Double in
            let unknown = unknownCellsSeen(from: candidate)
            guard unknown > 0 else { return 0 }
            return Double(unknown) * 0.11 / pow(1.3, Double(distances[candidate] ?? 0))
        }.max() ?? 0
        // Colony access remains useful with fog off and after the world clears.
        return max(colony, frontier * 1.65)
    }

    func sailingGain(shipID: Int, to coordinate: HexCoordinate) -> Double {
        if revision == .scoutingV2 { return scoutingSailingGain(shipID: shipID, to: coordinate) }
        return legacySailingGain(shipID: shipID, to: coordinate)
    }

    /// Frozen version-one valuation remains separate because existing saved
    /// decisions and checkpoints must retain their original action sequence.
    private func legacySailingGain(shipID: Int, to coordinate: HexCoordinate) -> Double {
        guard let ship = ownedShips.first(where: { $0.id == shipID }),
              let route = Naval.sailingRoute(for: ship, to: coordinate, in: state) else {
            return Self.negativeScore
        }
        if tier == .expert, canAfford(Building.settlementCost, from: me.resources),
           reachesWinningColony(from: coordinate, steps: ship.stepsRemaining - route.count),
           winningColonyDistance(from: coordinate) < winningColonyDistance(from: ship.coordinate) {
            return 18_500
        }
        // A landing is an expedition's useful result. Keep its access while
        // supplies arrive instead of leaving it, redirecting another ship and
        // returning later in the same turn. Building consumes the opportunity
        // and automatically releases the vessel for its next voyage.
        let currentLanding = colonySites.filter { $0.touchingTiles.contains(ship.coordinate) }
            .map(settlementValue).max()
        if let currentLanding {
            let nextLanding = colonySites.filter { $0.touchingTiles.contains(coordinate) }
                .map(settlementValue).max()
            guard let nextLanding, nextLanding > currentLanding + 0.001 else { return Self.negativeScore }
        }
        let before = voyagePotential(at: ship.coordinate, shipID: shipID)
        let after = voyagePotential(at: coordinate, shipID: shipID)
        let discovery = Double(unknownCellsSeen(along: route)) * (tier == .expert ? 0.075 : 0.10)
        let progress = (after - before) * (tier == .expert ? 1.35 : 1.10)
        // A strict progress floor prevents sailing back and forth to collect
        // the same positive per-move reward once all nearby fog is gone.
        return progress + discovery - 0.005
    }

    func shipValue(at coordinate: HexCoordinate) -> Double {
        let usefulColony = colonySites.contains { site in
            site.touchingTiles.contains { (tiles[$0]?.kind ?? .fog) != .sea && isLand($0) }
        }
        let unseen = state.board.tiles.contains { $0.kind == .fog }
        guard usefulColony || unseen else { return -1 }
        let fleetSize = ownedShips.count
        let dilution = 1 + Double(fleetSize) * 1.2
        let marginal = tier == .expert || revision == .scoutingV2
        let access = marginal ? marginalVoyagePotential(at: coordinate) : voyagePotential(at: coordinate, shipID: nil)
        if (state.naval?.rulesVersion ?? 0) >= Naval.blockadeRulesVersion, access <= 0 { return -1 }
        if tier == .expert, fleetSize > 0, access <= 0.05 { return -1 }
        let exploration = unseen ? (tier == .expert ? min(1.4, access) : 1.4) : 0
        let firstHull = fleetSize == 0 && (tier != .expert || Naval.shipsBuilt(by: seat, in: state) == 0)
        let value = ((firstHull ? 2.2 : 0.35) + exploration + min(2.8, access)) / dilution
        return tier == .expert ? value * expeditionRetention(from: coordinate) : value
    }

    /// Fund a future landing only while this fleet has a public route to it.
    /// A rival may move later, but no hypothetical opening earns present funding.
    /// Earlier matches retain their original unrestricted recipe valuation.
    var reachableColonySites: [VertexID] {
        guard (state.naval?.rulesVersion ?? 0) >= Naval.blockadeRulesVersion else { return colonySites }
        return colonySites.filter { site in
            ownedShips.contains { ship in
                site.touchingTiles.contains { seaDistances(from: ship.coordinate)[$0] != nil }
            }
        }
    }

    /// A new hull earns only access that improves on the fleet's existing public
    /// routes. Ships reserved at an unfunded landing still cover that colony,
    /// but cannot simultaneously scout: frontier coverage excludes those ships.
    func marginalVoyagePotential(at coordinate: HexCoordinate) -> Double {
        let distances = seaDistances(from: coordinate)
        func access(_ origin: HexCoordinate, to site: VertexID) -> Double {
            guard let distance = site.touchingTiles.compactMap({ seaDistances(from: origin)[$0] }).min() else { return 0 }
            return settlementValue(site) / pow(1.28, Double(distance))
        }
        let colony = colonySites.map { site in
            let existing = ownedShips.map { access($0.coordinate, to: site) }.max() ?? 0
            return max(0, access(coordinate, to: site) - existing)
        }.max() ?? 0
        let scouts = ownedShips.filter { ship in
            revision == .scoutingV2 ? !reservesLanding(ship) : !colonySites.contains { $0.touchingTiles.contains(ship.coordinate) }
        }
        let frontier = distances.keys.sorted().map { candidate -> Double in
            let unknown = unknownCellsSeen(from: candidate)
            guard unknown > 0 else { return 0 }
            let fresh = Double(unknown) * 0.11 / pow(1.3, Double(distances[candidate] ?? 0))
            let existing = scouts.map { ship -> Double in
                guard let distance = seaDistances(from: ship.coordinate)[candidate] else { return 0 }
                return Double(unknown) * 0.11 / pow(1.3, Double(distance))
            }.max() ?? 0
            return max(0, fresh - existing)
        }.max() ?? 0
        return max(colony, frontier * 1.65)
    }

    /// A purchased vessel is exposed to each rival's two-in-36 capture roll
    /// while its settlement recipe and public route are unfinished. Expected
    /// funding allocates wild yield once and reserves the ship's actual cost.
    func expeditionRetention(from coordinate: HexCoordinate) -> Double {
        if revision == .scoutingV2, state.naval?.options.shipStealingEnabled == false { return 1 }
        let hand = spending(Self.shipCost, from: me.resources)
        let funding = recipeRolls(Building.settlementCost, hand: hand,
                                  fixed: fixedProduction, flexible: flexibleProduction) / Double(state.players.count)
        let distance = colonySites.flatMap { site in site.touchingTiles.compactMap { seaDistances(from: coordinate)[$0] } }.min()
        let travel = distance.map { max(0, ceil(Double($0) / Double(Naval.movementPerTurn(in: state))) - 1) } ?? 1
        let rivalRolls = Double(state.players.count - 1) * max(funding, travel)
        return pow(17.0 / 18.0, rivalRolls)
    }

    func canAfford(_ cost: [Resource: Int], from hand: [Resource: Int]) -> Bool {
        Resource.allCases.allSatisfy { hand[$0, default: 0] >= cost[$0, default: 0] }
    }

    func winningColonyDistance(from coordinate: HexCoordinate) -> Int {
        let distances = seaDistances(from: coordinate)
        let points = state.victoryPoints(for: seat)
        return colonySites.filter { points + colonyPoints($0) >= state.victoryPointTarget }
            .flatMap { $0.touchingTiles.compactMap { distances[$0] } }.min() ?? Int.max
    }

    func reachesWinningColony(from coordinate: HexCoordinate, steps: Int) -> Bool {
        winningColonyDistance(from: coordinate) <= steps
    }

    func winningLaunch(at coordinate: HexCoordinate) -> Bool {
        tier == .expert && canAfford(Building.settlementCost, from: spending(Self.shipCost, from: me.resources))
            && reachesWinningColony(from: coordinate, steps: Naval.movementPerTurn(in: state))
    }

    func captureValue(_ id: Int) -> Double {
        guard let ship = state.naval?.ships.first(where: { $0.id == id }), ship.owner != seat else {
            return Self.negativeScore
        }
        if tier == .expert, canAfford(Building.settlementCost, from: me.resources),
           reachesWinningColony(from: ship.coordinate, steps: Naval.movementPerTurn(in: state)) { return 19_000 }
        let gain = 0.8 + voyagePotential(at: ship.coordinate, shipID: id) * 0.6
        let leader = state.players.filter { $0.id != seat }
            .map { state.publicVictoryPoints(for: $0.id) }.max() ?? 0
        let ownerPoints = state.publicVictoryPoints(for: ship.owner)
        let rivalry = ownerPoints == leader ? 0.45 : 0.12
        return gain + rivalry * (0.6 + personality.aggressiveness)
    }
}
