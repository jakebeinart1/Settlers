import CatanEngine

/// Picks the legal move that most improves `advantage`.
///
/// ## The two layers
/// The route is the committed plan and changes rarely; this is the other
/// layer, and it runs at *every* decision point. It does not ask "what does my
/// route say to buy next" - it asks "of the things I can legally do right now,
/// which leaves me furthest ahead". The route reaches it through the clock: a
/// move that advances the committed route shortens this seat's clock, so it
/// scores well without anyone wiring the route into the scoring.
///
/// That is what makes commitment and opportunism coexist. At eight cards with a
/// development card affordable but not a city, the card wins because it both
/// advances the route and deletes the seven cost. If the roll then completes
/// the city, the city wins, because it is now the cheapest thing that advances
/// the same route. The route never changed; only what was affordable did.
public struct ActionSelector: Sendable {

    public struct Settings: Sendable, Equatable {
        /// Beam used when re-planning a seat inside a move evaluation. Narrower
        /// than the planning beam: this runs once per candidate move, and the
        /// question is which move is better rather than what the exact route is.
        public var evaluation: RoutePlannerSettings
        /// Above this many candidates, every move is screened with the cheap
        /// clock first and only the leaders are re-planned properly.
        public var cheapEnumerationThreshold: Int
        /// How many screened candidates get a full re-plan. Bounds the cost of
        /// a decision no matter how many moves the engine enumerates - a
        /// robber phase offers one placement per tile per victim.
        public var deepEvaluationLimit: Int

        public static let `default` = Settings(
            evaluation: RoutePlannerSettings(
                beamWidth: 12,
                maxDepthPerVictoryPoint: 2,
                exactNodeLimit: RoutePlannerSettings.default.exactNodeLimit
            ),
            cheapEnumerationThreshold: 8,
            deepEvaluationLimit: 8
        )

        public init(
            evaluation: RoutePlannerSettings,
            cheapEnumerationThreshold: Int,
            deepEvaluationLimit: Int = 8
        ) {
            self.evaluation = evaluation
            self.cheapEnumerationThreshold = cheapEnumerationThreshold
            self.deepEvaluationLimit = deepEvaluationLimit
        }
    }

    public let seat: PlayerID
    public let settings: Settings

    public init(seat: PlayerID, settings: Settings = .default) {
        self.seat = seat
        self.settings = settings
    }

    /// The best of `candidates`, with its score.
    ///
    /// Ties are broken by the candidate's position in the supplied list, which
    /// the engine already produces in a sorted, process-independent order. No
    /// randomness enters here: two runs of the same seeded game must choose the
    /// same move.
    public func best(
        among candidates: [GameMove],
        state: GameState,
        ledger: PublicLedger
    ) -> (move: GameMove, score: Double)? {
        guard !candidates.isEmpty else { return nil }

        // `advantage` is this seat's clock against the *nearest* rival's, so a
        // candidate only has to re-plan those two. Re-planning all four seats
        // per candidate measured roughly 360ms per decision, which is the shape
        // of latency that killed the earlier rollout experiment.
        // Computed once and reused for every clock in this decision, so the
        // baseline and every candidate are priced by the same contest model.
        // They were not, and the constant offset between them was larger than
        // the differences the comparison exists to measure.
        let rivalMaps = ContestModel.rivalDistanceMaps(excluding: seat, in: state)

        let baseline = clocks(in: state, ledger: ledger, rivalDistances: rivalMaps)
        let before = AdvantageModel.advantage(of: seat, given: baseline)
        let rival = AdvantageModel.leadingRival(of: seat, given: baseline)

        let shortlist = candidates.count > settings.cheapEnumerationThreshold
            ? screen(candidates, state: state, ledger: ledger, baseline: baseline, rival: rival)
            : candidates
        guard !shortlist.isEmpty else { return nil }

        var bestMove: GameMove?
        var bestScore = -Double.greatestFiniteMagnitude
        for candidate in shortlist {
            guard let after = advantage(
                afterApplying: candidate, to: state, ledger: ledger,
                baseline: baseline, rival: rival, rivalDistances: rivalMaps
            ) else { continue }
            let score = after - before
            if score > bestScore {
                bestScore = score
                bestMove = candidate
            }
        }
        guard let bestMove else { return nil }
        return (bestMove, bestScore)
    }

