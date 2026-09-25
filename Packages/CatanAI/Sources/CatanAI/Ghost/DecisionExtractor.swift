import CatanEngine

public enum ExtractionError: Error, Equatable {
    case divergedAt(game: String, index: Int, reason: String)
}

/// Replays a recorded game and writes down every choice its human made.
///
/// ## Why gradients, not features
/// Expert's score is not one tidy weighted sum. It caps at a win, subtracts
/// the strongest rival, and adds purchase corrections to trades. Refactoring it
/// to expose features would touch the shipping bot. Instead, each candidate is
/// re-scored at slightly nudged weights, and the slope is recorded. The fit then
/// works on `score + gradient · Δw`, which is exact wherever the score is linear
/// in the weights (almost everywhere) and is checked where it is not (`ghost fit`
/// prints the drift).
public enum DecisionExtractor {

    /// The ruler, the no-worse-trades rule, and the win constant. See `EvaluationWeights`.
    public static let frozen: Set<Int> = [0, 16, 18]
    static let conquestSlots = 19..<24

    public static func decisions(in game: LoggedGame, anchor: EvaluationWeights) throws -> [DecisionRecord] {
        var session = GameSession(state: game.initialState, policies: [:], policySeed: 0)
        var records: [DecisionRecord] = []
        for (index, event) in game.events.enumerated() {
            do {
                if game.humanSeats.contains(event.player),
                   let found = try decision(for: event, in: session, game: game.id, anchor: anchor) {
                    records.append(found)
                }
                _ = try session.applyExternal(event.move, by: event.player)
            } catch {
                throw ExtractionError.divergedAt(game: game.id, index: index, reason: "\(error)")
            }
        }
        return records
    }

    struct ChoiceMissing: Error { let move: GameMove }

    static func decision(
        for event: LoggedMove, in session: GameSession, game: String, anchor: EvaluationWeights
    ) throws -> DecisionRecord? {
        let state = session.state
        let legal = options(for: event, in: state)
        // A roll is not a decision; v1 does not model knight-before-roll.
        guard legal.count > 1, !legal.contains(.rollDice) else { return nil }
        let observation = GameObservation(seat: event.player, state: state, legalMoves: legal)
        let ledger = session.ledger(for: event.player)
        var extra: [TradeOffer] = []
        if case .proposeTrade(let offer) = event.move { extra.append(offer) }

        let base = EvaluationPolicy(weights: anchor).candidateScores(observation, ledger: ledger, extraProposals: extra)
        guard base.count > 1 else { return nil }
        guard let chosen = base.firstIndex(where: { same($0.move, event.move) }) else {
            throw ChoiceMissing(move: event.move)
        }
        let gradients = slopes(observation, ledger: ledger, extra: extra, anchor: anchor, count: base.count)
        let candidates = base.enumerated().map { index, candidate in
            CandidateRecord(move: candidate.move, score: candidate.score, gradient: gradients[index],
                            style: StyleFeatures.of(candidate.move, by: event.player, in: state))
        }
        return DecisionRecord(game: game, facet: facet(of: state, legal: legal), anchor: anchor.vector,
                              candidates: candidates, chosen: chosen)
    }

    /// What `event.player` could have done. A reply to someone else's offer
    /// is not in `legalMoves`, which lists the *acting* seat's moves in that
    /// phase; the responder's choice is built the way `GameSession` builds it.
    static func options(for event: LoggedMove, in state: GameState) -> [GameMove] {
        guard case .respondToTrade(let id, _) = event.move,
              let offer = state.pendingTradeOffers.first(where: { $0.id == id }) else {
            return RulesEngine.legalMoves(for: state, seat: event.player)
        }
        let reject = GameMove.respondToTrade(offerID: id, accept: false)
        guard Trading.bothSidesCanHonour(offer, responder: event.player, state: state) else { return [reject] }
        return [.respondToTrade(offerID: id, accept: true), reject]
    }

    // ponytail: 2 × free-slot re-scorings per decision (33 in Classic). Fine
    // offline; memoise per-state evaluations if 100+ games is too slow.
    /// Central differences, one free weight at a time. `result[candidate][slot]`.
    static func slopes(_ observation: GameObservation, ledger: PublicLedger, extra: [TradeOffer],
                       anchor: EvaluationWeights, count: Int) -> [[Double]] {
        var result = [[Double]](repeating: [Double](repeating: 0, count: anchor.vector.count), count: count)
        for slot in freeSlots(for: observation.state) {
            let step = 0.01 * max(abs(anchor.vector[slot]), 0.05)
            let up = scores(observation, ledger, extra, anchor, slot, +step)
            let down = scores(observation, ledger, extra, anchor, slot, -step)
            precondition(up.count == count && down.count == count, "candidate list moved with the weights")
            for index in 0..<count { result[index][slot] = (up[index] - down[index]) / (2 * step) }
        }
        return result
    }

    private static func scores(_ observation: GameObservation, _ ledger: PublicLedger, _ extra: [TradeOffer],
                               _ anchor: EvaluationWeights, _ slot: Int, _ delta: Double) -> [Double] {
        var vector = anchor.vector
        vector[slot] += delta
        return EvaluationPolicy(weights: EvaluationWeights(vector: vector))
            .candidateScores(observation, ledger: ledger, extraProposals: extra).map(\.score)
    }

    static func freeSlots(for state: GameState) -> [Int] {
        EvaluationWeights.vectorLabels.indices.filter {
            !frozen.contains($0) && (state.variant == .conquest || !conquestSlots.contains($0))
        }
    }

    static func facet(of state: GameState, legal: [GameMove]) -> Facet {
        switch state.phase {
        case .setupForward, .setupBackward: return .opening
        case .discarding: return .discard
        case .movingRobber: return .robber
        default:
            return legal.allSatisfy { if case .respondToTrade = $0 { true } else { false } } ? .tradeResponse : .turn
        }
    }

    /// A person's offer carries a fresh id; it matches by what it says.
    static func same(_ lhs: GameMove, _ rhs: GameMove) -> Bool {
        if case .proposeTrade(let left) = lhs, case .proposeTrade(let right) = rhs {
            return left.sameProposition(as: right)
        }
        return lhs == rhs
    }
}
