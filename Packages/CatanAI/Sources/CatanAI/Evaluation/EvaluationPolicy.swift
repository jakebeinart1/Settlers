import CatanEngine
import Foundation

/// Plays the move that leaves the best position, judged by `PositionEvaluator`.
///
/// ## What changed from `PlannerPolicy`
/// The objective is the same - be further along than the seat closest to
/// winning - but the quantity computed at the point of decision is different.
/// The planner priced each candidate by re-running a bounded route search for
/// two seats, which cost about 100ms and, more importantly, answered with an
/// estimate whose tail was a single purchase repeated. This scores the
/// resulting position directly. No horizon, no tail, nothing to approximate
/// away.
///
/// Expected turns to the target has not been thrown out; it is the term this
/// policy does not yet carry, and folding it in as one weighted feature is
/// what the planner work was for. It is deliberately absent from this first
/// version so its contribution can be measured rather than assumed.
///
/// ## Public information only
/// Hands are read from the `PublicLedger`, so an opponent's composition is a
/// belief and never their real cards.
///
/// Two deliberate gaps, both narrow and both in this seat's own favour rather
/// than against an opponent's privacy:
/// - A development card is evaluated as *a card*, not as the card the deck
///   would actually deal. `buyDevCard` is projected rather than applied, so
///   the deck's order cannot reach the decision.
/// - A candidate that steals is applied, so the evaluation sees which card the
///   steal would take. That is one card of hidden information reaching a
///   robber placement. It is recorded here rather than hidden because it is
///   the kind of thing that silently makes a strength measurement flattering.
public struct EvaluationPolicy: LedgerAwarePolicy {

    /// Which generation of trade modelling this policy plays.
    ///
    /// ## Why the old one is kept
    /// Jake's rule for trading changes is that Expert must improve *against
    /// Expert*, not just against the shipping heuristic. That cannot be
    /// measured with two builds: a table of four copies of one build wins 25%
    /// by symmetry whatever the build does. The new model has to sit at the
    /// same table as the old one, and one binary can only do that if the old
    /// one still exists. `roundThree` is the trading that shipped on main at
    /// `dac279c`, frozen as the opponent later work is measured against. The
    /// app never selects it.
    public enum TradeModel: Sendable, Equatable {
        /// Pushed at `dac279c`: the counterparty's side of a proposal is not
        /// modelled, so the rival term never sees what it receives.
        case roundThree
        /// The cascade: open with the offer best for this seat and concede
        /// more on every refusal.
        case current
        /// Jake, after seeing the cascade measured: "try the wacky trades but
        /// not a full cascade - if it isn't worth trading don't go down the
        /// ladder. But if getting a city is worth trading away 3-4 cards, that
        /// should definitely be offered."
        ///
        /// Same composed offers, same counterparty modelling, no forced
        /// escalation. An offer must clear a bar that rises with the number of
        /// cards it gives away, so a trade that finishes a city is worth four
        /// cards while a marginal one is not worth one.
        case worthIt
    }

    public let id: String
    /// Weights to play with regardless of mode, or `nil` to use the set
    /// validated for whichever mode the game is in. A sweep sets this; the app
    /// does not.
    public let weightsOverride: EvaluationWeights?
    public let tradeModel: TradeModel

    public init(
        id: String = "evaluation-v1",
        weights: EvaluationWeights? = nil,
        tradeModel: TradeModel = .worthIt
    ) {
        self.id = id
        self.weightsOverride = weights
        self.tradeModel = tradeModel
    }

    /// The weights this policy plays `mode` with.
    public func weights(for mode: GameMode) -> EvaluationWeights {
        weightsOverride ?? .forMode(mode)
    }

    /// Without a ledger, fall back to a position-only belief: exact hand
    /// sizes, unknown composition. Weaker, never wrong.
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
        // A roll is not a decision; nothing downstream of it has happened yet.
        if legal.contains(.rollDice) { return .rollDice }

        var counted = ledger
        counted.reconcileObserverHand(from: observation.state)

