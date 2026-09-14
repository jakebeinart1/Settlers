import CatanEngine

/// Turns a production rate and a hand into an expected number of turns.
///
/// This is the whole cost model. Every edge in the route search is priced
/// through `turnsToAfford`, and the planner's objective is a difference of two
/// numbers this file produces.
public enum ClockModel {

    /// Chance of rolling a seven, per roll.
    public static let sevenProbability = 6.0 / 36.0

    /// A cost this seat has no way to pay. Kept as a named constant rather
    /// than `.infinity` at call sites so the arithmetic that must not produce
    /// a `NaN` (infinity minus infinity, in the advantage difference) has one
    /// place to be guarded.
    public static let unreachable = 1_000_000.0

    /// Expected turns for a seat with `rate` and `holding` to afford `cost`.
    ///
    /// ## Why the maximum and not the sum
    /// You cannot build a city out of five grain. The binding constraint is
    /// the resource you are furthest from, so the cost of a purchase is the
    /// worst per-resource wait, not the total number of cards involved.
    ///
    /// ## Why conversions matter here
    /// A resource a seat does not produce at all has an infinite direct wait,
    /// which would make most routes unreachable. Bank and port conversions
    /// remove that: a deficit can instead be bought with `bankRate` cards of
    /// whatever the seat produces fastest. Taking the cheaper of the two is
    /// what lets the search notice that a 2:1 port shortens a route, without
    /// anyone assigning ports a score.
    ///
    /// The conversion term deliberately ignores that converted cards compete
    /// with the same production feeding the direct term. It is an
    /// approximation, and it errs optimistic on routes that lean hard on one
    /// port - recorded here rather than discovered later.
    public static func turnsToAfford(
        _ cost: [Resource: Int],
        holding: [Resource: Double],
        rate: ProductionRate,
        bankRates: [Resource: Int]
    ) -> Double {
        let conversion = conversionThroughput(rate: rate, bankRates: bankRates)
        var worst = 0.0

        for resource in Resource.allCases {
            let required = Double(cost[resource] ?? 0)
            let deficit = required - (holding[resource] ?? 0)
            guard deficit > 0 else { continue }

            let direct = rate[resource] > 0 ? deficit / rate[resource] : unreachable
            let converted = conversion > 0 ? deficit / conversion : unreachable
            worst = max(worst, min(direct, converted))
        }
        return min(worst, unreachable)
    }

    /// Expected cards of an arbitrary chosen resource obtainable per turn by
    /// producing something else and trading it in.
    ///
    /// Picks the resource with the best ratio of production rate to the number
    /// of cards the bank charges for it - a 2:1 port on a 5-pip resource beats
    /// a 4:1 rate on a 6-pip one.
    static func conversionThroughput(rate: ProductionRate, bankRates: [Resource: Int]) -> Double {
        var best = 0.0
        for resource in Resource.allCases {
            let charge = Double(bankRates[resource] ?? 4)
            guard charge > 0 else { continue }
            best = max(best, rate[resource] / charge)
        }
        return best
    }

    /// The expected cost, in turns, of holding `handSize` cards through the
    /// sevens that will be rolled.
    ///
    /// Half a hand over the discard threshold is lost on every seven, and
    /// replacing those cards takes `1 / total rate` turns each. This is not
    /// decoration: it is the entire reason the planner buys a development card
    /// at eight cards to duck under the threshold, and why that behaviour
    /// needs no special case anywhere in the action selector.
    public static func sevenCost(handSize: Int, rate: ProductionRate, rules: Ruleset) -> Double {
        guard handSize > rules.discardThreshold, rate.total > 0 else { return 0 }
        let expectedLoss = sevenProbability * Double(handSize / 2)
        return expectedLoss / rate.total
    }

    /// `holding` as the planner consumes it: fractional, because a belief about
    /// an opponent's hand is a floor plus a share of what is uncertain.
    public static func holding(from belief: PublicLedger.SeatBelief) -> [Resource: Double] {
        var holding: [Resource: Double] = [:]
        for resource in Resource.allCases {
            holding[resource] = belief.believedHolding(of: resource)
        }
        return holding
    }
}
