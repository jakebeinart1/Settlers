import CatanEngine

/// Tuning for the route search. Values, not literals, so they can be swept.
public struct RoutePlannerSettings: Sendable, Equatable {
    /// How many nodes survive each depth of the beam.
    public var beamWidth: Int
    /// Hard cap on purchases in a route, per victory point still needed.
    ///
    /// A victory point is rarely one purchase: a settlement worth one point can
    /// need three roads to reach. Sized too tight, the beam simply cannot reach
    /// the target and silently returns a worse route than exists - which is
    /// exactly what `RoutePlannerTests` caught at four purchases per point, the
    /// beam missing the exact answer by nine turns on a three-point target.
    public var maxDepthPerVictoryPoint: Int
    /// Depth floor, for the same reason. A one-point target still needs road
    /// room.
    public var minimumDepth: Int
    /// How deep a bounded estimate looks before handing the rest to the
    /// heuristic. Used per candidate move, where a full-depth plan per seat per
    /// move is not affordable.
    public var estimationHorizon: Int
    /// Hard cap on nodes the exact planner will settle before giving up.
    public var exactNodeLimit: Int

    public static let `default` = RoutePlannerSettings(
        beamWidth: 48,
        maxDepthPerVictoryPoint: 6,
        minimumDepth: 18,
        estimationHorizon: 4,
        exactNodeLimit: 200_000
    )

    public init(
        beamWidth: Int,
        maxDepthPerVictoryPoint: Int,
        minimumDepth: Int = 18,
        estimationHorizon: Int = 4,
        exactNodeLimit: Int
    ) {
        self.beamWidth = beamWidth
        self.maxDepthPerVictoryPoint = maxDepthPerVictoryPoint
        self.minimumDepth = minimumDepth
        self.estimationHorizon = estimationHorizon
        self.exactNodeLimit = exactNodeLimit
    }
}

/// Finds the cheapest sequence of purchases that reaches the victory-point
/// target, measured in expected turns.
public enum RoutePlanner {

    // MARK: - Beam search (the runtime path)

    /// Bounded beam search.
    ///
    /// ## Why a beam and not the exact search
    /// The exact planner below is correct and is used as this one's test
    /// oracle, but its frontier grows with the victory-point target, and
    /// Expanded's target is 25 - the mode with the measured defect is exactly
    /// the mode the exact search cannot be trusted to finish in a turn.
    ///
    /// ## Why diversity is preserved explicitly
    /// Ranking purely by `f` lets one purchase type dominate the whole beam at
    /// shallow depths, and the route that only pays off later - the Largest
    /// Army run, the long road - is pruned before it can. The beam therefore
    /// keeps the best surviving node for each distinct last purchase before
    /// filling the remaining slots by rank.
    public static func planByBeam(
        _ expansion: RouteExpansion,
        settings: RoutePlannerSettings = .default
    ) -> Route {
        let context = expansion.context
        let start = RouteNode.start(from: context)
        guard start.victoryPoints < Double(context.victoryPointTarget) else {
            return Route(purchases: [], expectedTurns: 0)
        }

        var beam: [SearchEntry] = [SearchEntry(node: start, cost: 0, path: [])]
        var best = Route.unreachable
        let remaining = max(0, context.victoryPointTarget - context.startingVictoryPoints)
        let maxDepth = max(settings.minimumDepth, remaining * settings.maxDepthPerVictoryPoint)

        for _ in 0..<maxDepth {
            var next: [SearchEntry] = []
            for entry in beam {
                for successor in expansion.successors(of: entry.node) {
                    let candidate = SearchEntry(
                        node: successor.node,
                        cost: entry.cost + successor.cost,
                        path: entry.path + [successor.purchase]
                    )
                    guard candidate.cost < best.expectedTurns else { continue }
                    if candidate.node.victoryPoints >= Double(context.victoryPointTarget) {
                        best = Route(purchases: candidate.path, expectedTurns: candidate.cost)
                    } else {
                        next.append(candidate)
                    }
                }
            }
            guard !next.isEmpty else { break }
            beam = prune(next, to: settings.beamWidth, expansion: expansion)
        }
        return best
    }

