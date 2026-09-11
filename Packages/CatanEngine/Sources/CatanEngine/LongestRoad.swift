/// Computes which player (if any) currently holds the longest-road bonus.
public enum LongestRoad {
    /// The largest per-player road limit the search is measured to serve
    /// comfortably. `Ruleset.validationProblem` refuses a mode above this.
    ///
    /// Measured on the standard board's densest clump (every edge of each
    /// hex, centre outward — Task 1's method), mean of 20 calls: 32 roads
    /// 1.83ms, 35 roads 3.93ms, 38 roads 5.48ms, all stable across repeated
    /// runs. Probing further on the same generator found the branch-and-bound
    /// cliff at 44 roads (~235ms) with 43 still at ~7.8ms — 38 was kept as the
    /// candidate actually asked for, comfortably under the 20ms bar with a
    /// 5-road margin before that cliff. Raising it requires re-running that
    /// measurement and pasting the new numbers.
    public static let supportedRoadLimit = 38

    /// The player with the strict-longest continuous road of at least
    /// `state.rules.longestRoadMinimum` edges. Ties keep the current holder's
    /// bonus (per official rules); if there's no current holder and it's a
    /// tie, no one gets it.
    public static func compute(for state: GameState) -> PlayerID? {
        let lengths = state.players.map { ($0.id, longestPath(for: $0, in: state)) }
        guard let maxLength = lengths.map(\.1).max(),
              maxLength >= state.rules.longestRoadMinimum else { return nil }

        let leaders = lengths.filter { $0.1 == maxLength }.map { $0.0 }
        if leaders.count == 1 { return leaders[0] }
        if let holder = state.longestRoadPlayer, leaders.contains(holder) { return holder }
        return nil
    }

    /// Public wrapper around `longestPath(for:in:)` - the length (in edges)
    /// of `player`'s own longest continuous road right now, same figure
    /// `compute(for:)` compares across players to award the bonus. UI
    /// layers read this for each player's "roads" stat, rather than a raw
    /// `player.roads.count` (total segments built), since the latter
    /// doesn't answer "how close is this player to/holding longest road" -
    /// a heavily-forked network can have many more segments built than its
    /// actual longest stretch.
    public static func length(for player: Player, in state: GameState) -> Int {
        longestPath(for: player, in: state)
    }

    /// The longest continuous road `player` has, cut at any vertex holding an
    /// opposing settlement or city.
    ///
    /// Precisely: the longest *trail* - each road used at most once, but a
    /// vertex may be passed through twice where a cycle allows it, which is
    /// what the reference implementation permits (it marks edges visited,
    /// never vertices) and therefore what this must permit too.
    ///
    /// Longest path is NP-hard in general, so this does not find a clever
    /// formula - it removes work that never needed doing:
    ///
    /// 1. **Split at blocked vertices.** A road may END at an opponent's
    ///    building but never continue through it, so a blocked vertex is
    ///    duplicated into one copy per incident edge. That is exactly
    ///    equivalent to the old rule and it breaks one tangled graph into
    ///    several small ones.
    /// 2. **Decompose into connected components.** Separate clusters cannot
    ///    form one path, so the answer is the maximum over components rather
    ///    than a search across all of them at once.
    /// 3. **A component with no cycle is a tree** - the common case for real
    ///    road networks - and a tree's longest road is its diameter, found by
    ///    two linear traversals with no search at all.
    /// 4. **Only a component containing a cycle searches**, and then under
    ///    branch-and-bound: a branch is abandoned as soon as its length plus
    ///    the most it could still add (`CycleSearch.upperBound`) cannot beat
    ///    the best answer so far.
    ///
    /// Measured against the oracle on the densest 4-player road clump the
    /// standard board admits: 80.6ms -> 4.9ms at 30 roads, 719.6ms -> 45.5ms
    /// at 40. It is still exponential in the worst case - it has to be - so a
    /// ruleset with a road limit far above 40 will want another look here,
    /// most likely contracting runs of degree-2 vertices into single weighted
    /// roads before searching. The allocations would want attention in the same
    /// pass: `CycleSearch.init` and `farthest` each size their scratch arrays to
    /// the WHOLE graph rather than to the component in hand, which is free at 30
    /// roads and O(components x vertices) of pure allocation once a network has
    /// hundreds of both.
    ///
    /// Proven equal to `referenceLongestPath` across thousands of generated
    /// networks by `LongestRoadEquivalenceTests`. If those ever disagree, this
    /// function is wrong - the oracle is the definition.
    private static func longestPath(for player: Player, in state: GameState) -> Int {
        guard !player.roads.isEmpty else { return 0 }
        let graph = RoadGraph(for: player, in: state)

        var best = 0
        for component in graph.components() {
            // A component can never yield a road longer than its own edge
            // count, so one that cannot beat the leader is skipped outright.
            let edgeCount = graph.edgeCount(of: component)
            guard edgeCount > best else { continue }

            // The two-sweep walk is the exact answer for a tree and a real
            // (if short) road otherwise, so it doubles as the search's opening
            // incumbent - starting the bound at a genuine length rather than
            // at zero is what stops the first branch exploring everything.
            let sweep = max(best, graph.twoSweepPath(in: component))
            if edgeCount == component.count - 1 {
                best = sweep
            } else {
                var search = CycleSearch(graph: graph, best: sweep)
                best = search.longestTrail(in: component, edgeCount: edgeCount)
            }
        }
        return best
    }

