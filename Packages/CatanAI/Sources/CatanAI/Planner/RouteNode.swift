import CatanEngine

/// A purchase a route can take.
public enum RoutePurchase: String, Sendable, Hashable, CaseIterable {
    case road, settlement, city, devCard
}

/// One position along a route to victory.
///
/// ## What is deliberately not in here
/// The board, and the exact hand. A node carries a *production rate* and a
/// *cumulative spend*; the hand at any point is the starting hand minus what
/// has been spent, floored at zero. That is what collapses an enormous state
/// space into something a search can dedupe: two routes that bought the same
/// things in a different order arrive at the same node and are merged.
///
/// Victory points are a `Double` because a development card is worth its
/// expectation over the remaining deck, not a whole point.
public struct RouteNode: Sendable {
    public var victoryPoints: Double
    public var rate: ProductionRate
    /// Cumulative cost paid so far, by resource.
    public var spent: [Resource: Int]

    public var settlementsBuilt: Int
    public var citiesBuilt: Int
    public var roadsBuilt: Int
    public var devCardsBought: Int
    /// Expected knights in hand from bought cards, hence fractional.
    public var knights: Double
    public var roadLength: Int

    public var holdsLongestRoad: Bool
    public var holdsLargestArmy: Bool

    /// What the last edge bought, for beam diversity. Not part of identity.
    public var lastPurchase: RoutePurchase?

    public static func start(from context: RouteContext) -> RouteNode {
        RouteNode(
            victoryPoints: Double(context.startingVictoryPoints),
            rate: context.startingRate,
            spent: [:],
            settlementsBuilt: 0,
            citiesBuilt: 0,
            roadsBuilt: 0,
            devCardsBought: 0,
            knights: Double(context.knightsPlayed),
            roadLength: context.roadLength,
            holdsLongestRoad: context.holdsLongestRoad,
            holdsLargestArmy: context.holdsLargestArmy,
            lastPurchase: nil
        )
    }

    /// What this seat still holds, given what the route has spent.
    public func residualHand(startingFrom hand: [Resource: Double]) -> [Resource: Double] {
        var residual: [Resource: Double] = [:]
        for resource in Resource.allCases {
            residual[resource] = max(0, (hand[resource] ?? 0) - Double(spent[resource] ?? 0))
        }
        return residual
    }
}

/// Identity for deduplication. Doubles are quantised, because two routes whose
/// production differs in the twelfth decimal are the same route, and floating
/// point equality would keep both.
extension RouteNode: Hashable {
    private static let quantum = 1_000.0

    private static func quantise(_ value: Double) -> Int { Int((value * quantum).rounded()) }

    public static func == (lhs: RouteNode, rhs: RouteNode) -> Bool {
        lhs.identity == rhs.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }

    /// Everything that makes two nodes interchangeable for the search.
    /// `lastPurchase` is excluded on purpose: it steers beam diversity but does
    /// not change what can be bought next.
    private var identity: [Int] {
        var parts = [
            RouteNode.quantise(victoryPoints),
            settlementsBuilt, citiesBuilt, roadsBuilt, devCardsBought,
            RouteNode.quantise(knights), roadLength,
            holdsLongestRoad ? 1 : 0, holdsLargestArmy ? 1 : 0
        ]
        for component in rate.components { parts.append(RouteNode.quantise(component)) }
        for resource in Resource.allCases { parts.append(spent[resource] ?? 0) }
        return parts
    }
}

/// A complete plan: the ordered purchases and what they are expected to cost.
public struct Route: Sendable, Equatable {
    public let purchases: [RoutePurchase]
    /// Expected turns to complete the whole route.
    public let expectedTurns: Double
    /// The first purchase, which is what the action layer actually pursues.
    public var next: RoutePurchase? { purchases.first }

    public init(purchases: [RoutePurchase], expectedTurns: Double) {
        self.purchases = purchases
        self.expectedTurns = expectedTurns
    }

    /// A seat that cannot reach the target at all.
    public static let unreachable = Route(purchases: [], expectedTurns: ClockModel.unreachable)
}
