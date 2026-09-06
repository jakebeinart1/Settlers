/// A policy's actual selection, before any session safety override. Metadata
/// follows the same single decision call as the move; observing it must never
/// invoke the policy twice or advance RNG again.
public struct PolicySelection: Codable, Equatable, Sendable {
    public let move: GameMove
    public let source: String
    public let fallbackReason: String?

    public init(move: GameMove, source: String, fallbackReason: String? = nil) {
        self.move = move
        self.source = source
        self.fallbackReason = fallbackReason
    }
}

/// Compact durable provenance. Unlike GameSession.Decision this does not copy
/// the whole observation into every move of a phone's recording.
public struct PolicyTrace: Codable, Equatable, Sendable {
    /// Only selections evaluated by GameSession have a cursor index. An app
    /// negotiation records its existing result without inventing an evaluation.
    public let evaluationIndex: Int?
    public let policyID: String
    public let selection: PolicySelection
    public let sessionOverride: String?

    public init(evaluationIndex: Int?, policyID: String, selection: PolicySelection, sessionOverride: String? = nil) {
        self.evaluationIndex = evaluationIndex
        self.policyID = policyID
        self.selection = selection
        self.sessionOverride = sessionOverride
    }
}
