import CatanEngine

/// Player-facing strength, deliberately independent of play personality.
///
/// Only tiers with measured behavior belong here. `standard` is the shipping
/// heuristic unchanged. `easy` is an experimental bounded-lapse policy until
/// it passes the calibration protocol; adding the type does not authorize a
/// product label by itself.
public enum AIDifficulty: String, Codable, CaseIterable, Sendable {
    case easy
    case standard
}

/// Applies a strength tier around the same personality-aware heuristic.
///
/// Standard delegates directly, including its exact RNG stream. Easy first
/// asks that same bot for intent, then occasionally softens only the target of
/// a settlement or city target. Road planning, trade judgement, robber intent,
/// dev-card use, discards, and the chosen move category remain the
/// personality's decision.
public struct DifficultyPolicy: Policy {
    public let id: String
    private let difficulty: AIDifficulty
    private let heuristic: HeuristicPolicy
    private let personality: BotPersonality
    private let weights: BotWeights

    public init(
        personality: BotPersonality,
        difficulty: AIDifficulty,
        weights: BotWeights = .default,
        id: String
    ) {
        self.heuristic = HeuristicPolicy(personality: personality, weights: weights, id: id)
        self.personality = personality
        self.weights = weights
        self.difficulty = difficulty
        self.id = id
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        let preferred = heuristic.decide(observation, rng: &rng)
        guard difficulty == .easy else { return preferred }
        return EasySpatialLapse.choose(
            insteadOf: preferred,
            observation: observation,
            personality: personality,
            weights: weights,
            rng: &rng
        )
    }
}

/// A narrow, testable source of plausible mistakes for the Easy candidate.
private enum EasySpatialLapse {
    /// A development parameter, not a product promise. It may move only on
    /// development seeds and must be frozen before held-out calibration.
    static let lapseDenominator = 1
    static let targetScoreRatio = 0.80
    static let minimumScoreRatio = 0.60

    static func choose(
        insteadOf preferred: GameMove,
        observation: GameObservation,
        personality: BotPersonality,
        weights: BotWeights,
        rng: inout RandomSource
    ) -> GameMove {
        let alternatives = rankedAlternatives(
            to: preferred,
            observation: observation,
            personality: personality,
            weights: weights
        )
        guard !alternatives.isEmpty else { return preferred }
        if lapseDenominator > 1,
           Int.random(in: 0..<lapseDenominator, using: &rng) != 0 {
            return preferred
        }
        return alternatives[0]
    }

    private static func rankedAlternatives(
        to preferred: GameMove,
        observation: GameObservation,
        personality: BotPersonality,
        weights: BotWeights
    ) -> [GameMove] {
        let candidates = observation.legalMoves.enumerated()
            .filter { $0.element != preferred && sameSpatialKind($0.element, preferred) }
        guard !candidates.isEmpty else { return [] }
        let preferredScore = score(
            preferred,
            observation: observation,
            personality: personality,
            weights: weights
        )
        let scored = candidates.map { candidate in
            RankedMove(
                move: candidate.element,
                score: score(
                    candidate.element,
                    observation: observation,
                    personality: personality,
                    weights: weights
                ),
                stableIndex: candidate.offset
            )
        }
        let lower = scored.filter { $0.score < preferredScore }
        let ranked = lower.sorted { left, right in
            left.score == right.score ? left.stableIndex < right.stableIndex : left.score > right.score
        }
        let bounded = ranked.filter {
            $0.score <= preferredScore * targetScoreRatio
                && $0.score >= preferredScore * minimumScoreRatio
        }
        return (bounded.isEmpty ? ranked : bounded).map(\.move)
    }

    private static func score(
        _ move: GameMove,
        observation: GameObservation,
        personality: BotPersonality,
        weights: BotWeights
    ) -> Double {
        if let score = BuildPlanner.score(
            move,
            for: observation.state,
            player: observation.seat,
            personality: personality,
            weights: weights
        ) {
            return score
        }
        return setupScore(move, observation: observation, weights: weights)
    }

    private static func setupScore(
        _ move: GameMove,
        observation: GameObservation,
        weights: BotWeights
    ) -> Double {
        let covered = PlacementHeuristics.coveredResources(
            for: observation.seat,
            in: observation.state
        )
        switch move {
        case .placeInitialSettlement(let vertex):
            return PlacementHeuristics.score(
                vertex: vertex,
                board: observation.state.board,
                alreadyCovered: covered,
                weights: weights
            )
        default:
            preconditionFailure("non-spatial move reached Easy spatial scoring")
        }
    }

    private static func sameSpatialKind(_ candidate: GameMove, _ preferred: GameMove) -> Bool {
        switch (candidate, preferred) {
        case (.placeInitialSettlement, .placeInitialSettlement),
             (.buildSettlement, .buildSettlement),
             (.buildCity, .buildCity):
            return true
        default:
            return false
        }
    }

    private struct RankedMove {
        let move: GameMove
        let score: Double
        let stableIndex: Int
    }
}
