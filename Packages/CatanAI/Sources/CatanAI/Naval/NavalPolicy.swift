import CatanEngine

/// A complete Voyages policy using only the seat's public observation and ledger.
///
/// Sailing is evaluated as progress toward known colonies or public fog frontiers,
/// never by applying a move to the concealed world. Both tiers share the same
/// legal action contract; Traditional expresses personality through priorities,
/// while Expert prices purchases, funding and rival benefits more carefully.
public struct NavalPolicy: LedgerAwarePolicy {
    public enum Tier: String, Codable, Sendable, CaseIterable {
        case traditional, expert
    }

    public let tier: Tier
    public let personality: BotPersonality
    public var id: String { "naval-\(tier.rawValue)-v1" }

    public init(tier: Tier, personality: BotPersonality = .balanced) {
        self.tier = tier
        self.personality = personality
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: Self.positionLedger(observation), rng: &rng)
    }

    public func decide(
        _ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource
    ) -> GameMove {
        let evaluations = assess(observation, ledger: ledger)
        guard var best = evaluations.first else {
            preconditionFailure("NavalPolicy requires a nonempty action mask")
        }
        for candidate in evaluations.dropFirst() where candidate.score > best.score { best = candidate }
        // Strict deterministic ranking also protects response-only masks: answering
        // a human offer never advances the durable policy RNG on cold resume.
        return best.move
    }

    /// Actual scores/reasons in mask order, followed by permitted composed offers.
    /// Diagnostics use this exact path, so they cannot describe a different bot.
    public func assess(_ observation: GameObservation, ledger: PublicLedger? = nil) -> [NavalMoveAssessment] {
        assess(observation, ledger: ledger, voyagesEnabled: true)
    }

    func assess(_ observation: GameObservation, ledger: PublicLedger?, voyagesEnabled: Bool) -> [NavalMoveAssessment] {
        precondition(observation.state.mode == .naval && observation.state.naval != nil,
                     "NavalPolicy requires a complete Voyages observation")
        let context = NavalDecisionContext(
            observation: observation, ledger: ledger ?? Self.positionLedger(observation),
            tier: tier, personality: personality, voyagesEnabled: voyagesEnabled
        )
        let legal = observation.legalMoves.filter { move in
            guard !voyagesEnabled else { return true }
            switch move {
            case .buildShip, .sailShip, .captureShip: return false
            default: return true
            }
        }
        let composed = tier == .expert ? context.composedProposals() : []
        return (legal + composed).map { context.assessment(of: $0) }
    }

    static func positionLedger(_ observation: GameObservation) -> PublicLedger {
        var beliefs: [PlayerID: PublicLedger.SeatBelief] = [:]
        for player in observation.state.players {
            beliefs[player.id] = PublicLedger.SeatBelief(
                known: player.id == observation.seat ? player.resources.filter { $0.value > 0 } : [:],
                maxTotal: observation.handCounts[player.id] ?? 0,
                devCardCount: observation.devCardCounts[player.id] ?? 0
            )
        }
        return PublicLedger(observer: observation.seat, seats: beliefs)
    }
}

public struct NavalMoveAssessment: Sendable {
    public let move: GameMove
    public let score: Double
    public let reason: String
}