    // MARK: - The split road graph

    /// One endpoint of one road after the blocked-vertex split. An unblocked
    /// vertex always uses `copy: 0`, so every road meeting there meets the same
    /// node; a blocked vertex uses a distinct copy per incident road, which
    /// leaves each of those copies with degree 1 - reachable as an endpoint,
    /// never traversable.
    private struct SplitVertex: Hashable {
        let vertex: VertexID
        let copy: Int
    }

    /// `player`'s roads as a numbered graph: nodes are `SplitVertex`es mapped
    /// to dense integers, edges are indices into `player.roads.sorted()`.
    ///
    /// Integer nodes and edges are not micro-optimisation for its own sake -
    /// they are what lets every traversal below use arrays rather than
    /// dictionaries, so no result can depend on `Set`/`Dictionary` iteration
    /// order, which Swift seeds per process.
    private struct RoadGraph {
        /// `adjacency[node]` lists `(edge index, neighbour node)`, appended in
        /// sorted-road order and therefore identical on every launch.
        private(set) var adjacency: [[(edge: Int, neighbor: Int)]] = []
        /// Total roads, i.e. the number of valid edge indices.
        private(set) var roadCount = 0

        init(for player: Player, in state: GameState) {
            var blocked = Set<VertexID>()
            for other in state.players where other.id != player.id {
                blocked.formUnion(other.settlements)
                blocked.formUnion(other.cities)
            }
            var ids: [SplitVertex: Int] = [:]
            for (index, edge) in player.roads.sorted().enumerated() {
                let (a, b) = state.board.vertices(of: edge)
                let left = node(a, road: index, blocked: blocked, ids: &ids)
                let right = node(b, road: index, blocked: blocked, ids: &ids)
                adjacency[left].append((index, right))
                adjacency[right].append((index, left))
                roadCount += 1
            }
        }

        private mutating func node(_ vertex: VertexID, road: Int,
                                   blocked: Set<VertexID>, ids: inout [SplitVertex: Int]) -> Int {
            let key = SplitVertex(vertex: vertex, copy: blocked.contains(vertex) ? road + 1 : 0)
            if let existing = ids[key] { return existing }
            ids[key] = adjacency.count
            adjacency.append([])
            return adjacency.count - 1
        }

