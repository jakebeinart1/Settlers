import CatanEngine

/// Which seats could actually pay for a proposal, from the public ledger.
///
/// Named for what it used to be: it once priced a proposal by re-planning both
/// sides' routes to victory, for `PlannerPolicy`. `EvaluationPolicy` replaced
/// that valuation with `TradeValuation`, and when `PlannerPolicy` was deleted
/// the route-beam half of this type went with it - `TradeCascade` and
/// `EvaluationProjections` only ever asked it this one question.
///
/// It answers from the counted belief, never the real hand: a proposer must not
/// pick its counterparty using information it cannot see.
public struct PlannerTradeEvaluator: Sendable {
    public let seat: PlayerID
    public init(seat: PlayerID) { self.seat = seat }

    /// Seats that could pay for `offer`, in seat order.
    ///
    /// Uses the counted belief, never the real hand.
    func plausiblePayers(of offer: TradeOffer, state: GameState, ledger: PublicLedger) -> [PlayerID] {
        state.players.map(\.id).sorted().filter { candidate in
            candidate != seat && canPlausiblyPay(candidate, offer.want, ledger: ledger)
        }
    }

    // MARK: - Helpers

    /// Whether `seat` is believed to hold what the offer asks of them. Uses the
    /// counted belief, never the real hand.
    func canPlausiblyPay(_ candidate: PlayerID, _ cost: [Resource: Int], ledger: PublicLedger) -> Bool {
        let belief = ledger.belief(of: candidate)
        return cost.allSatisfy { resource, amount in
            belief.believedHolding(of: resource) >= Double(amount)
        }
    }
}