    /// Expected turns to the target, looking `horizon` purchases ahead and
    /// pricing whatever is left with the heuristic.
    ///
    /// ## Why the runtime does not simply call `planByBeam`
    /// A full plan is the right answer and the wrong cost. Move selection
    /// re-plans every seat a candidate move can affect, for every candidate -
    /// so a full-depth plan per evaluation multiplies out to hundreds of
    /// thousands of node expansions per decision, which is the shape of the
    /// latency that killed the earlier rollout experiment.
    ///
    /// A bounded horizon keeps what the comparison actually needs: near-term
    /// differences between candidate moves are searched properly, and the long
    /// tail - identical across candidates - is priced by the same estimate for
    /// all of them. Comparisons stay meaningful because every candidate is
    /// measured the same way.
    public static func estimate(
        _ expansion: RouteExpansion,
        settings: RoutePlannerSettings = .default
    ) -> Double {
        let context = expansion.context
        let start = RouteNode.start(from: context)
        guard start.victoryPoints < Double(context.victoryPointTarget) else { return 0 }

        var beam = [SearchEntry(node: start, cost: 0, path: [])]
        var best = heuristic(for: start, expansion: expansion)

        for _ in 0..<max(1, settings.estimationHorizon) {
            var next: [SearchEntry] = []
            for entry in beam {
                for successor in expansion.successors(of: entry.node) {
                    let cost = entry.cost + successor.cost
                    guard cost < ClockModel.unreachable else { continue }
                    let candidate = SearchEntry(
                        node: successor.node, cost: cost, path: entry.path + [successor.purchase]
                    )
                    if successor.node.victoryPoints >= Double(context.victoryPointTarget) {
                        best = min(best, cost)
                    } else {
                        best = min(best, cost + heuristic(for: successor.node, expansion: expansion))
                        next.append(candidate)
                    }
                }
            }
            guard !next.isEmpty else { break }
            beam = prune(next, to: settings.beamWidth, expansion: expansion)
        }
        return min(best, ClockModel.unreachable)
    }

    /// Collapses duplicate nodes to their cheapest path, then keeps the best
    /// surviving entry per last-purchase kind before filling by rank.
    ///
    /// ## Why deduplication has to come first
    /// It did not, and the oracle caught it. Two routes that buy the same
    /// things in a different order reach the *same* node at different costs -
    /// `[city, road, road]` costs 36 expected turns and `[road, road, city]`
    /// costs 45, because the city raises the rate the roads are then bought
    /// at. The diversity pass ran first, looked for a node whose last purchase
    /// was a city, found the 45-turn one, and marked that node as seen; the
    /// 36-turn path to the identical node was then discarded as a duplicate.
    ///
    /// The beam lost nine turns on a three-point target and looked entirely
    /// reasonable doing it - it returned a real, walkable route, just not the
    /// best one. Nothing but comparison against the exact search would have
    /// shown it.
    static func prune(
        _ entries: [SearchEntry],
        to width: Int,
        expansion: RouteExpansion
    ) -> [SearchEntry] {
        let ranked = entries
            .map { (entry: $0, score: $0.cost + heuristic(for: $0.node, expansion: expansion)) }
            .sorted { $0.score != $1.score ? $0.score < $1.score : MinHeap.precedes($0.entry, $1.entry) }

        // Cheapest path to each distinct node, and nothing else.
        var cheapest: [SearchEntry] = []
        var seenNodes: Set<RouteNode> = []
        for candidate in ranked where !seenNodes.contains(candidate.entry.node) {
            seenNodes.insert(candidate.entry.node)
            cheapest.append(candidate.entry)
        }

        var kept: [SearchEntry] = []
        var keptNodes: Set<RouteNode> = []
        var seenKinds: Set<RoutePurchase> = []
        for entry in cheapest {
            guard let kind = entry.node.lastPurchase, !seenKinds.contains(kind) else { continue }
            seenKinds.insert(kind)
            keptNodes.insert(entry.node)
            kept.append(entry)
        }
        for entry in cheapest where kept.count < width {
            guard !keptNodes.contains(entry.node) else { continue }
            keptNodes.insert(entry.node)
            kept.append(entry)
        }
        return kept
    }

    /// Optimistic estimate of the turns still needed from `node`.
    ///
    /// Prices the remaining victory points as *repeated* purchases of whichever
    /// victory-point purchase is cheapest here, spending down the hand as it
    /// goes.
    ///
    /// ## Why it repeats rather than multiplying
    /// It used to be `remaining x costOfOnePurchase`, and that made giving
    /// cards away free. A bank trade converts four surplus cards into one
    /// needed card; `turnsToAfford` charges only for the resource the next
    /// purchase is *short* of, so the four cards leaving the hand cost nothing
    /// and the one arriving shortened the estimate. Every bank trade therefore
    /// scored positive, and the planner spent whole turns converting its hand
    /// away - measured over one game: five bank trades, two roads, no
    /// settlements, no cities, and a final score of two.
    ///
    /// Charging for the whole remaining requirement fixes it at the source.
    /// Four settlements need four settlements' worth of cards, so a hand that
    /// has been traded down is visibly further from the target, and a
    /// conversion has to earn its cost against the rest of the route rather
    /// than against one purchase.
    static func heuristic(for node: RouteNode, expansion: RouteExpansion) -> Double {
        let remaining = Double(expansion.context.victoryPointTarget) - node.victoryPoints
        guard remaining > 0 else { return 0 }

        var cheapest = ClockModel.unreachable
        for purchase in RoutePurchase.allCases {
            let gain = victoryPointGain(of: purchase, in: expansion.context)
            guard gain > 0 else { continue }
            let repeats = min(maximumHeuristicRepeats, Int((remaining / gain).rounded(.up)))
            cheapest = min(cheapest, costOfRepeating(purchase, repeats, from: node, expansion: expansion))
        }
        return cheapest < ClockModel.unreachable ? cheapest : 0
    }

