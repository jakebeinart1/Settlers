import CatanEngine

/// An explicitly hybrid policy: upstream v1 greedy decisions on representable
/// actions, Swift-authoritative compound completion, and the existing heuristic
/// for player trades and unsupported states. This is not upstream AlphaBot or a
/// claim about playing strength. No model decision samples or advances an RNG.
/// The r2 checkpoint trained with perfect information in seats 0 and 2 at
/// four seats / target 7; its calibration evaluated seat 0. Three-seat and 8/10/12-VP use is an experimental
/// distribution shift, not evidence of faithfully transferred strength.
public struct UpstreamPolicy: Policy {
    public enum Source: String, Sendable { case neural, heuristic }

    public enum FallbackReason: Equatable, Sendable {
        case unknownTurnHistory
        case playerTradeNegotiation
        case heuristicTradeProposal
        case unsupportedPreRollDevelopmentCard
        case unsupportedAction
        case invalidPrediction
        case incompleteCompound
        case unsupportedBoard
        case observationEncoding(String)
        case incompatibleState(String)

        /// Persist stable identifiers; retain error context in the detailed
        /// result without making diagnostics depend on error-description prose.
        public var identifier: String {
            switch self {
            case .unknownTurnHistory: return "unknown_turn_history"
            case .playerTradeNegotiation: return "player_trade_negotiation"
            case .heuristicTradeProposal: return "heuristic_trade_proposal"
            case .unsupportedPreRollDevelopmentCard: return "unsupported_pre_roll_development_card"
            case .unsupportedAction: return "unsupported_action"
            case .invalidPrediction: return "invalid_prediction"
            case .incompleteCompound: return "incomplete_compound"
            case .unsupportedBoard: return "unsupported_board"
            case .observationEncoding: return "observation_encoding_failure"
            case .incompatibleState: return "incompatible_state"
            }
        }
    }

    public struct ScoredDecision: Sendable {
        public let move: GameMove
        public let source: Source
        public let fallbackReason: FallbackReason?
    }

    public let id: String
    public let fallbackProfile: String
    private let fallback: HeuristicPolicy
    private let scorer: UpstreamActionScorer

    public init(network: UpstreamNetwork, fallback: HeuristicPolicy) {
        self.init(fallback: fallback, predict: { network.predict($0) })
    }

    /// The injectable boundary permits action-contract tests with prescribed
    /// logits and observations; it does not duplicate network or feature logic.
    init(fallback: HeuristicPolicy, predict: @escaping UpstreamActionScorer.Predictor,
         encode: @escaping UpstreamActionScorer.Encoder = { state, seat, context in
             try UpstreamObservation.encode(state: state, seat: seat, context: context)
         }) {
        self.fallback = fallback
        self.scorer = UpstreamActionScorer(predict: predict, encode: encode)
        self.fallbackProfile = fallback.id
        self.id = "upstream-r2-hybrid-greedy-swift-compounds-trade-scheduler-fallback-\(fallback.id)"
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        scoredDecision(observation, rng: &rng).move
    }

    public func select(_ observation: GameObservation, rng: inout RandomSource) -> PolicySelection {
        let result = scoredDecision(observation, rng: &rng)
        return PolicySelection(move: result.move, source: result.source.rawValue,
                               fallbackReason: result.fallbackReason?.identifier)
    }

    public func scoredDecision(_ observation: GameObservation, rng: inout RandomSource) -> ScoredDecision {
        precondition(!observation.legalMoves.isEmpty, "UpstreamPolicy requires a nonempty action mask")
        if let reason = fallbackReason(observation) { return heuristic(observation, reason: reason, rng: &rng) }
        if let scheduled = scheduledTrade(observation, rng: &rng) { return scheduled }
        do {
            let move = try neuralMove(observation)
            guard observation.legalMoves.contains(move) else { throw UpstreamActionScorer.ScoringError.incompleteCompound }
            return ScoredDecision(move: move, source: .neural, fallbackReason: nil)
        } catch let error as UpstreamActionScorer.ScoringError {
            return heuristic(observation, reason: scoringFallback(error), rng: &rng)
        } catch is UpstreamBoardLayout.LayoutError {
            return heuristic(observation, reason: .unsupportedBoard, rng: &rng)
        } catch let error as UpstreamObservation.EncodingError {
            return heuristic(observation, reason: .observationEncoding(String(describing: error)), rng: &rng)
        } catch {
            return heuristic(observation, reason: .incompatibleState(String(describing: error)), rng: &rng)
        }
    }

    private func scoringFallback(_ error: UpstreamActionScorer.ScoringError) -> FallbackReason {
        switch error {
        case .noRepresentableAction: return .unsupportedAction
        case .invalidPrediction: return .invalidPrediction
        case .incompleteCompound: return .incompleteCompound
        }
    }

    private func fallbackReason(_ observation: GameObservation) -> FallbackReason? {
        if observation.state.completedTurnCount == nil { return .unknownTurnHistory }
        if !observation.state.pendingTradeOffers.isEmpty
            || observation.legalMoves.contains(where: { if case .respondToTrade = $0 { true } else { false } }) {
            return .playerTradeNegotiation
        }
        if case .rollDice = observation.state.phase,
           observation.legalMoves.contains(where: UpstreamActions.unsupportedBeforeRoll) {
            return .unsupportedPreRollDevelopmentCard
        }
        return nil
    }

    /// Preserve Bot.decideMainTurn's existing build-versus-trade scheduling.
    /// Speculative heuristic tie-breaks advance only a copy; retain that RNG
    /// advance exactly when its trade decision is actually returned.
    private func scheduledTrade(_ observation: GameObservation, rng: inout RandomSource) -> ScoredDecision? {
        guard observation.legalMoves.contains(where: UpstreamActions.isPlayerTrade) else { return nil }
        var proposedRNG = rng
        let move = fallback.decide(observation, rng: &proposedRNG)
        guard UpstreamActions.isPlayerTrade(move) else { return nil }
        rng = proposedRNG
        return ScoredDecision(move: move, source: .heuristic, fallbackReason: .heuristicTradeProposal)
    }

    private func neuralMove(_ observation: GameObservation) throws -> GameMove {
        let layout = try UpstreamBoardLayout(board: observation.state.board)
        let compounds = UpstreamCompounds(observation: observation, layout: layout, scorer: scorer)
        if case .discarding = observation.state.phase { return try compounds.discard() }
        let available = observation.legalMoves.filter { !UpstreamActions.isPlayerTrade($0) }
        let actions = available.compactMap { UpstreamActions.root($0, layout: layout, state: observation.state) }
        guard actions.count == available.count else { throw UpstreamActionScorer.ScoringError.noRepresentableAction }
        let context = UpstreamDecisionContext(state: observation.state, seat: observation.seat)
        let root = try scorer.choose(actions, state: observation.state, seat: observation.seat, context: context)
        let candidates = available.filter { UpstreamActions.root($0, layout: layout, state: observation.state) == root }
        return try compounds.resolve(root: root, candidates: candidates)
    }

    private func heuristic(_ observation: GameObservation, reason: FallbackReason,
                           rng: inout RandomSource) -> ScoredDecision {
        let move = fallback.decide(observation, rng: &rng)
        precondition(observation.legalMoves.contains(move), "heuristic fallback left the supplied action mask")
        return ScoredDecision(move: move, source: .heuristic, fallbackReason: reason)
    }
}
