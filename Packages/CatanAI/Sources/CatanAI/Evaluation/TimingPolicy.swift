import CatanEngine

/// The card-completion Expert with rules about *when* to play, not what a
/// position is worth.
///
/// Jake's ask (2026-10-23): "the timing of all moves in the game is especially
/// valuable", and his rule for the army and the road: stay exactly one ahead,
/// because a bigger lead is wasted. The Expert underneath never considers a
/// knight before its roll (`EvaluationPolicy.decide` returns `.rollDice`
/// whenever it is legal), plays knights the moment they score best, and ends
/// turns at up to seven cards, so it lost 8.4 cards a game to sevens where
/// Jake lost 4.7.
///
/// `oneAheadV1` (margin + preroll + lean) is `ExpertRevision.timingOneAheadV1`.
/// 4 players, randomized board, every chair against three
/// `pointCompletingCardsV1` Experts: 28.5% on held-out seeds 985000-985311
/// (1,248 games, 90% bootstrap [26.9, 30.2]); against three Classic bots
/// +3.9 points over the Expert it replaces. Each rule alone was weaker, and
/// `hold` alone lost ground. See docs/AI_summaries/2026-10-24-timing-expert.md.
/// The other rule sets stay reachable from `sim` (`eval-timing-<rules>`).
public struct TimingPolicy: LedgerAwarePolicy {
    public enum Rule: String, CaseIterable, Sendable {
        /// Play a knight before rolling when the robber sits on one of this
        /// seat's tiles, or when the knight wins outright.
        case preroll
        /// Keep a knight in hand unless playing it now frees a tile, takes
        /// Largest Army, or wins: a held knight answers the next robber.
        case hold
        /// End the turn at five cards or fewer when anything can be bought,
        /// so a rival's seven costs less.
        case lean
        /// Jake: stay exactly one ahead. A knight or road past a one-step lead
        /// is held back; one that restores or takes the lead is played at once.
        case margin
    }

    public let rules: Set<Rule>
    public let id: String
    /// Weights to evaluate with instead of the mode's shipping set; nil in
    /// every shipped revision. `ghost duel` sets it to test a refit.
    public let weights: EvaluationWeights?
    private let base: EvaluationPolicy
    private static let leanThreshold = 5

    /// The brain `ExpertRevision.timingOneAheadV1` names. Frozen: a change is a new revision.
    public static let oneAheadV1 = TimingPolicy(rules: [.margin, .preroll, .lean],
                                                id: ExpertRevision.timingOneAheadV1.policyID)

    public init(rules: Set<Rule>, id: String? = nil, weights: EvaluationWeights? = nil) {
        self.rules = rules
        self.id = id ?? "evaluation-timing-" + Rule.allCases.filter(rules.contains).map(\.rawValue).joined(separator: "+")
        self.weights = weights
        self.base = EvaluationPolicy(weights: weights, revision: .pointCompletingCardsV1)
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: .fromPositionAlone(observation.state, observer: observation.seat), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let state = observation.state, seat = observation.seat, legal = observation.legalMoves
        var counted = ledger
        counted.reconcileObserverHand(from: state)
        let knights = legal.filter(Self.isKnight)

        if rules.contains(.preroll), case .rollDice = state.phase, !knights.isEmpty,
           Self.robberBlocks(seat, in: state) || knights.contains(where: { Self.wins($0, seat, state) }) {
            return base.best(among: knights, state: state, ledger: counted)
        }
        let base = rules.contains(.margin) ? Self.marginBase(seat, state, weights: weights) : self.base
        let pounces = rules.contains(.margin) ? knights.filter { Self.restoresLead($0, seat, state) } : []
        if case .mainTurn = state.phase, !pounces.isEmpty {
            return base.best(among: pounces, state: state, ledger: counted)
        }
        let move = base.decide(observation, ledger: ledger, rng: &rng)
        if rules.contains(.margin), case .mainTurn = state.phase, Self.isKnight(move),
           Self.leadsArmy(seat, state, by: 1), !Self.robberBlocks(seat, in: state), !Self.wins(move, seat, state) {
            return base.best(among: legal.filter { !Self.isKnight($0) }, state: state, ledger: counted)
        }
        if rules.contains(.hold), case .mainTurn = state.phase, Self.isKnight(move),
           !Self.knightIsTimely(move, seat, state) {
            return base.best(among: legal.filter { !Self.isKnight($0) }, state: state, ledger: counted)
        }
        if rules.contains(.lean), move == .endTurn, case .mainTurn = state.phase,
           state.players[seat.index].resources.values.reduce(0, +) > Self.leanThreshold {
            let spends = legal.filter(HandDiscipline.spends)
            if !spends.isEmpty { return base.best(among: spends, state: state, ledger: counted) }
        }
        return move
    }

    /// Played knights ahead of the strongest rival, holding Largest Army.
    static func leadsArmy(_ seat: PlayerID, _ state: GameState, by margin: Int) -> Bool {
        let rival = state.players.filter { $0.id != seat }.map(\.playedKnights).max() ?? 0
        return state.largestArmyPlayer == seat && state.players[seat.index].playedKnights >= rival + margin
    }

    /// A knight that takes Largest Army, or turns a tie back into a one-knight lead.
    static func restoresLead(_ move: GameMove, _ seat: PlayerID, _ state: GameState) -> Bool {
        guard isKnight(move), !leadsArmy(seat, state, by: 1) else { return false }
        var next = state
        guard (try? RulesEngine.apply(move, by: seat, to: &next)) != nil else { return false }
        return leadsArmy(seat, next, by: 1)
    }

    /// The shipped weights with road length zeroed past a two-segment lead
    /// and doubled while the road is within one segment either way.
    static func marginBase(_ seat: PlayerID, _ state: GameState, weights base: EvaluationWeights? = nil) -> EvaluationPolicy {
        var weights = base ?? EvaluationWeights.forMode(state.mode)
        let me = state.players[seat.index]
        let mine = LongestRoad.length(for: me, in: state)
        let rival = state.players.filter { $0.id != seat }.map { LongestRoad.length(for: $0, in: state) }.max() ?? 0
        if state.longestRoadPlayer == seat, mine >= rival + 2 {
            weights.roadLength = 0
        } else if abs(mine - rival) <= 1, max(mine, rival) >= 4 {
            weights.roadLength *= 2
        }
        return EvaluationPolicy(id: "evaluation-timing-margin", weights: weights, revision: .pointCompletingCardsV1)
    }

    static func isKnight(_ move: GameMove) -> Bool {
        if case .playKnight = move { true } else { false }
    }

    static func robberBlocks(_ seat: PlayerID, in state: GameState) -> Bool {
        let me = state.players[seat.index]
        return me.settlements.union(me.cities).contains { $0.touchingTiles.contains(state.board.robberTile) }
    }

    static func wins(_ move: GameMove, _ seat: PlayerID, _ state: GameState) -> Bool {
        var next = state
        guard (try? RulesEngine.apply(move, by: seat, to: &next)) != nil else { return false }
        if case .gameOver = next.phase { return true }
        return false
    }

    static func knightIsTimely(_ move: GameMove, _ seat: PlayerID, _ state: GameState) -> Bool {
        if robberBlocks(seat, in: state) { return true }
        var next = state
        guard (try? RulesEngine.apply(move, by: seat, to: &next)) != nil else { return true }
        if case .gameOver = next.phase { return true }
        return state.largestArmyPlayer != seat && next.largestArmyPlayer == seat
    }
}
