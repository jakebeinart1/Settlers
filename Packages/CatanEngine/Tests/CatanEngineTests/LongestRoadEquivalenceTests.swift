import Testing
import Foundation
@testable import CatanEngine

/// Proves the fast longest-road search returns EXACTLY what the exhaustive one
/// returns, across randomly generated networks.
///
/// Equality is the requirement, not approximation: this function decides games,
/// and every seeded fingerprint in the repo is pinned to its answers. A
/// disagreement on any generated network is a bug in the new algorithm, never
/// an acceptable difference.
private func randomNetwork(seed: UInt64, roadCount: Int, blockedCount: Int)
    -> (GameState, Player) {
    var rng = RandomSource(seed: seed)
    let board = BoardGenerator.randomized(seed: seed)
    var state = GameSetup.newGame(board: board, seed: seed)
    let edges = board.onBoardEdges.sorted()
    let vertices = board.onBoardVertices.sorted()

    // Grow from a random seed edge so the network is CONNECTED often enough to
    // be interesting, but jump to a fresh edge sometimes so disconnected
    // components and cycles both occur.
    var roads = Set<EdgeID>()
    var frontier: [VertexID] = []
    while roads.count < min(roadCount, edges.count) {
        let candidates: [EdgeID]
        if frontier.isEmpty || Int.random(in: 0..<5, using: &rng) == 0 {
            candidates = edges.filter { !roads.contains($0) }
        } else {
            let from = frontier[Int.random(in: 0..<frontier.count, using: &rng)]
            candidates = edges.filter { !roads.contains($0) && ($0.a == from || $0.b == from) }
        }
        guard let pick = candidates.isEmpty ? edges.filter({ !roads.contains($0) }).first
                                            : candidates[Int.random(in: 0..<candidates.count, using: &rng)]
        else { break }
        roads.insert(pick)
        frontier.append(pick.a); frontier.append(pick.b)
    }
    state.players[0].roads = roads
    // Opponent buildings that cut the network.
    var blocked = Set<VertexID>()
    while blocked.count < blockedCount && blocked.count < vertices.count {
        blocked.insert(vertices[Int.random(in: 0..<vertices.count, using: &rng)])
    }
    // Split the blockers across settlements AND cities: both sides of the
    // comparison union the two, so a bug that read only one of them would
    // otherwise go unseen. Every network is all-settlement, all-city, or a
    // mix, chosen by seed so the split is reproducible.
    let ordered = blocked.sorted()
    switch seed % 3 {
    case 0: state.players[1].settlements = blocked
    case 1: state.players[1].cities = blocked
    default:
        state.players[1].settlements = Set(ordered.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element))
        state.players[1].cities = Set(ordered.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element))
    }
    return (state, state.players[0])
}

@Test func fastSearchAgreesWithTheExhaustiveOneOnManyRandomNetworks() {
    var checked = 0
    for seed in UInt64(1)...300 {
        for roadCount in [1, 3, 5, 8, 12, 15, 18, 22] {
            for blockedCount in [0, 2, 5] {
                let (state, player) = randomNetwork(seed: seed, roadCount: roadCount,
                                                    blockedCount: blockedCount)
                let fast = LongestRoad.length(for: player, in: state)
                let reference = LongestRoad.referenceLongestPath(for: player, in: state)
                #expect(fast == reference,
                        "seed \(seed), \(roadCount) roads, \(blockedCount) blocked: fast \(fast) != reference \(reference)")
                checked += 1
            }
        }
    }
    #expect(checked >= 7_000, "equivalence sweep covered only \(checked) networks")
}

@Test func fastSearchHandlesTheShapesThatBreakNaiveSearches() {
    // A closed loop of roads around one hex: a cycle, so the tree shortcut
    // must NOT be taken.
    let board = BoardGenerator.standard()
    var state = GameSetup.newGame(board: board, seed: 1)
    let hex = board.tiles[0].coordinate
    state.players[0].roads = Set(HexGeometry.edges(of: hex))
    #expect(LongestRoad.length(for: state.players[0], in: state)
            == LongestRoad.referenceLongestPath(for: state.players[0], in: state))

    // Two disconnected clusters: the answer is the longer one, never the sum.
    var disjoint = GameSetup.newGame(board: board, seed: 2)
    let edges = board.onBoardEdges.sorted()
    disjoint.players[0].roads = Set(edges.prefix(3)).union(Set(edges.suffix(4)))
    #expect(LongestRoad.length(for: disjoint.players[0], in: disjoint)
            == LongestRoad.referenceLongestPath(for: disjoint.players[0], in: disjoint))

    // An empty network.
    var empty = GameSetup.newGame(board: board, seed: 3)
    empty.players[0].roads = []
    #expect(LongestRoad.length(for: empty.players[0], in: empty) == 0)
}

/// The sweep above stops at 22 roads because the oracle's cost doubles every
/// few roads and 300 seeds of it is already the slowest test in the package.
/// But 30 is the road cap a player can actually reach, so the sizes that
/// matter most in play would otherwise be compared at no size at all. This
/// covers 26 and 30 over few enough seeds to stay affordable. 60 seeds rather
/// than a handful because the generator produces mostly acyclic networks at
/// this size - measured, only 6 of the first 80 contain a cycle - so a smaller
/// sweep would barely exercise the branch-and-bound path at all. It costs
/// ~1.2s, against ~15s for the sweep above.
@Test func fastSearchAgreesWithTheExhaustiveOneAtThePlayableRoadCap() {
    var checked = 0
    for seed in UInt64(1)...60 {
        for roadCount in [26, 30] {
            for blockedCount in [0, 3] {
                let (state, player) = randomNetwork(seed: seed, roadCount: roadCount,
                                                    blockedCount: blockedCount)
                let fast = LongestRoad.length(for: player, in: state)
                let reference = LongestRoad.referenceLongestPath(for: player, in: state)
                #expect(fast == reference,
                        "seed \(seed), \(roadCount) roads, \(blockedCount) blocked: fast \(fast) != reference \(reference)")
                checked += 1
            }
        }
    }
    #expect(checked == 240, "playable-cap sweep covered only \(checked) networks")
}
