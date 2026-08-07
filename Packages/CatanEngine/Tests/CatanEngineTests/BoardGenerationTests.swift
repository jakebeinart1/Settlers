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
