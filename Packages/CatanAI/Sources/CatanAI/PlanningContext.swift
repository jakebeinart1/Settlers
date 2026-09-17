import CatanEngine

/// The facts `BuildPlanner.score` needs that are the same for every candidate
/// move in one decision, computed at most once instead of once per candidate.
///
/// ## Why this exists
/// `chooseBuild` scores every legal move, and a `.buildRoad` score used to
/// recompute, per edge: the whole table's occupied vertices (once per vertex
/// it tested), every opponent's `immediateFrontier`, this player's
/// `expansionTarget` (a four-hop search) and a board-wide BFS from it. None of
/// those can change while the loop runs - `state` is a value and nothing in
/// the loop mutates it - so the work was the same answer recomputed tens of
/// times per decision, and it grew with the board: measured over five seeded
/// four-bot games, 1.9ms per move on the 19-tile Classic board against 13.5ms
/// on the 61-tile Vast one, where `chooseBuild` was 63% of the whole process.
///
/// ## Why a class, and why lazily
/// A class so one instance threads through the scoring loop by reference and
/// every entry filled by one candidate is already there for the next. Lazily,
/// because a decision with no road candidate must not pay for an
/// `expansionTarget` nobody asked for - the cheapest decisions stay exactly as
/// cheap as they were.
///
/// ## Determinism
/// Every value here is a pure function of `state`, `player` and `weights`, and
/// the memo only changes *how often* each is computed, never what it answers.
/// Each cache is keyed by `PlayerID` or `VertexID`, never iterated, so no
/// result can depend on `Set`/`Dictionary` order - the property
/// `SeededGameFingerprintTests` pins. The five Classic and five Vast seeded
/// fingerprints are byte-identical before and after this file existed, which
/// is the check that it changed nothing but speed.
final class PlanningContext {
    let state: GameState
    let player: PlayerID
    let weights: BotWeights

    init(state: GameState, player: PlayerID, weights: BotWeights = .default) {
        self.state = state
        self.player = player
        self.weights = weights
    }

    /// Every vertex holding anyone's settlement or city.
    lazy var occupiedVertices: Set<VertexID> = Set(state.players.flatMap { $0.settlements.union($0.cities) })

    /// Whether `vertex` could ever legally hold a settlement right now - not
    /// already occupied by anyone, and not within the distance-rule radius of
    /// an existing settlement/city. A road's "leads to a good future spot"
    /// bonus (`bestReachable` in `.buildRoad`'s scoring) must only count
    /// vertices this is true for - otherwise a road pointing at an opponent's
    /// already-built settlement on a great tile scores just as high as one
    /// pointing at a genuinely open spot, even though the former can never
    /// actually be settled.
    func isBuildableVertex(_ vertex: VertexID) -> Bool {
        guard !occupiedVertices.contains(vertex) else { return false }
        return !state.board.adjacentVertices(of: vertex).contains { occupiedVertices.contains($0) }
    }

    private var immediateFrontiers: [PlayerID: Set<VertexID>] = [:]

    /// Vacant, currently-legal vertices `id` could reach with exactly one more
    /// road from anywhere in their existing settlements/cities/roads right now.
    /// See `BuildPlanner.immediateFrontier` for how it differs from
    /// `opponentFrontier`'s two-hops-out view.
    func immediateFrontier(for id: PlayerID) -> Set<VertexID> {
        if let cached = immediateFrontiers[id] { return cached }
        var frontier = Set<VertexID>()
        if let touched = networkVertices(for: id) {
            for vertex in Set(touched.flatMap { state.board.adjacentVertices(of: $0) })
            where isBuildableVertex(vertex) {
                frontier.insert(vertex)
            }
        }
        immediateFrontiers[id] = frontier
        return frontier
    }

    private var opponentFrontiers: [PlayerID: Set<VertexID>] = [:]

    /// `id`'s near-term expansion options, two hops out - a vertex directly
    /// adjacent to one of their own buildings is illegal for everyone under
    /// the distance rule, but roads are not, so they can road out to it and
    /// beyond. See `BuildPlanner.opponentFrontier` for the full rationale.
    func opponentFrontier(for id: PlayerID) -> Set<VertexID> {
        if let cached = opponentFrontiers[id] { return cached }
        var frontier = Set<VertexID>()
        if let touched = networkVertices(for: id) {
            for hop in Set(touched.flatMap { state.board.adjacentVertices(of: $0) }) {
                for candidate in state.board.adjacentVertices(of: hop)
                where !touched.contains(candidate) && isBuildableVertex(candidate) {
                    frontier.insert(candidate)
                }
            }
        }
        opponentFrontiers[id] = frontier
        return frontier
    }

    private var relativeWeights: [PlayerID: Double] = [:]

    /// `ThreatAssessment.relativeWeight`, which re-scores the whole table -
    /// including a longest-road search per player - on every call.
    func relativeWeight(for opponent: PlayerID) -> Double {
        if let cached = relativeWeights[opponent] { return cached }
        let weight = ThreatAssessment.relativeWeight(for: opponent, excluding: player, in: state, weights: weights)
        relativeWeights[opponent] = weight
        return weight
    }

    private var longestRoadLengths: [PlayerID: Int] = [:]

