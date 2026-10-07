import CatanEngine

/// Research control: the Traditional economy deliberately declines all naval
/// access. Its funding targets also omit ships, so this is a capable home-land
/// strategy rather than a bot repeatedly saving for a forbidden purchase.
/// It is never selected by the app. Completion and wins must be reported
/// separately; its purpose is to challenge whether expeditions matter.
public struct NavalLandControl: LedgerAwarePolicy {
    public let id = "naval-traditional-land-control-v1"
    public init() {}

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        decide(observation, ledger: NavalPolicy.positionLedger(observation), rng: &rng)
    }

    public func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove {
        let candidates = NavalPolicy(tier: .traditional).assess(observation, ledger: ledger, voyagesEnabled: false)
        guard var best = candidates.first else { preconditionFailure("Land control has no permitted action") }
        for candidate in candidates.dropFirst() where candidate.score > best.score { best = candidate }
        return best.move
    }
}
