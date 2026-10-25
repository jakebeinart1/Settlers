import CatanEngine

/// The timing Expert, aimed at whoever is actually winning.
///
/// ## Why
/// 63 ranked games from CloudKit (2026-10-25): a lone human beat three Experts
/// in 84% of Kbeast's 25 games. When the human truly led, the robbing Expert
/// believed someone else was its strongest rival 33% of the time, while the
/// public points named the human 87% of the time: `PositionEvaluator`'s
/// standing leans on production, and hidden victory-point cards never show.
/// Across those games Experts robbed each other three times for every time
/// they robbed the human, and traded with him 3.7 times a game.
///
/// Experimental: reachable from `sim` as `eval-leader-<rules>`, never from the app.
public struct LeaderPolicy: LedgerAwarePolicy {
    public enum Rule: String, CaseIterable, Sendable {
        /// Robber and knights steal from, and sit on, the threat leader.
        case rob
        /// Refuse any trade the threat leader proposes.
        case starve
        /// Opening placements for pips, not variety: humans opened on 20.2
        /// pips over 3.9 resources, Expert on 19.1 over 4.7, and out-produced
        /// it 3.2-3.4 cards a turn to 2.9.
        case opening
        /// Refuse a trade that would let a proposer level with or ahead of
        /// this seat afford a settlement or city at once: 66 of the 158
        /// offers Experts accepted from a human were followed by one that turn.
        case deny
    }

    public let rules: Set<Rule>
    public let id: String
    private let timing = TimingPolicy.oneAheadV1
    private let base = EvaluationPolicy(revision: .pointCompletingCardsV1)

    public init(rules: Set<Rule>, id: String? = nil) {
        self.rules = rules
        self.id = id ?? "evaluation-leader-" + Rule.allCases.filter(rules.contains).map(\.rawValue).joined(separator: "+")
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let state = observation.state, seat = observation.seat
        if rules.contains(.opening), Self.isSetup(state), observation.legalMoves.count > 1 {
            var counted = ledger
            counted.reconcileObserverHand(from: state)
            var weights = EvaluationWeights.forMode(state.mode)
            weights.variety = 0
            return EvaluationPolicy(weights: weights, revision: .pointCompletingCardsV1)
                .best(among: observation.legalMoves, state: state, ledger: counted)
        }
        let move = timing.decide(observation, ledger: ledger, rng: &rng)
        guard let leader = Self.threatLeader(for: seat, in: state, ledger: ledger) else { return move }
        if rules.contains(.starve), case .respondToTrade(let id, true) = move,
           state.pendingTradeOffers.first(where: { $0.id == id })?.from == leader {
            return .respondToTrade(offerID: id, accept: false)
        }
        if rules.contains(.deny), case .respondToTrade(let id, true) = move,
           let offer = state.pendingTradeOffers.first(where: { $0.id == id }),
           Self.threat(of: offer.from, for: seat, in: state, ledger: ledger) >= Double(state.victoryPoints(for: seat) - 1),
           Self.enablesBuilding(offer, ledger: ledger) {
            return .respondToTrade(offerID: id, accept: false)
        }
        if rules.contains(.rob), Self.robs(move) {
            let aimed = observation.legalMoves.filter { Self.robs($0) && Self.isKnight($0) == Self.isKnight(move) }
                .filter { Self.victim($0) == leader && Self.blocks($0, leader, state) }
            guard !aimed.isEmpty, Self.victim(move) != leader || !Self.blocks(move, leader, state) else { return move }
            var counted = ledger
            counted.reconcileObserverHand(from: state)
            return base.best(among: aimed, state: state, ledger: counted)
        }
        return move
    }

    /// The rival with the most points counting the hidden ones they probably
    /// hold, when that is at least this seat's own count: public points plus
    /// each unplayed development card times the share of unseen cards that
    /// are victory points.
    static func threatLeader(for seat: PlayerID, in state: GameState, ledger: PublicLedger) -> PlayerID? {
        let rivals = state.players.map(\.id).filter { $0 != seat }.sorted()
        func threat(_ id: PlayerID) -> Double { Self.threat(of: id, for: seat, in: state, ledger: ledger) }
        guard let top = rivals.max(by: { threat($0) < threat($1) }) else { return nil }
        return threat(top) >= Double(state.victoryPoints(for: seat)) ? top : nil
    }

    /// `rival`'s public points plus each unplayed development card times the
    /// share of the cards `seat` has not seen that are victory points.
    static func threat(of rival: PlayerID, for seat: PlayerID, in state: GameState, ledger: PublicLedger) -> Double {
        let printed = state.rules.devCardDeck[.victoryPoint] ?? 0
        let mineHidden = state.players[seat.index].devCards.filter { $0 == .victoryPoint }.count
        let others = state.players.map(\.id).filter { $0 != seat }
        let unseen = state.devCardDeck.count + others.map { ledger.belief(of: $0).devCardCount }.reduce(0, +)
        let share = unseen == 0 ? 0 : Double(max(0, printed - mineHidden)) / Double(unseen)
        return Double(state.publicVictoryPoints(for: rival)) + share * Double(ledger.belief(of: rival).devCardCount)
    }

    /// Whether the proposer's believed hand, after `offer`, covers a settlement or a city.
    static func enablesBuilding(_ offer: TradeOffer, ledger: PublicLedger) -> Bool {
        var holding = believedHolding(from: ledger.belief(of: offer.from))
        for resource in Resource.allCases {
            holding[resource, default: 0] += Double(offer.want[resource] ?? 0) - Double(offer.give[resource] ?? 0)
        }
        func covers(_ cost: [Resource: Int]) -> Bool {
            Resource.allCases.allSatisfy { holding[$0, default: 0] + 0.5 >= Double(cost[$0] ?? 0) }
        }
        return covers(Building.settlementCost) || covers(Building.cityCost)
    }

    static func isSetup(_ state: GameState) -> Bool {
        switch state.phase {
        case .setupForward, .setupBackward: true
        default: false
        }
    }

    static func robs(_ move: GameMove) -> Bool {
        switch move {
        case .moveRobber, .playKnight: true
        default: false
        }
    }

    static func isKnight(_ move: GameMove) -> Bool { TimingPolicy.isKnight(move) }

    static func victim(_ move: GameMove) -> PlayerID? {
        switch move {
        case .moveRobber(_, let from), .playKnight(_, let from): from
        default: nil
        }
    }

    static func blocks(_ move: GameMove, _ leader: PlayerID, _ state: GameState) -> Bool {
        let hex: HexCoordinate
        switch move {
        case .moveRobber(let to, _), .playKnight(let to, _): hex = to
        default: return false
        }
        let owner = state.players[leader.index]
        return owner.settlements.union(owner.cities).contains { $0.touchingTiles.contains(hex) }
    }
}
