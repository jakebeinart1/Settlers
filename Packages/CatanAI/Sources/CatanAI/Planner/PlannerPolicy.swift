import CatanEngine

/// A bot that plans a route to victory and then plays the move that most
/// widens its lead.
///
/// ## How this differs from `Bot`
/// The shipping heuristic scores each legal move against hand-authored terms
/// and picks the highest. It has no representation of winning - only of the
/// next purchase being good - which is why it cannot close a 25-point game and
/// why it will take a city over a contested road it needs.
///
/// This policy has one quantity: how many turns ahead of the nearest rival it
/// is. Every decision it makes is the move that raises that number the most.
/// Blocking, bonus races, opportunistic buying, and trade selectivity are all
/// consequences of that single objective rather than rules written for each.
///
/// ## It reads public information only
/// `GameObservation.state` contains every hand; this policy never looks at one
/// but its own. Opponents' holdings come from the counted `PublicLedger` the
/// session maintains, which is folded from events masked per seat. That makes
/// a strength measurement against it a measurement of the policy rather than
/// of its access.
///
/// ## It ships beside `Bot`, not instead of it
/// The heuristic stays exactly as it is and becomes the frozen anchor this is
/// measured against. Two prior candidates improved on paper and lost badly in
/// play; this one does not enter the app roster until it wins under the
/// `bot-strength` protocol.
public struct PlannerPolicy: LedgerAwarePolicy {
    public let id: String
    public let settings: ActionSelector.Settings
    public let plannerSettings: RoutePlannerSettings

    public init(
        id: String = "planner-v1",
        settings: ActionSelector.Settings = .default,
        plannerSettings: RoutePlannerSettings = .default
    ) {
        self.id = id
        self.settings = settings
        self.plannerSettings = plannerSettings
    }

    /// Without a ledger the policy still plays, using a position-only belief:
    /// exact hand sizes, unknown composition. Weaker, never wrong, and it means
    /// a caller that has not adopted `LedgerAwarePolicy` still gets a legal,
    /// sensible bot rather than a crash.
    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(
            observation,
            ledger: PublicLedger.fromPositionAlone(observation.state, observer: observation.seat),
            rng: &rng
        )
    }

    public func decide(
        _ observation: GameObservation,
        ledger: PublicLedger,
        rng: inout RandomSource
    ) -> GameMove {
        let legal = observation.legalMoves
        precondition(!legal.isEmpty, "asked to decide with no legal moves")
        guard legal.count > 1 else { return legal[0] }

        var counted = ledger
        counted.reconcileObserverHand(from: observation.state)

        let chosen = choose(from: legal, observation: observation, ledger: counted)
        precondition(legal.contains(chosen), "planner returned a move outside its action mask")
        return chosen
    }

    // MARK: - Choosing

    private func choose(
        from legal: [GameMove],
        observation: GameObservation,
        ledger: PublicLedger
    ) -> GameMove {
        // A forced roll is not a decision worth planning.
        if legal.contains(.rollDice) { return .rollDice }

        let selector = ActionSelector(seat: observation.seat, settings: settings)
        let (proposals, direct) = split(legal)

        var best: (move: GameMove, score: Double)?
        if let outcome = selector.best(among: direct, state: observation.state, ledger: ledger) {
            best = outcome
        }

        if !proposals.isEmpty {
            let evaluator = PlannerTradeEvaluator(seat: observation.seat, settings: settings)
            let offers = proposals.compactMap { move -> TradeOffer? in
                guard case .proposeTrade(let offer) = move else { return nil }
                return offer
            }
            if let proposal = evaluator.bestProposal(
                among: offers, state: observation.state, ledger: ledger
            ), proposal.score > (best?.score ?? 0) {
                best = (.proposeTrade(proposal.offer), proposal.score)
            }
        }

        // Nothing improved the position: end the turn if that is offered,
        // otherwise take the first legal move, which keeps the contract that
        // a returned move is always inside the mask.
        guard let best else { return legal.contains(.endTurn) ? .endTurn : legal[0] }
        return best.move
    }

    /// Trade proposals are separated because they are priced differently -
    /// by the trade they would become rather than by the offer sitting on the
    /// table. See `PlannerTradeEvaluator`.
    private func split(_ legal: [GameMove]) -> (proposals: [GameMove], direct: [GameMove]) {
        var proposals: [GameMove] = []
        var direct: [GameMove] = []
        for move in legal {
            if case .proposeTrade = move { proposals.append(move) } else { direct.append(move) }
        }
        return (proposals, direct)
    }
}
