import CatanEngine

/// Prices positions that two seats are racing for.
///
/// ## Why the clock alone is not enough
/// `AdvantageModel` already notices that blocking an opponent helps, because
/// an opponent who has been cut off plans a longer route and their clock
/// lengthens. What it cannot see on its own is the *other* half of a race: a
/// route of mine that runs through a vertex an opponent will reach first is
/// not worth what it appears to be worth, because I am not going to get it.
///
/// So a candidate site is discounted by the chance a rival claims it first. A
/// settlement I will win is worth its full production; one I will probably
/// lose is worth almost nothing, and a route built on it is a route built on
/// sand.
///
/// This is the same machinery the bonus races use. Longest Road and Largest
/// Army are contested resources with a clock on them: a road run that cannot
/// beat the current holder before they extend is worth its real value, which
/// is near zero, rather than its face value in victory points.
public enum ContestModel {

    /// Most of a site's value that losing the race can take away.
    ///
    /// A contested site is worth less, never nothing. The discount is capped
    /// because the race is not the only thing that decides who builds there:
    /// a rival two roads closer may be heading somewhere else entirely, may
    /// not hold the cards, and may be blocked in the meantime.
    static let maximumDiscount = 0.5

    /// How much of the remaining value one road of disadvantage removes.
    static let discountPerRoadBehind = 0.25

    /// Chance that some rival puts a building on `vertex` before this seat can.
    ///
    /// Driven purely by road distance, which is public, and only by rivals who
    /// are strictly *closer*. Being level is not being behind - this seat also
    /// gets to move - and seat order is deliberately not modelled: it is worth
    /// a fraction of one road and would make the estimate depend on whose turn
    /// it happens to be rather than on the position.
    ///
    /// ## Why this replaced a logistic on the raw gap
    /// The first version was `1 / (1 + exp(-1.1 * gap))`, which returns 0.5
    /// when the two seats are level and 0.75 at one road behind. Almost every
    /// vertex on a real board has some rival within a road or two, so almost
    /// every candidate site lost most of its value, the planner concluded that
    /// expanding was worthless, and it upgraded its two opening settlements and
    /// then stopped. Measured over three games: **zero settlements built in two
    /// of them.** A discount that applies to everything is not a discount, it
    /// is a change of units.
    public static func rivalClaimChance(
        myDistance: Int,
        rivalDistances: [Int]
    ) -> Double {
        guard let nearest = rivalDistances.min(), nearest < myDistance else { return 0 }
        return min(maximumDiscount, discountPerRoadBehind * Double(myDistance - nearest))
    }

    /// Road distances to every vertex for each seat other than `seat`.
    ///
    /// One breadth-first search per rival, reused across every candidate, so
    /// contest pricing costs a handful of searches per planning pass rather
    /// than one per vertex.
    public static func rivalDistanceMaps(
        excluding seat: PlayerID,
        in state: GameState
    ) -> [[VertexID: Int]] {
        state.players
            .map(\.id)
            .filter { $0 != seat }
            .sorted()
            .map { RouteContext.roadDistances(for: $0, in: state) }
    }

    /// `rate` scaled down by the risk of losing the race for the site.
    public static func discounted(
        _ rate: ProductionRate,
        byClaimChance chance: Double
    ) -> ProductionRate {
        return rate.scaled(by: max(0, 1 - chance))
    }

    /// Whether a bonus is realistically still winnable.
    ///
    /// A race this seat cannot win before the holder extends is priced out of
    /// the route rather than pursued at face value - the failure mode being
    /// replaced is a bot that spends ten cards on roads for a bonus somebody
    /// else takes two turns earlier.
    public static func bonusIsContestable(
        mine: Int,
        toBeat: Int,
        minimum: Int,
        stepsAffordable: Int
    ) -> Bool {
        let needed = max(minimum, toBeat + 1)
        return mine + stepsAffordable >= needed
    }
}