        /// Node ids grouped by connected component, each group sorted so the
        /// traversals that consume it start from the same place every run.
        func components() -> [[Int]] {
            var seen = [Bool](repeating: false, count: adjacency.count)
            var result: [[Int]] = []
            for start in adjacency.indices where !seen[start] {
                seen[start] = true
                var stack = [start]
                var members: [Int] = []
                while let node = stack.popLast() {
                    members.append(node)
                    for (_, neighbor) in adjacency[node] where !seen[neighbor] {
                        seen[neighbor] = true
                        stack.append(neighbor)
                    }
                }
                result.append(members.sorted())
            }
            return result
        }

        /// Every road in a component is listed once at each of its two ends, so
        /// the degree sum is exactly twice the road count.
        func edgeCount(of component: [Int]) -> Int {
            component.reduce(0) { $0 + adjacency[$1].count } / 2
        }

        /// BFS to the farthest node from any start, then BFS again from
        /// there. For a tree that is exactly the diameter, and so exactly the
        /// longest road. For a component with a cycle it is the length of a
        /// real shortest path between two far-apart nodes - not the maximum,
        /// but a genuine lower bound the search can start from.
        func twoSweepPath(in component: [Int]) -> Int {
            farthest(from: farthest(from: component[0]).node).distance
        }

        private func farthest(from start: Int) -> (node: Int, distance: Int) {
            var distance = [Int](repeating: -1, count: adjacency.count)
            distance[start] = 0
            var queue = [start]
            var head = 0
            var best = (node: start, distance: 0)
            while head < queue.count {
                let node = queue[head]
                head += 1
                if distance[node] > best.distance { best = (node, distance[node]) }
                for (_, neighbor) in adjacency[node] where distance[neighbor] < 0 {
                    distance[neighbor] = distance[node] + 1
                    queue.append(neighbor)
                }
            }
            return best
        }
    }

    // MARK: - Branch-and-bound search, for components that contain a cycle

    /// Exhaustive edge-distinct walk search over ONE component, pruned by an
    /// upper bound. Only components with a cycle reach here; a cycle is also
    /// the only reason a walk may revisit a vertex, which the reference
    /// implementation permits (it marks edges visited, never vertices) and this
    /// therefore must permit too.
    private struct CycleSearch {
        private let graph: RoadGraph
        private var visited: [Bool]
        private var best: Int
        /// Scratch for `upperBound`. `stamp[x] == generation` means "already
        /// counted during the current bound", which makes each bound
        /// O(component) with no per-call allocation and no array clearing.
        private var nodeStamp: [Int]
        private var edgeStamp: [Int]
        private var generation = 0
        private var queue: [Int] = []

        init(graph: RoadGraph, best: Int) {
            self.graph = graph
            self.best = best
            visited = [Bool](repeating: false, count: graph.roadCount)
            nodeStamp = [Int](repeating: 0, count: graph.adjacency.count)
            edgeStamp = [Int](repeating: 0, count: graph.roadCount)
        }

        mutating func longestTrail(in component: [Int], edgeCount: Int) -> Int {
            for start in component {
                explore(from: start, length: 0)
                if best >= edgeCount { break }
            }
            return best
        }

        /// Recursion depth is bounded by the component's road count, since every
        /// level consumes one road - a few hundred frames at the largest piece
        /// limit any ruleset permits, far inside the default stack.
        private mutating func explore(from node: Int, length: Int) {
            best = max(best, length)
            // Nothing below this node can beat the leader if even the most
            // optimistic continuation would not, so abandon the branch.
            guard length + upperBound(from: node) > best else { return }
            for (edge, neighbor) in graph.adjacency[node] where !visited[edge] {
                visited[edge] = true
                explore(from: neighbor, length: length + 1)
                visited[edge] = false
            }
        }

