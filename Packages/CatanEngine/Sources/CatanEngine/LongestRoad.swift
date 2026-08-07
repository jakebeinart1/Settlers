/// Computes which player (if any) currently holds the longest-road bonus.
public enum LongestRoad {
    private static let minimumLength = 5

    /// The player with the strict-longest continuous road of at least
    /// `minimumLength` edges. Ties keep the current holder's bonus (per
    /// official rules); if there's no current holder and it's a tie, no one
    /// gets it.
    public static func compute(for state: GameState) -> PlayerID? {
        let lengths = state.players.map { ($0.id, longestPath(for: $0, in: state)) }
        guard let maxLength = lengths.map(\.1).max(), maxLength >= minimumLength else { return nil }

        let leaders = lengths.filter { $0.1 == maxLength }.map { $0.0 }
        if leaders.count == 1 { return leaders[0] }
        if let holder = state.longestRoadPlayer, leaders.contains(holder) { return holder }
        return nil
    }

    /// The longest simple path through `player`'s road-edge graph, cut at
    /// any vertex owned by an opposing settlement/city (the road can't
    /// continue through an opponent's building, but the segments up to it
    /// still count).
    private static func longestPath(for player: Player, in state: GameState) -> Int {
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
