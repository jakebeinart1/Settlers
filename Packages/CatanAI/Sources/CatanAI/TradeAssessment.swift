import CatanEngine

/// The scalar rationale actually used to accept or reject a player trade.
/// Values describe the receiver's gains/costs and each additive threshold
/// shift; `accepted` is the strict `netGain > threshold` decision, not a
/// promise that the bot chose this trade over its other available moves.
/// Missing receivers have no rationale: `TradeHeuristics.assessment` returns
/// `nil` rather than manufacturing zero-valued evidence.
public struct TradeAssessment: Codable, Sendable, Equatable {
    public let offer: TradeOffer
    public let receiver: PlayerID
    public let gainValue: Double
    public let costValue: Double
    public let netGain: Double
    public let baseThreshold: Double
    public let threatShift: Double
    public let standingShift: Double
    public let suspicionShift: Double
    /// Newly affordable build-cost penalty: the proposer gains enough cards
    /// for a previously unaffordable settlement/city cost. Does not check
    /// legal placement, remaining pieces, or whether the build would win.
    public let unlockShift: Double
    public let threshold: Double
    public let accepted: Bool
}