    /// Ranks every candidate by a cheap positional score and keeps the leaders.
    ///
    /// ## Why screen at all
    /// A robber phase enumerates one placement per tile per eligible victim,
    /// and a main turn can offer thirty road edges. A proper re-plan per
    /// candidate is the difference between a decision costing milliseconds and
    /// one costing a second.
    ///
    /// ## Why this does not use the clock
    /// It did, and it saved nothing: the clock's cost is dominated by building
    /// a `RouteContext` - a breadth-first search plus a scan and sort of every
    /// vertex on the board - so screening with a cheap *clock* still paid the
    /// expensive part once per candidate. This score touches none of that. It
    /// reads what a move changes directly: victory points, total production,
    /// and hand size against the discard threshold.
    ///
    /// The screen never decides anything. It only chooses which candidates are
    /// worth the full comparison, and every survivor is then measured the same
    /// way as every other.
    func screen(
        _ candidates: [GameMove],
        state: GameState,
        ledger: PublicLedger,
        baseline: [PlayerID: Double],
        rival: PlayerID?
    ) -> [GameMove] {
        let tiles = ProductionModel.tileIndex(of: state.board)
        let before = positionScore(of: seat, in: state, tiles: tiles)

        let scored = candidates.enumerated().compactMap { position, move -> (Int, GameMove, Double)? in
            var next = state
            guard (try? RulesEngine.apply(move, by: seat, to: &next)) != nil else { return nil }
            var gain = positionScore(of: seat, in: next, tiles: tiles) - before
            if let rival {
                // A move that slows the nearest rival is worth as much as one
                // that speeds this seat up - which is the whole objective in
                // miniature, and is what keeps blocking moves on the shortlist.
                gain -= positionScore(of: rival, in: next, tiles: tiles)
                    - positionScore(of: rival, in: state, tiles: tiles)
            }
            return (position, move, gain)
        }
        // Ties fall back to the engine's own enumeration order, which is
        // sorted and process-independent, so the shortlist is reproducible.
        return scored
            .sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }
            .prefix(settings.deepEvaluationLimit)
            .map(\.1)
    }

    /// A cheap stand-in for a seat's standing: points, production, and the
    /// penalty for sitting on a hand a seven would halve.
    ///
    /// Screening only, never scoring. The weights exist to order a shortlist,
    /// not to decide anything, which is why they are plain constants here
    /// rather than tunable policy.
    func positionScore(of seat: PlayerID, in state: GameState, tiles: [HexCoordinate: Tile]) -> Double {
        let victoryPointWeight = 10.0
        let productionWeight = 6.0
        let overflowWeight = 0.35

        let rate = ProductionModel.rate(for: seat, in: state, tiles: tiles)
        let hand = state.players.first { $0.id == seat }?.resources.values.reduce(0, +) ?? 0
        let overflow = max(0, hand - state.rules.discardThreshold)
        return Double(state.publicVictoryPoints(for: seat)) * victoryPointWeight
            + rate.total * productionWeight
            - Double(overflow) * overflowWeight
    }

    /// This seat's advantage after `move` is applied, or `nil` if the engine
    /// refuses the move.
    ///
    /// Only the seats a move can actually affect are re-planned; the rest of
    /// the baseline is reused. Re-planning every seat for every candidate was
    /// measured to dominate the decision, and most moves move one clock.
    func advantage(
        afterApplying move: GameMove,
        to state: GameState,
        ledger: PublicLedger,
        baseline: [PlayerID: Double],
        rival: PlayerID? = nil,
        rivalDistances: [[VertexID: Int]]? = nil
    ) -> Double? {
        var next = state
        guard let events = try? RulesEngine.apply(move, by: seat, to: &next) else { return nil }

        var nextLedger = ledger
        for event in events {
            nextLedger.apply(event.masked(for: seat), stateBefore: state)
        }
        nextLedger.reconcileObserverHand(from: next)

        var clocks = baseline
        let relevant: Set<PlayerID> = rival.map { [seat, $0] } ?? Set(state.players.map(\.id))
        for affected in seatsAffected(by: move, events: events, in: state) where relevant.contains(affected) {
            clocks[affected] = clock(
                for: affected, in: next, ledger: nextLedger, rivalDistances: rivalDistances
            )
        }
        return AdvantageModel.advantage(of: seat, given: clocks)
    }

    /// Which seats' clocks a move can change.
    ///
    /// Always this seat. Others only when the move reaches them: the robber and
    /// a knight move production and steal a card, Monopoly empties every hand,
    /// and a trade moves cards across the table. A road or a settlement can
    /// also cut an opponent off, which shows up as a changed road distance, so
    /// any event naming another seat re-plans that seat.
    func seatsAffected(by move: GameMove, events: [GameEvent], in state: GameState) -> [PlayerID] {
        var affected: Set<PlayerID> = [seat]
        switch move {
        case .playMonopoly:
            affected.formUnion(state.players.map(\.id))
        case .moveRobber(_, let victim), .playKnight(_, let victim):
            if let victim { affected.insert(victim) }
            // Production changed for everyone touching the moved tile.
            affected.formUnion(state.players.map(\.id))
        case .buildRoad, .buildSettlement:
            // May block a rival's route; re-plan the field.
            affected.formUnion(state.players.map(\.id))
        default:
            break
        }
        for event in events {
            switch event {
            case .acceptedTrade(let accepter, let proposer, _, _):
                affected.insert(accepter)
                affected.insert(proposer)
            default:
                break
            }
        }
        return affected.sorted()
    }

    // MARK: - Clocks

    func clocks(
        in state: GameState,
        ledger: PublicLedger,
        rivalDistances: [[VertexID: Int]]? = nil
    ) -> [PlayerID: Double] {
        var result: [PlayerID: Double] = [:]
        for player in state.players.sorted(by: { $0.id < $1.id }) {
            result[player.id] = clock(
                for: player.id, in: state, ledger: ledger, rivalDistances: rivalDistances
            )
        }
        return result
    }

    /// A seat's clock at the fidelity a move comparison needs.
    func clock(
        for seat: PlayerID,
        in state: GameState,
        ledger: PublicLedger,
        rivalDistances: [[VertexID: Int]]? = nil
    ) -> Double {
        AdvantageModel.clock(
            for: seat, in: state, ledger: ledger,
            settings: settings.evaluation, rivalDistances: rivalDistances
        )
    }
}
