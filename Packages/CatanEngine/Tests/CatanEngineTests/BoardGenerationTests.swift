import Testing
@testable import CatanEngine

@Test func standardBoardHas19TilesAndOneDesert() {
    let board = BoardGenerator.standard()
    #expect(board.tiles.count == 19)
    #expect(board.tiles.filter { $0.kind == .desert }.count == 1)
}

@Test func standardBoardHasNoAdjacentSixOrEight() {
    let board = BoardGenerator.standard()
    let hot = board.tiles.filter { $0.numberToken == 6 || $0.numberToken == 8 }
    for tile in hot {
        for dir in 0..<6 {
            let n = tile.coordinate.neighbor(dir)
            if let neighborTile = board.tiles.first(where: { $0.coordinate == n }) {
                #expect(!(neighborTile.numberToken == 6 || neighborTile.numberToken == 8))
            }
        }
    }
}

@Test func randomizedBoardIsDeterministicForSameSeed() {
    let b1 = BoardGenerator.randomized(seed: 42)
    let b2 = BoardGenerator.randomized(seed: 42)
    #expect(b1.tiles.map(\.coordinate) == b2.tiles.map(\.coordinate))
    #expect(b1.tiles.map(\.numberToken) == b2.tiles.map(\.numberToken))
}

@Test func boardHas9Ports() {
    #expect(BoardGenerator.standard().ports.count == 9)
}

@Test func vertexCanonicalizationIsConsistentAcrossSharedTiles() {
    let board = BoardGenerator.standard()
    // Every on-board edge's two vertices must each be in onBoardVertices.
    for edge in board.onBoardEdges {
        #expect(board.onBoardVertices.contains(edge.a))
        #expect(board.onBoardVertices.contains(edge.b))
    }
}

// MARK: BoardShape

@Test func classicShapeReproducesTheStandardBoardExactly() {
    let viaShape = BoardGenerator.standard(BoardShape.classic)
    let original = BoardGenerator.standard()
    #expect(viaShape.tiles == original.tiles)
    #expect(viaShape.ports == original.ports)
    #expect(viaShape.onBoardVertices == original.onBoardVertices)
    #expect(viaShape.onBoardEdges == original.onBoardEdges)
    #expect(viaShape.robberTile == original.robberTile)
}

@Test func tileCountFollowsTheHexFormulaAtEveryRadius() {
    // 3r^2 + 3r + 1
    #expect(BoardShape.tileCount(radius: 0) == 1)
    #expect(BoardShape.tileCount(radius: 2) == 19)
    #expect(BoardShape.tileCount(radius: 3) == 37)
    #expect(BoardShape.tileCount(radius: 12) == 469)
    #expect(BoardShape.tileCount(radius: 18) == 1_027)
}

@Test func aCompositionExpandsToExactlyTheDeclaredCounts() {
    let shape = BoardShape(
        radius: 3,
        terrain: .counts([.desert: 1, .resource(.grain): 12, .resource(.ore): 24]),
        tokens: .counts([6: 18, 8: 18]),
        ports: .derived(kinds: [.generic, .generic])
    )
    let board = BoardGenerator.standard(shape)
    #expect(board.tiles.count == 37)
    #expect(board.tiles.filter { $0.kind == .desert }.count == 1)
    #expect(board.tiles.filter { $0.kind == .resource(.grain) }.count == 12)
    #expect(board.tiles.filter { $0.kind == .resource(.ore) }.count == 24)
    #expect(board.tiles.compactMap(\.numberToken).count == 36)
}

@Test func aCompositionThatDoesNotFillTheBoardIsRejected() {
    // 10 tiles declared for a 37-tile radius. Trapping here beats dealing a
    // board with silent holes in it.
    #expect(BoardShape(radius: 3, terrain: .counts([.desert: 10]),
                       tokens: .counts([:]), ports: .derived(kinds: []))
        .compositionProblem != nil)
}

@Test func aCountedCompositionExpandsToOnePinnedInterleavedOrder() {
    // Pinned, not merely "some permutation": `counts` is a dictionary, and
    // Swift seeds dictionary iteration order per process, so an expansion that
    // let that order through would deal a different board every launch of the
    // same seed. Each test process gets a fresh hash seed, so this literal
    // fails such a regression rather than flaking on it.
    let terrain = TerrainComposition.counts(
        [.desert: 1, .resource(.brick): 2, .resource(.grain): 3]
    )
    #expect(terrain.expanded(tileCount: 6) == [
        .resource(.grain), .resource(.brick), .desert,
        .resource(.grain), .resource(.brick), .resource(.grain),
    ])
    #expect(TokenComposition.counts([6: 3, 8: 3]).expanded(count: 6) == [6, 8, 6, 8, 6, 8])
}

@Test func aTokenCountThatMissesTheProducingTilesIsRejected() {
    let shape = BoardShape(
        radius: 2,
        terrain: .counts([.desert: 1, .resource(.grain): 18]),
        tokens: .counts([6: 3]),
        ports: .derived(kinds: [])
    )
    #expect(shape.compositionProblem != nil)
}

@Test func derivedPortsSitOnDistinctCoastalEdgesOfTheBoard() {
    let shape = BoardShape(
        radius: 2,
        terrain: .counts([.desert: 1, .resource(.grain): 18]),
        tokens: .counts([6: 18]),
        ports: .derived(kinds: [.generic, .resource(.ore), .generic, .resource(.wool)])
    )
    let board = BoardGenerator.standard(shape)
    #expect(board.ports.count == 4)
    #expect(board.ports.map(\.kind) == [.generic, .resource(.ore), .generic, .resource(.wool)])
    let edges = board.ports.map { EdgeID($0.vertexA, $0.vertexB) }
    #expect(Set(edges).count == 4)
    for edge in edges {
        #expect(board.onBoardEdges.contains(edge))
    }
}