    /// Caps how far the tail estimate simulates. Expanded can need twenty-odd
    /// victory points, and the estimate is a tie-break over a bounded horizon,
    /// not a plan - past a handful of repeats the extra precision buys nothing
    /// and costs a decision that is already the expensive part of a turn.
    static let maximumHeuristicRepeats = 8

    /// Expected turns to buy `purchase` `repeats` times in a row, spending the
    /// hand down as it goes and leaving production unchanged.
    ///
    /// Production only rises along a real route, so holding it flat keeps this
    /// an over-estimate of speed rather than an under-estimate - the direction
    /// that does not prune a route that was actually the best one.
    private static func costOfRepeating(
        _ purchase: RoutePurchase,
        _ repeats: Int,
        from node: RouteNode,
        expansion: RouteExpansion
    ) -> Double {
        var walker = node
        var total = 0.0
        for _ in 0..<max(1, repeats) {
            let step = expansion.cost(of: purchase, from: walker)
            guard step < ClockModel.unreachable else { return ClockModel.unreachable }
            total += step
            walker.spend(expansion.price(of: purchase))
        }
        return total
    }

    private static func victoryPointGain(of purchase: RoutePurchase, in context: RouteContext) -> Double {
        switch purchase {
        case .settlement:
            return Double(context.rules.victoryPoints(for: .settlement))
        case .city:
            return Double(context.rules.victoryPoints(for: .city) - context.rules.victoryPoints(for: .settlement))
        case .devCard:
            return context.devCardVictoryPointChance
        case .road:
            return 0
        }
    }

    // MARK: - Exact search (the test oracle)

    /// Uniform-cost search over the same graph.
    ///
    /// Exists to test `planByBeam`, not to run in a game. On a truncated
    /// problem the two must return the same expected turns; if they diverge,
    /// the beam is pruning something it should not. "The numbers look
    /// plausible" is not a correctness gate, and this is.
    ///
    /// Returns `Route.unreachable` if the node limit is hit, rather than a
    /// wrong answer.
    public static func planExactly(
        _ expansion: RouteExpansion,
        settings: RoutePlannerSettings = .default
    ) -> Route {
        let context = expansion.context
        let start = RouteNode.start(from: context)
        guard start.victoryPoints < Double(context.victoryPointTarget) else {
            return Route(purchases: [], expectedTurns: 0)
        }

        var frontier = MinHeap()
        frontier.push(SearchEntry(node: start, cost: 0, path: []))
        var settledCost: [RouteNode: Double] = [start: 0]
        var settled = 0

        while let entry = frontier.pop() {
            settled += 1
            guard settled <= settings.exactNodeLimit else { return .unreachable }
            if entry.node.victoryPoints >= Double(context.victoryPointTarget) {
                return Route(purchases: entry.path, expectedTurns: entry.cost)
            }
            if let known = settledCost[entry.node], known < entry.cost { continue }

            for successor in expansion.successors(of: entry.node) {
                let cost = entry.cost + successor.cost
                guard cost < ClockModel.unreachable else { continue }
                if let known = settledCost[successor.node], known <= cost { continue }
                settledCost[successor.node] = cost
                frontier.push(
                    SearchEntry(node: successor.node, cost: cost, path: entry.path + [successor.purchase])
                )
            }
        }
        return .unreachable
    }
}

/// One partial route under consideration.
struct SearchEntry: Sendable {
    let node: RouteNode
    let cost: Double
    let path: [RoutePurchase]
}

/// A binary heap ordered by cost, then by path length, then by the purchase
/// sequence itself.
///
/// The tie-breaks are not cosmetic: two routes can cost exactly the same
/// number of expected turns, and popping them in an order that depends on
/// insertion history would make the planner's answer depend on the order
/// `Dictionary` and `Set` happened to enumerate - which Swift seeds per
/// process. Ordering fully on the entry's own contents keeps the result a pure
/// function of the position.
struct MinHeap {
    private var storage: [SearchEntry] = []

    var isEmpty: Bool { storage.isEmpty }

    static func precedes(_ lhs: SearchEntry, _ rhs: SearchEntry) -> Bool {
        if lhs.cost != rhs.cost { return lhs.cost < rhs.cost }
        if lhs.path.count != rhs.path.count { return lhs.path.count < rhs.path.count }
        for (left, right) in zip(lhs.path, rhs.path) where left != right {
            return left.rawValue < right.rawValue
        }
        return false
    }

    mutating func push(_ entry: SearchEntry) {
        storage.append(entry)
        var child = storage.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard MinHeap.precedes(storage[child], storage[parent]) else { break }
            storage.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> SearchEntry? {
        guard !storage.isEmpty else { return nil }
        storage.swapAt(0, storage.count - 1)
        let smallest = storage.removeLast()
        var parent = 0
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var best = parent
            if left < storage.count, MinHeap.precedes(storage[left], storage[best]) { best = left }
            if right < storage.count, MinHeap.precedes(storage[right], storage[best]) { best = right }
            guard best != parent else { break }
            storage.swapAt(parent, best)
            parent = best
        }
        return smallest
    }
}
