import Foundation
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

    /// How sharply the claim probability swings as the road-distance gap
    /// changes. At a gap of zero the two seats are even; one road of advantage
    /// moves the odds substantially, which matches how these races actually
    /// resolve.
    static let distanceSharpness = 1.1

    /// Chance that some rival puts a building on `vertex` before this seat can.
    ///
    /// Driven purely by road distance, which is public. A rival who is two
    /// roads closer will usually get there; one who is two roads further
    /// usually will not. Seat order is deliberately not modelled - it is worth
    /// a fraction of one road of distance and would make the estimate depend
    /// on whose turn it happens to be rather than on the position.
    public static func rivalClaimChance(
        myDistance: Int,
        rivalDistances: [Int]
    ) -> Double {
        guard let nearest = rivalDistances.min() else { return 0 }
        let gap = Double(myDistance - nearest)
        return 1.0 / (1.0 + exp(-distanceSharpness * gap))
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