        /// The most roads any continuation from `node` could still use.
        ///
        /// Two independent limits, whichever is smaller:
        ///
        /// - **Reach.** Only unvisited roads reachable from `node` can be used
        ///   at all.
        /// - **Parity.** The roads a continuation adds form a trail from
        ///   `node` to wherever it stops, so in that trail every vertex has
        ///   even degree except those two ends. A vertex with three unused
        ///   roads left can therefore contribute only two of them - and a
        ///   board vertex never has more than three roads, so this is the
        ///   binding limit almost everywhere. Summing the per-vertex even caps
        ///   and halving (degrees double-count edges), plus one for each of
        ///   the two ends, bounds the trail far more tightly than reach does:
        ///   on a 40-road clump it reads 21 where reach reads 40.
        ///
        /// Both are upper bounds on a real trail, so pruning on them cannot
        /// discard the true maximum.
        private mutating func upperBound(from node: Int) -> Int {
            generation += 1
            nodeStamp[node] = generation
            queue.removeAll(keepingCapacity: true)
            queue.append(node)
            var reach = 0
            var evenCapSum = 0
            var oddAtStart = 0
            var oddElsewhere = 0
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                var degree = 0
                for (edge, neighbor) in graph.adjacency[current] where !visited[edge] {
                    degree += 1
                    if edgeStamp[edge] != generation {
                        edgeStamp[edge] = generation
                        reach += 1
                    }
                    if nodeStamp[neighbor] != generation {
                        nodeStamp[neighbor] = generation
                        queue.append(neighbor)
                    }
                }
                evenCapSum += degree - degree % 2
                // The trail's two ends are the only vertices allowed an odd
                // degree, and only a vertex with an odd number of roads left
                // can take that allowance.
                if degree % 2 == 1 {
                    if current == node { oddAtStart = 1 } else { oddElsewhere = 1 }
                }
            }
            return min(reach, (evenCapSum + oddAtStart + oddElsewhere) / 2)
        }
    }

    /// The pre-2026-09-10 exhaustive search, kept verbatim as the correctness
    /// oracle for `longestPath`. Exponential in road count (measured on a dense
    /// network: 1.6ms at 15 roads, 80.6ms at 30, 719.6ms at 40), which is why
    /// it is no longer the one that runs - but it is simple enough to be
    /// obviously correct, which is exactly what an oracle needs to be.
    ///
    /// Not `private` so `LongestRoadEquivalenceTests` can compare against it.
    /// Nothing in production may call this.
    ///
    /// The longest simple path through `player`'s road-edge graph, cut at
    /// any vertex owned by an opposing settlement/city (the road can't
    /// continue through an opponent's building, but the segments up to it
    /// still count).
    static func referenceLongestPath(for player: Player, in state: GameState) -> Int {
        guard !player.roads.isEmpty else { return 0 }

        var adjacency: [VertexID: [(edge: EdgeID, neighbor: VertexID)]] = [:]
        for edge in player.roads {
            let (a, b) = state.board.vertices(of: edge)
            adjacency[a, default: []].append((edge, b))
            adjacency[b, default: []].append((edge, a))
        }

        var blocked = Set<VertexID>()
        for other in state.players where other.id != player.id {
            blocked.formUnion(other.settlements)
            blocked.formUnion(other.cities)
        }

        var best = 0
        for start in adjacency.keys {
            var visitedEdges = Set<EdgeID>()
            dfs(from: start, adjacency: adjacency, blocked: blocked, visitedEdges: &visitedEdges, length: 0, best: &best)
        }
        return best
    }

    private static func dfs(
        from vertex: VertexID,
        adjacency: [VertexID: [(edge: EdgeID, neighbor: VertexID)]],
        blocked: Set<VertexID>,
        visitedEdges: inout Set<EdgeID>,
        length: Int,
        best: inout Int
    ) {
        best = max(best, length)
        // A blocked (opponent-owned) vertex can be a segment's starting
        // point (length == 0) but the road can't continue past it.
        guard length == 0 || !blocked.contains(vertex) else { return }

        for (edge, neighbor) in adjacency[vertex] ?? [] {
            guard !visitedEdges.contains(edge) else { continue }
            visitedEdges.insert(edge)
            dfs(from: neighbor, adjacency: adjacency, blocked: blocked, visitedEdges: &visitedEdges, length: length + 1, best: &best)
            visitedEdges.remove(edge)
        }
    }
}
