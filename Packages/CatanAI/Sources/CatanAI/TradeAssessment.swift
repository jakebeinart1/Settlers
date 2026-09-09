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
    /// Opt-in arithmetic in the scorer's original reduction order: gains,
    /// then costs. `nil` means unavailable (including legacy recordings),
    /// while an empty array means an explained offer with no resources.
    public let resourceContributions: [TradeResourceContribution]?
}

/// One resource's term in the receiver's gain or cost reduction. Both sides
/// use the ORIGINAL hand's marginal value of one additional card, multiplied
/// by quantity without repricing successive cards. In particular, `cost` is
/// not the value of a deficit created by removing cards; it can be zero even
/// when losing the resource would prevent a build. Values are not negated:
/// `TradeAssessment.netGain` subtracts the cost sum from the gain sum.
public struct TradeResourceContribution: Codable, Sendable, Equatable {
    public enum Direction: String, Codable, Sendable, Equatable {
        case gain
        case cost
    }

    public let resource: Resource
    public let quantity: Int
    public let direction: Direction
    public let unitValue: Double
    public let totalValue: Double
    /// All four targets in scoring order, including zero-valued targets.
    public let targets: [TradeTargetContribution]
}

/// A target's contribution to ONE additional resource card, before quantity
/// multiplication. Names are `settlement`, `city`, `devCard`, and `road`.
/// `held` is the receiver's original holding, `required` is this target's
/// resource cost (zero when unused), and `otherDeficits` sums shortages of
/// the other resources. A covered or unused resource contributes zero;
/// otherwise contribution is weight times 1 / (1 + otherDeficits).
public struct TradeTargetContribution: Codable, Sendable, Equatable {
    public let targetName: String
    public let held: Int
    public let required: Int
    public let deficit: Int
    public let otherDeficits: Int
    public let weight: Double
    public let contribution: Double
}
