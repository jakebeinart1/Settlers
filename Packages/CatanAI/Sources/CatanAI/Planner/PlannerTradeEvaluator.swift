import CatanEngine

/// Prices player trades by what they do to both clocks.
///
/// ## Why proposals cannot be scored like other moves
/// Applying `.proposeTrade` moves no cards - it puts an offer on the table.
/// Scored the way every other move is scored, its effect on the position is
/// nil and the planner would never propose anything. So a proposal is valued
/// by the trade it would *become*: the swap is simulated, both sides are
/// re-planned, and the result is weighted by whether any seat that can pay
/// would actually want to.
///
/// ## Why the opponent's gain is priced against their route
/// One lumber is usually worth almost nothing. One lumber that completes a
/// fifth road and takes Longest Road is worth two victory points and a large
/// drop in that seat's clock. The same card, two completely different prices,
/// and only a model of what the opponent is *building* can tell them apart.
/// Counting cards alone would walk straight into the second.
///
/// The consequence, recorded deliberately: this accepts lopsided-in-our-favour
/// offers far more readily than a scorer measuring marginal value against its
/// own next build target, because it can see that they are lopsided at all.
/// It also refuses even-looking trades with the seat closest to winning.
public struct PlannerTradeEvaluator: Sendable {
    public let seat: PlayerID
    public let settings: ActionSelector.Settings

    /// Proposals examined at full fidelity per decision. The engine can
    /// enumerate 120; re-planning the table for each is not affordable, and
    /// the cheap pre-rank below is a good filter for which few are worth it.
    public static let proposalsToEvaluate = 4

    public init(seat: PlayerID, settings: ActionSelector.Settings = .default) {
        self.seat = seat
        self.settings = settings
    }

    /// The most valuable proposal among `offers`, with the change in advantage
    /// it is expected to produce.
    ///
    /// Returns `nil` when no offer is expected to be accepted, or when every
    /// acceptable one would leave this seat worse off.
    public func bestProposal(
        among offers: [TradeOffer],
        state: GameState,
        ledger: PublicLedger
    ) -> (offer: TradeOffer, score: Double)? {
        let baseline = clocks(in: state, ledger: ledger)
        let before = AdvantageModel.advantage(of: seat, given: baseline)

        // Ranked once per offer, not inside the comparator: `rank` walks both
        // sides of the offer, and a comparator recomputes it O(n log n) times
        // over a list the engine can fill with 120 candidates.
        let shortlist = offers
            .map { (offer: $0, rank: rank($0, state: state)) }
            .sorted { $0.rank != $1.rank ? $0.rank > $1.rank : $0.offer.id.uuidString < $1.offer.id.uuidString }
            .prefix(Self.proposalsToEvaluate)
            .map(\.offer)

        var best: (TradeOffer, Double)?
        for offer in shortlist {
            for responder in plausiblePayers(of: offer, state: state, ledger: ledger) {
                let outcome = settlement(
                    of: offer, accepter: responder, state: state, ledger: ledger, baseline: baseline
                )
                // Opponents are modelled as doing what this planner does -
                // accepting only when it improves their own advantage. That
                // errs toward expecting refusal, the safe direction to err in
                // as a proposer.
                let theirBefore = AdvantageModel.advantage(of: responder, given: baseline)
                guard outcome.accepter > theirBefore else { continue }
                let score = outcome.proposer - before
                guard score > 0 else { continue }
                if best == nil || score > best!.1 { best = (offer, score) }
                break
            }
        }
        guard let best else { return nil }
        return (best.0, best.1)
    }

    /// Both sides' advantage once `offer` has actually changed hands.
    ///
    /// One simulation, one re-plan, both answers. It used to be two calls -
    /// one asking whether the responder would accept, one asking what we gain
    /// - which re-planned the identical position twice per candidate
    /// responder, and trade evaluation is the most expensive thing a main turn
    /// does.
    func settlement(
        of offer: TradeOffer,
        accepter: PlayerID,
        state: GameState,
        ledger: PublicLedger,
        baseline: [PlayerID: Double]
    ) -> (proposer: Double, accepter: Double) {
        var next = state
        move(offer.give, from: offer.from, to: accepter, in: &next)
        move(offer.want, from: accepter, to: offer.from, in: &next)

        var nextLedger = ledger
        nextLedger.apply(
            .acceptedTrade(accepter, from: offer.from, gave: offer.want, got: offer.give),
            stateBefore: state
        )
        nextLedger.reconcileObserverHand(from: next)

        var clocks = baseline
        for affected in [offer.from, accepter].sorted() {
            clocks[affected] = AdvantageModel.clock(
                for: affected, in: next, ledger: nextLedger,
                settings: settings.evaluation, contest: .ignoreContest
            )
        }
        return (
            AdvantageModel.advantage(of: offer.from, given: clocks),
            AdvantageModel.advantage(of: accepter, given: clocks)
        )
    }

    /// Seats that could pay for `offer`, in seat order.
    ///
    /// Uses the counted belief, never the real hand.
    func plausiblePayers(of offer: TradeOffer, state: GameState, ledger: PublicLedger) -> [PlayerID] {
        state.players.map(\.id).sorted().filter { candidate in
            candidate != seat && canPlausiblyPay(candidate, offer.want, ledger: ledger)
        }
    }

    // MARK: - Helpers

    /// A cheap ordering used to pick which proposals deserve a full
    /// evaluation: prefer asking for what we are short of and giving what we
    /// hold most of.
    func rank(_ offer: TradeOffer, state: GameState) -> Double {
        guard let me = state.players.first(where: { $0.id == offer.from }) else { return 0 }
        // Summed over `Resource.allCases`, never over a dictionary: these are
        // floating-point sums feeding a sort, and dictionary order is seeded
        // per process.
        var wanted = 0
        var given = 0
        var surplus = 0.0
        for resource in Resource.allCases {
            wanted += offer.want[resource] ?? 0
            let offered = offer.give[resource] ?? 0
            let held = me.resources[resource] ?? 0
            given += min(offered, held)
            if offered > 0 { surplus += Double(held) - Double(offered) }
        }
        return Double(wanted) - Double(given) * 0.5 + surplus * 0.1
    }

    /// Whether `seat` is believed to hold what the offer asks of them. Uses the
    /// counted belief, never the real hand.
    func canPlausiblyPay(_ candidate: PlayerID, _ cost: [Resource: Int], ledger: PublicLedger) -> Bool {
        let belief = ledger.belief(of: candidate)
        return cost.allSatisfy { resource, amount in
            belief.believedHolding(of: resource) >= Double(amount)
        }
    }

    private func move(_ cards: [Resource: Int], from: PlayerID, to: PlayerID, in state: inout GameState) {
        guard let source = state.players.firstIndex(where: { $0.id == from }),
              let destination = state.players.firstIndex(where: { $0.id == to }) else { return }
        for (resource, amount) in cards {
            state.players[source].resources[resource, default: 0] -= amount
            state.players[destination].resources[resource, default: 0] += amount
        }
    }

    private func clocks(in state: GameState, ledger: PublicLedger) -> [PlayerID: Double] {
        AdvantageModel.clocks(
            in: state, ledger: ledger, settings: settings.evaluation, contest: .ignoreContest
        )
    }
}
