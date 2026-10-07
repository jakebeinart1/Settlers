import CatanEngine

/// The Expert brain a match actually started with. Persist this beside the
/// difficulty: updating the app must not silently change a resumed opponent.
/// Ghosts and callers that do not select a revision keep `legacy`.
public enum ExpertRevision: String, Codable, Sendable, CaseIterable {
    case legacy
    case cityProductionV1
    /// City production plus the independently confirmed B-002 card correction.
    case pointCompletingCardsV1
    case navalV1

    public var policyID: String {
        switch self {
        case .legacy: return "evaluation-v1"
        case .cityProductionV1: return "evaluation-city-production-v1"
        case .pointCompletingCardsV1: return "evaluation-point-completing-cards-v1"
        case .navalV1: return "naval-expert-v1"
        }
    }

    /// Frozen B-001 hypothesis, confirmed against Jake's Expert, not fitted
    /// again at integration. A different magnitude requires a new experiment
    /// and revision, not an edit that rewrites what old checkpoints mean.
    private static let cityProductionWeight = 0.7

    /// Sustainable city recipes per dice roll, valued in the same VP units
    /// as the original standing. Only the bottleneck earns credit: more ore
    /// without enough grain cannot buy more cities. No hidden hands are read.
    func productionValue(_ rate: ProductionRate) -> Double {
        guard self == .cityProductionV1 || self == .pointCompletingCardsV1 else { return 0 }
        var bottleneck = Double.infinity
        for resource in Resource.allCases {
            guard let required = Building.cityCost[resource], required > 0 else { continue }
            bottleneck = min(bottleneck, rate[resource] / Double(required))
        }
        return Self.cityProductionWeight * bottleneck
    }
}
