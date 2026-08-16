import Testing
import CatanEngine
@testable import CatanAI

/// Walks `length` edges out from an arbitrary starting vertex, greedily
/// picking an unvisited neighbor each step - a real connected road chain on
/// `board`, for tests that need one without hand-writing coordinates. Copied
/// from `BuildPlannerTests.swift` since Swift Testing files don't share
/// private helpers across files.
private func buildChain(from board: Board, length: Int) -> [EdgeID] {
    var edges: [EdgeID] = []
    var visited = Set<VertexID>()
    var current = board.onBoardVertices.sorted().first!
    visited.insert(current)
    for _ in 0..<length {
        guard let next = board.adjacentVertices(of: current).first(where: { !visited.contains($0) }) else { break }
        guard let edge = board.edgesTouching(current).first(where: { edge in
            let (a, b) = board.vertices(of: edge)
            return a == next || b == next
        }) else { break }
        edges.append(edge)
        visited.insert(next)
        current = next
    }
    return edges
}

@Test func scoreWeighsVictoryPointsHeavily() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[0].settlements.insert(vertex)

    let withSettlement = ThreatAssessment.score(for: player, in: state)

    var noSettlement = state
    noSettlement.players[0].settlements.removeAll()
    let without = ThreatAssessment.score(for: player, in: noSettlement)

    // 1 VP difference must show up as (at least) the VP weight - other
    // components (production) also shift with the same settlement, so this
    // is a lower bound, not an exact diff.
    #expect(withSettlement - without >= 10.0)
}

@Test func scoreIncludesProductionStrengthWeightedByPips() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    // Pick the two vertices with the most differing pip-weighted production
    // among on-board vertices, so the test isn't sensitive to board layout.
    let scored = state.board.onBoardVertices.map { vertex in
        (vertex, PlacementHeuristics.score(vertex: vertex, board: state.board))
    }.sorted { $0.1 > $1.1 }
    let best = scored.first!
    let worst = scored.last!
    #expect(best.1 > worst.1, "test board too uniform to distinguish production")

    state.players[0].settlements = [best.0]
    let highProduction = ThreatAssessment.score(for: player, in: state)

    state.players[0].settlements = [worst.0]
    let lowProduction = ThreatAssessment.score(for: player, in: state)

    #expect(highProduction > lowProduction)
}

@Test func scoreCountsCityProductionAtDoubleWeight() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let vertex = state.board.onBoardVertices.sorted().first!

    state.players[0].settlements = [vertex]
    let settlementScore = ThreatAssessment.score(for: player, in: state)

    state.players[0].settlements = []
    state.players[0].cities = [vertex]
    let cityScore = ThreatAssessment.score(for: player, in: state)

    // City is worth +10 VP-equivalent (1 more VP than settlement, weighted
    // 10) plus double the production term versus a settlement on the same
    // vertex - so the gap must exceed the flat VP difference alone.
    let production = PlacementHeuristics.score(vertex: vertex, board: state.board)
    #expect(cityScore - settlementScore > 10.0)
    #expect(cityScore - settlementScore >= 10.0 + production - 0.001)
}

@Test func scoreIncludesHeldDevCardCount() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].devCards = [.knight, .knight]
    let withDevCards = ThreatAssessment.score(for: player, in: state)

    #expect(withDevCards - baseline == 3.0) // 1.5 per card
}

@Test func scoreAddsLargestArmySwingBonusWhenOneKnightAway() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].playedKnights = 2
    let oneAway = ThreatAssessment.score(for: player, in: state)

    #expect(oneAway - baseline == 2.5)
}

@Test func scoreSkipsLargestArmySwingBonusWhenHolderIsFarAhead() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)
    state.players[1].playedKnights = 5
    state.largestArmyPlayer = holder

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].playedKnights = 2
    let stillTwoAway = ThreatAssessment.score(for: player, in: state)

    // Reaching 3 knights wouldn't take Largest Army from a holder already at
    // 5, so no swing bonus applies.
    #expect(stillTwoAway - baseline == 0.0)
}

@Test func scoreAddsLongestRoadSwingBonusWhenOneSegmentFromQualifying() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)

    let chain = buildChain(from: state.board, length: 4)
    #expect(chain.count == 4, "test board too small to build a 4-edge chain")

    let baseline = ThreatAssessment.score(for: player, in: state)
    state.players[0].roads = Set(chain)
    let fourEdges = ThreatAssessment.score(for: player, in: state)

    #expect(fourEdges - baseline >= 2.5) // production from the new roads' vertices also shifts, so >=, not ==
}

@Test func scoreSkipsLongestRoadSwingBonusWhenFarBehindTheHolder() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let player = PlayerID(index: 0)
    let holder = PlayerID(index: 1)

    let holderChain = buildChain(from: state.board, length: 7)
    #expect(holderChain.count == 7, "test board too small to build a 7-edge chain")
    state.players[1].roads = Set(holderChain)
    state.longestRoadPlayer = holder

    let baseline = ThreatAssessment.score(for: player, in: state)
    let shortChain = buildChain(from: state.board, length: 4)
    state.players[0].roads = Set(shortChain)
    let stillBehind = ThreatAssessment.score(for: player, in: state)

    // 4 edges doesn't come close to beating a 7-edge holder, so no bonus -
    // any diff is purely from the roads' own production-adjacent vertices,
    // which the base score doesn't count at all (roads aren't settlements),
    // so this should be exactly 0.
    #expect(stillBehind - baseline == 0.0)
}

@Test func scoresExcludesTheGivenPlayerAndSortsHighestFirst() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex) // player 1 now clearly ahead

    let ranked = ThreatAssessment.scores(excluding: PlayerID(index: 0), in: state)

    #expect(!ranked.contains { $0.player == PlayerID(index: 0) })
    #expect(ranked.first?.player == PlayerID(index: 1))
    #expect(ranked.map(\.score) == ranked.map(\.score).sorted(by: >))
}

@Test func relativeWeightIsAboveOneForAnAboveAverageOpponent() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let vertex = state.board.onBoardVertices.sorted().first!
    state.players[1].settlements.insert(vertex)
    state.players[1].cities.insert(vertex)

    let weight = ThreatAssessment.relativeWeight(for: PlayerID(index: 1), excluding: PlayerID(index: 0), in: state)
    #expect(weight > 1.0)
}

@Test func relativeWeightIsOneForEveryoneWhenAllScoresAreZero() {
    let state = GameSetup.newGame(board: BoardGenerator.standard())
    for player in state.players where player.id != PlayerID(index: 0) {
        let weight = ThreatAssessment.relativeWeight(for: player.id, excluding: PlayerID(index: 0), in: state)
        #expect(weight == 1.0)
    }
}

@Test func relativeWeightClampsExtremeOutliers() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let vertex = state.board.onBoardVertices.sorted().first!
    // Player 1 gets a huge, artificial lead - real games can't produce
    // scores this lopsided, but the clamp must still hold.
    state.players[1].settlements.insert(vertex)
    state.players[1].cities.insert(vertex)
    state.players[1].devCards = Array(repeating: DevCardType.knight, count: 20)

    let weight = ThreatAssessment.relativeWeight(for: PlayerID(index: 1), excluding: PlayerID(index: 0), in: state)
    #expect(weight <= 3.0)

    let lowWeight = ThreatAssessment.relativeWeight(for: PlayerID(index: 2), excluding: PlayerID(index: 0), in: state)
    #expect(lowWeight >= 0.4)
}
