import CatanEngine

/// Experimental, uncalibrated balanced-policy candidate; never the default Bot.
/// Only GameSession-shaped, single-offer response masks with a rejection use
/// joint accounting. Everything else delegates unchanged to balanced heuristics,
/// including their RNG consumption. Scoped decisions consume no policy RNG.
///
/// Acceptance applies the native atomic exchange to a copy, then compares
/// V(after) - V(before) with the ORIGINAL TradeHeuristics assessment.threshold.
/// Reusing that threshold is an experimental control, not a calibrated scale or
/// a claim of strength. Inventory potential does not imply a build is available.
public struct JointTradeResponsePolicy: Policy {
    public let id: String
    private let weights: BotWeights
    private let fallback: HeuristicPolicy

    public init(weights: BotWeights = .default, id: String = "experimental-joint-balanced-v1") {
        self.id = id
        self.weights = weights
        self.fallback = HeuristicPolicy(personality: .balanced, weights: weights, id: "heuristic-balanced")
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        guard let reject = scopedRejection(in: observation),
              case .respondToTrade(let offerID, false) = reject else {
            return fallback.decide(observation, rng: &rng)
        }
        let accept = GameMove.respondToTrade(offerID: offerID, accept: true)
        guard observation.legalMoves.contains(accept),
              acceptanceImprovesInventory(accept, observation: observation) else { return reject }
        return accept
    }

    /// Match the session's one-offer negotiation, not mixed main-turn actions
    /// or accept-only masks where inventing a rejection would violate the mask.
    private func scopedRejection(in observation: GameObservation) -> GameMove? {
        guard case .mainTurn = observation.state.phase,
              let reject = observation.legalMoves.first(where: {
                  if case .respondToTrade(_, false) = $0 { true } else { false }
              }), case .respondToTrade(let offerID, false) = reject,
              observation.legalMoves.allSatisfy({
                  if case .respondToTrade(let candidateID, _) = $0 { candidateID == offerID } else { false }
              }) else { return nil }
        return reject
    }

    private func acceptanceImprovesInventory(_ accept: GameMove, observation: GameObservation) -> Bool {
        guard case .respondToTrade(let offerID, true) = accept,
              let offer = observation.state.pendingTradeOffers.first(where: { $0.id == offerID }),
              let receiverIndex = observation.state.players.firstIndex(where: { $0.id == observation.seat }) else {
            preconditionFailure("joint response acceptance mask has no matching offer or receiver")
        }
        var after = observation.state
        do {
            try RulesEngine.apply(accept, by: observation.seat, to: &after)
        } catch {
            // Policy cannot throw. An advertised legal acceptance failing in
            // the engine is an experiment failure, never a strategic rejection.
            preconditionFailure("joint response native acceptance failed: \(error)")
        }
        guard let baseline = TradeHeuristics.assessment(
            offer: offer, receiver: observation.seat, state: observation.state,
            personality: .balanced, weights: weights) else {
            preconditionFailure("joint response receiver has no native trade assessment")
        }
        let delta = TradeHeuristics.jointInventoryDelta(
            before: observation.state.players[receiverIndex].resources, after: after.players[receiverIndex].resources,
            personality: .balanced, weights: weights)
        return delta > baseline.threshold
    }
}
