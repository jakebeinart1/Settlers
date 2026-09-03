import CatanEngine
import Foundation

/// One supervised policy/value example produced by deterministic self-play.
///
/// The record carries both layout versions because shape-compatible does not
/// mean semantically compatible: loading weights or data against moved slots
/// produces plausible numbers and bad play rather than an actionable error.
public struct TrainingExample: Codable, Sendable, Equatable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let buildID: String
    public let stateLayoutVersion: Int
    public let actionLayoutVersion: Int
    public let actionCount: Int
    public let seed: UInt64
    public let decisionIndex: Int
    public let observerSeat: Int
    public let winnerSeat: Int
    public let playerCount: Int
    public let policyID: String
    public let hiddenInformationPolicy: HiddenInformationPolicy
    public let features: [Float]
    public let legalActionIndices: [Int]
    public let chosenActionIndex: Int
    /// Final result from the observer's perspective: 1 for a win, -1 for a
    /// loss. Draws do not exist in the current rules and are not invented here.
    public let outcome: Float

    public init(
        buildID: String,
        seed: UInt64,
        decisionIndex: Int,
        policyID: String,
        hiddenInformationPolicy: HiddenInformationPolicy,
        observation: GameObservation,
        chosenMove: GameMove,
        winner: PlayerID
    ) {
        precondition(!buildID.isEmpty, "training examples require build provenance")
        precondition(!policyID.isEmpty, "training examples require policy provenance")
        precondition(decisionIndex >= 0, "decision index must be nonnegative")
        let actionSpace = ActionSpace(board: observation.state.board)
        let legal = Self.actionIndices(for: observation, in: actionSpace)
        precondition(Set(legal).count == legal.count, "legal moves alias onto one global action index")
        guard let chosen = actionSpace.index(
            of: chosenMove,
            pendingOffers: observation.state.pendingTradeOffers
        ) else {
            preconditionFailure("chosen move has no global action index: \(chosenMove)")
        }
        precondition(legal.contains(chosen), "chosen action \(chosen) is outside the legal mask")

        schemaVersion = Self.schemaVersion
        self.buildID = buildID
        stateLayoutVersion = StateEncoding.layoutVersion
        actionLayoutVersion = ActionSpace.layoutVersion
        actionCount = actionSpace.size
        self.seed = seed
        self.decisionIndex = decisionIndex
        observerSeat = observation.seat.index
        winnerSeat = winner.index
        playerCount = observation.state.players.count
        self.policyID = policyID
        self.hiddenInformationPolicy = hiddenInformationPolicy
        features = StateEncoding.features(observation, policy: hiddenInformationPolicy.statePolicy)
        legalActionIndices = legal
        chosenActionIndex = chosen
        outcome = winner == observation.seat ? 1 : -1
    }

    private static func actionIndices(
        for observation: GameObservation,
        in actionSpace: ActionSpace
    ) -> [Int] {
        observation.legalMoves.map { move in
            guard let index = actionSpace.index(
                of: move,
                pendingOffers: observation.state.pendingTradeOffers
            ) else {
                preconditionFailure("legal move has no global action index: \(move)")
            }
            return index
        }.sorted()
    }
}

public enum HiddenInformationPolicy: String, Codable, Sendable {
    case revealAll
    case publicCountsOnly

    fileprivate var statePolicy: StateEncoding.HiddenInformationPolicy {
        switch self {
        case .revealAll: .revealAll
        case .publicCountsOnly: .publicCountsOnly
        }
    }
}
