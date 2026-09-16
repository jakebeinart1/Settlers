import CatanEngine

/// Any policy, with every incoming trade offer refused.
///
/// ## Why this exists
/// Every opponent in the measurement pool accepts trades sometimes, so every
/// strength number Expert has ever been given was earned at a table that
/// trades. Jake, playing his own game on 2026-09-16, accepted 1 offer out of
/// 75 and won: "trades are a bonus; they should never be a reliance." An
/// Expert whose edge is documented as "a stream of small gains" from trades
/// has never been measured against that, and the one game where it was, the
/// bots stalled - two of three built nothing after setup.
///
/// This is that opponent. It is a decorator rather than a policy of its own
/// because the question is not "how does a trade-refusing bot play" but "how
/// does a known opponent play when it will not bail anybody out": wrapping
/// `balanced` keeps every other decision identical to the arm it is compared
/// against, so a difference between the two cells is about trading and
/// nothing else.
///
/// It refuses only what other seats propose. It may still bank-trade, and it
/// may still propose - a self-sufficient player is not a silent one.
public struct TradeRefusingPolicy: Policy {
    public let id: String
    private let base: any Policy

    public init(base: any Policy) {
        self.base = base
        self.id = "refuses-\(base.id)"
    }

    public func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        let kept = observation.legalMoves.filter {
            if case .respondToTrade(_, true) = $0 { return false }
            return true
        }
        // Accepting is never the only thing on offer - `RulesEngine` emits the
        // decline alongside it - but a mask that somehow held nothing else
        // must not turn into a crash inside a measurement run.
        guard !kept.isEmpty else { return base.decide(observation, rng: &rng) }
        return base.decide(
            GameObservation(seat: observation.seat, state: observation.state, legalMoves: kept),
            rng: &rng
        )
    }
}
