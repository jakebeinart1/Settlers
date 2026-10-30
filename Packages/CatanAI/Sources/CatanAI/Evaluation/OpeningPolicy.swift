import CatanEngine

/// The trade-guard Expert with its opening settlements scored by what wins.
///
/// ## Why
/// Jake, 2026-10-27: make Expert the best, not a counter to one person. Paired
/// rollouts of Expert's own games (`ghost improve`) found the opening its most
/// frequent mistake. Rolling out Expert's top seven spots at every opening
/// settlement (13 games, 104 placements, 16 shared-dice rollouts each) and
/// fitting the win rate within each placement: a pip is worth +1.5 points of
/// win rate, an ore or grain pip about twice that (+1.4 more), and on the
/// second settlement each resource type not yet owned +4.3. Variety for its
/// own sake, ports, brick, lumber and wool earned nothing beyond their pips.
///
/// ## What it is worth
/// Against three `TradeGuardPolicy.v1`, every chair, 4 seats: screened 26.6%
/// on seeds 1360000-1360311, confirmed 27.5%, 90% bootstrap [26.3, 28.6], on
/// held-out seeds 1370000-1371199 (4,800 games). It opens on more pips with
/// fewer types and builds a third more cities. Paired with today's Expert on
/// seeds 1380000-1380311 it also gains against three Classic (+2.2 points,
/// 90% [+0.2, +4.2]) and three pointCompletingCards Experts (+6.0 [+3.0, +9.1]). See
/// docs/AI_summaries/2026-10-28-opening-rollouts.md.
public struct OpeningPolicy: LedgerAwarePolicy {
    /// The brain `ExpertRevision.openingOreGrainV1` names. Frozen: a change is a new revision.
    public static let v1 = OpeningPolicy(oreGrain: 0.85, newType: 3.3, id: ExpertRevision.openingOreGrainV1.policyID)

    /// Extra value per ore or grain pip, in pips.
    public let oreGrain: Double
    /// Value per resource type the second settlement adds, in pips.
    public let newType: Double
    public let id: String
    /// Every move but an opening settlement.
    let rest: TradeGuardPolicy

    public init(oreGrain: Double, newType: Double, id: String, rest: TradeGuardPolicy = .v1) {
        self.oreGrain = oreGrain
        self.newType = newType
        self.id = id
        self.rest = rest
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let spots = observation.legalMoves.compactMap { move -> VertexID? in
            if case .placeInitialSettlement(let vertex) = move { vertex } else { nil }
        }
        guard !spots.isEmpty, spots.count == observation.legalMoves.count else {
            return rest.decide(observation, ledger: ledger, rng: &rng)
        }
        let state = observation.state
        let owned = Set(state.players[observation.seat.index].settlements.flatMap { Self.pips(at: $0, state).keys })
        // Legal moves arrive sorted, so strict > breaks ties the same way in every process.
        var best = spots[0]
        var bestScore = -Double.infinity
        for spot in spots {
            let score = self.score(Self.pips(at: spot, state), owned: owned)
            if score > bestScore { bestScore = score; best = spot }
        }
        return .placeInitialSettlement(best)
    }

    /// Pips, plus the ore and grain bonus, plus new types on the second placement.
    func score(_ pips: [Resource: Int], owned: Set<Resource>) -> Double {
        let newTypes = owned.isEmpty ? 0 : pips.keys.filter { !owned.contains($0) }.count
        return Double(pips.values.reduce(0, +)) + oreGrain * Double((pips[.ore] ?? 0) + (pips[.grain] ?? 0))
            + newType * Double(newTypes)
    }

    /// Pips per resource touching `vertex`.
    public static func pips(at vertex: VertexID, _ state: GameState) -> [Resource: Int] {
        var result: [Resource: Int] = [:]
        for tile in state.board.tiles where vertex.touchingTiles.contains(tile.coordinate) {
            if case .resource(let resource) = tile.kind, let token = tile.numberToken {
                result[resource, default: 0] += DiceOdds.pips(for: token)
            }
        }
        return result
    }
}