    /// `LongestRoad.length` for a player's CURRENT roads. Never a simulated
    /// build: those differ per candidate edge and are computed fresh.
    func longestRoadLength(for id: PlayerID) -> Int {
        if let cached = longestRoadLengths[id] { return cached }
        let length = state.players.first(where: { $0.id == id })
            .map { LongestRoad.length(for: $0, in: state) } ?? 0
        longestRoadLengths[id] = length
        return length
    }

    private var expansionTargetResolved = false
    private var resolvedExpansionTarget: VertexID?

    /// The single best vertex `player` could aim their road network toward
    /// right now - see `BuildPlanner.expansionTarget` for what "best" means
    /// and why the answer has to be stable across candidates.
    var expansionTarget: VertexID? {
        if expansionTargetResolved { return resolvedExpansionTarget }
        resolvedExpansionTarget = computeExpansionTarget()
        expansionTargetResolved = true
        return resolvedExpansionTarget
    }

    private var distances: [VertexID: [VertexID: Int]] = [:]

    /// Shortest hop-count from every board vertex to `target`, over the
    /// board's plain vertex-adjacency graph (ignores road ownership and
    /// legality - roads follow this same graph, so it is a fine distance proxy
    /// for "how many roads away").
    func distances(to target: VertexID) -> [VertexID: Int] {
        if let cached = distances[target] { return cached }
        var result: [VertexID: Int] = [target: 0]
        var frontier: Set<VertexID> = [target]
        var hop = 0
        while !frontier.isEmpty {
            hop += 1
            let next = Set(frontier.flatMap { state.board.adjacentVertices(of: $0) }).subtracting(result.keys)
            for vertex in next { result[vertex] = hop }
            frontier = next
        }
        distances[target] = result
        return result
    }

    /// Every vertex `id`'s network already touches: their settlements, their
    /// cities, and both ends of each of their roads. `nil` for an unknown
    /// seat, which the callers treat as an empty frontier.
    func networkVertices(for id: PlayerID) -> Set<VertexID>? {
        guard let seat = state.players.first(where: { $0.id == id }) else { return nil }
        var touched = seat.settlements.union(seat.cities)
        for edge in seat.roads {
            let (a, b) = state.board.vertices(of: edge)
            touched.insert(a)
            touched.insert(b)
        }
        return touched
    }

    private func computeExpansionTarget() -> VertexID? {
        guard let me = state.players.first(where: { $0.id == player }) else { return nil }
        var networkVertices = me.settlements.union(me.cities)
        // `investment[v]` counts the player's own already-built roads
        // touching `v` - carried forward through the hop search below (a
        // vertex discovered via a heavily-invested source inherits its
        // parent's count) so `expansionContinuityScale` can reward
        // candidates that extend a branch the bot has already committed
        // roads to, not just whichever frontier vertex scores marginally
        // highest this turn. Settlements/cities with no roads yet start at
        // `0`, same as any other network vertex - there's nothing to be
        // continuous *with* before the first road exists.
        var investment: [VertexID: Int] = [:]
        for edge in me.roads {
            let (a, b) = state.board.vertices(of: edge)
            networkVertices.insert(a)
            networkVertices.insert(b)
            investment[a, default: 0] += 1
            investment[b, default: 0] += 1
        }
        guard !networkVertices.isEmpty else { return nil }

        var visited = networkVertices
        var frontier = networkVertices
        var best: (vertex: VertexID, score: Double)?
        var hop = 1
        while hop <= weights.expansionTargetMaxHops && !frontier.isEmpty {
            let next = Set(frontier.flatMap { state.board.adjacentVertices(of: $0) }).subtracting(visited)
            var nextInvestment: [VertexID: Int] = [:]
            // Sorted, because the winner below is chosen by a strict `>` and
            // ties here are the common case, not a rare one:
            // `PlacementHeuristics.score` takes only a handful of discrete
            // values, so several frontier vertices routinely score the same.
            // Iterating a `Set` meant whichever one Swift's per-process hash
            // seed happened to yield first won - and that choice feeds
            // `committedPathBonus`, so it reaches every road score, then
            // `chooseBuild`'s tie pool, and desynchronises the RNG stream for
            // the rest of the game. One flipped tie cascades into a different
            // game from the same seed.
            for vertex in next.sorted() {
                // Inherit the highest investment among this vertex's
                // already-visited neighbors in `frontier` - the branch it's
                // reachable from with the most existing roads already
                // pointing at it, not summed across every possible parent
                // (summing would make a vertex reachable from two mediocre
                // branches beat one reachable from a single strong one).
                let inherited = state.board.adjacentVertices(of: vertex)
                    .filter { frontier.contains($0) }
                    .compactMap { investment[$0] }
                    .max() ?? 0
                nextInvestment[vertex] = inherited
                guard isBuildableVertex(vertex) else { continue }
                let production = PlacementHeuristics.score(vertex: vertex, board: state.board, weights: weights)
                let continuity = Double(inherited) * weights.expansionContinuityScale
                let discounted = production - Double(hop) * weights.expansionTargetHopPenalty + continuity
                if best == nil || discounted > best!.score {
                    best = (vertex, discounted)
                }
            }
            investment.merge(nextInvestment) { _, new in new }
            visited.formUnion(next)
            frontier = next
            hop += 1
        }
        return best?.vertex
    }
}