        let chosen = best(among: legal, state: observation.state, ledger: counted)
        precondition(
            legal.contains(chosen)
                || RulesEngine.isPermittedComposedProposal(
                    chosen, by: observation.seat, in: observation.state, legal: legal
                ),
            "evaluation policy returned a move outside its mask"
        )
        return chosen
    }

    // MARK: - Choosing

    /// The highest-scoring legal move.
    ///
    /// Ties fall back to the engine's enumeration order, which is sorted and
    /// process-independent, so a seeded game replays move for move.
    func best(among legal: [GameMove], state: GameState, ledger: PublicLedger) -> GameMove {
        // The ledger knows whose view this is; the policy does not carry a
        // seat of its own, so there is only one place the two can disagree.
        let evaluator = PositionEvaluator(seat: ledger.observer, weights: weights(for: state.mode))

        // Built once, and only when the bank is actually on the table, because
        // a bank trade is scored against the purchase it unlocks and that
        // needs the same valuation the cascade uses.
        var purchases = legal.contains(where: { if case .bankTrade = $0 { true } else { false } })
            ? PurchaseGains(valuation: TradeValuation(evaluator: evaluator, state: state, ledger: ledger))
            : nil

        var bestMove = legal[0]
        var bestScore = -Double.greatestFiniteMagnitude
        for move in legal {
            // Every model but the frozen anchor chooses its own proposal, from
            // offers the enumeration cannot express; see `TradeCascade.swift`.
            if tradeModel != .roundThree, case .proposeTrade = move { continue }
            guard let score = score(move, state: state, ledger: ledger, evaluator: evaluator,
                                   purchases: &purchases) else {
                continue
            }
            if score > bestScore {
                bestScore = score
                bestMove = move
            }
        }
        if tradeModel != .roundThree,
           let proposal = cascadeProposal(state: state, ledger: ledger, evaluator: evaluator, legal: legal),
           proposal.score > bestScore {
            bestMove = .proposeTrade(proposal.offer)
        }
        return bestMove
    }

    /// One candidate's score, or `nil` if the engine refuses the move.
    private func score(
        _ move: GameMove,
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator,
        purchases: inout PurchaseGains?
    ) -> Double? {
        if case .proposeTrade(let offer) = move {
            return projectedTrade(offer, state: state, ledger: ledger, evaluator: evaluator)
        }
        if case .buyDevCard = move {
            return projectedDevCard(state: state, ledger: ledger, evaluator: evaluator)
        }
        if case .bankTrade = move {
            return projectedBankTrade(
                move, state: state, ledger: ledger, evaluator: evaluator, purchases: &purchases
            )
        }
        guard let (next, nextLedger) = applied(move, to: state, ledger: ledger, by: evaluator.seat) else {
            return nil
        }
        let outcome = evaluator.evaluate(next, ledger: nextLedger)
        if case .respondToTrade(let offerID, true) = move {
            return acceptance(outcome, of: offerID, state: state, ledger: ledger, evaluator: evaluator)
        }
        return outcome
    }

    /// A bank or port trade's score: the position after the swap, plus the
    /// purchase the swap opens up, less the purchase already open without it.
    ///
    /// ## Why the bank needed the same correction a proposal already had
    /// `TradeValuation.bestPurchaseGain` exists because a trade scored on the
    /// position immediately after it looks like a loss - Jake's example there
    /// came out at -0.27 for the swap that finishes a city, because the
    /// evaluation could not see the city. That correction was wired to
    /// proposals and not to the bank, so a 4:1 was priced at one ply: three
    /// cards gone now, the building it pays for a move away and invisible. At
    /// the fitted `handCard` of 0.0646 that is a flat -0.194 against doing
    /// nothing, which is why an Expert seat could hold a 3:1 port, sit on
    /// three spare ore with no wheat, and never once use it.
    ///
    /// The purchase already affordable without trading is subtracted for the
    /// reason the proposal path subtracts it: otherwise every trade inherits
    /// the credit for a build the seat could have made anyway.
    private func projectedBankTrade(
        _ move: GameMove,
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator,
        purchases: inout PurchaseGains?
    ) -> Double? {
        guard let (next, nextLedger) = applied(move, to: state, ledger: ledger, by: evaluator.seat) else {
            return nil
        }
        let outcome = evaluator.evaluate(next, ledger: nextLedger)
        // `best` builds this whenever a bank trade is legal, so reaching here
        // without one would mean scoring a move nobody offered.
        guard var gains = purchases,
              let before = state.players.first(where: { $0.id == evaluator.seat }),
              let after = next.players.first(where: { $0.id == evaluator.seat })
        else { return outcome }
        let opened = gains.gain(with: after.resources) - gains.gain(with: before.resources)
        purchases = gains
        return outcome + opened
    }

    /// An acceptance's score, or `nil` if it does not beat refusing by the
    /// trade margin.
    ///
    /// ## Why a tie refuses
    /// Measured over 40 games, 100 of the 336 offers this policy accepted
    /// scored *exactly* the same as refusing them. A tie fell to the engine's
    /// enumeration order, and accept is listed before decline, so the bot took
    /// trades that gave it nothing. That is never nothing for the table: the
    /// proposer only asked because the trade helps them, and the relative
    /// objective only charges for helping the single strongest rival, so a
    /// gift to anyone else scored as free. Requiring a strict gain refuses
    /// those. The same `tradeMargin` governs proposing and accepting, so the
    /// bot is not pickier about its own offers than about everyone else's.
    private func acceptance(
        _ outcome: Double,
        of offerID: UUID,
        state: GameState,
        ledger: PublicLedger,
        evaluator: PositionEvaluator
    ) -> Double? {
        let decline = GameMove.respondToTrade(offerID: offerID, accept: false)
        guard let (refused, refusedLedger) = applied(decline, to: state, ledger: ledger, by: evaluator.seat) else {
            return outcome
        }
        let standingPat = evaluator.evaluate(refused, ledger: refusedLedger)
        return outcome > standingPat + evaluator.weights.tradeMargin ? outcome : nil
    }

    /// Applies `move` and folds its events into the ledger, masked for this
    /// seat so the belief a candidate is scored against is the belief this
    /// seat would actually hold afterwards.
    private func applied(
        _ move: GameMove,
        to state: GameState,
        ledger: PublicLedger,
        by seat: PlayerID
    ) -> (GameState, PublicLedger)? {
        var next = state
        guard let events = try? RulesEngine.apply(move, by: seat, to: &next) else { return nil }
        var nextLedger = ledger
        for event in events {
            nextLedger.apply(event.masked(for: seat), stateBefore: state)
        }
        nextLedger.reconcileObserverHand(from: next)
        return (next, nextLedger)
    }
}
