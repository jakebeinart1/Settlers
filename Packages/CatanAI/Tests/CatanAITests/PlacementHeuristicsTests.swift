import Testing
import CatanEngine
@testable import CatanAI

@Test func highPipVertexScoresHigherThanLowPipVertex() {
    let hotTiles = [
        Tile(coordinate: HexCoordinate(q: 0, r: 0), kind: .resource(.grain), numberToken: 6),
        Tile(coordinate: HexCoordinate(q: 1, r: 0), kind: .resource(.ore), numberToken: 8),
        Tile(coordinate: HexCoordinate(q: 1, r: -1), kind: .resource(.wool), numberToken: 5),
    ]
    let coldTiles = [
        Tile(coordinate: HexCoordinate(q: -5, r: 0), kind: .resource(.grain), numberToken: 2),
        Tile(coordinate: HexCoordinate(q: -4, r: 0), kind: .resource(.ore), numberToken: 12),
        Tile(coordinate: HexCoordinate(q: -4, r: -1), kind: .resource(.wool), numberToken: 3),
    ]

    let hotVertex = VertexID(touchingTiles: Set(hotTiles.map(\.coordinate)))
    let coldVertex = VertexID(touchingTiles: Set(coldTiles.map(\.coordinate)))

    let board = Board(
        tiles: hotTiles + coldTiles,
        ports: [],
        onBoardVertices: [hotVertex, coldVertex],
        onBoardEdges: [],
        robberTile: HexCoordinate(q: 100, r: 100)
    )

    let hotScore = PlacementHeuristics.score(vertex: hotVertex, board: board)
    let coldScore = PlacementHeuristics.score(vertex: coldVertex, board: board)
    #expect(hotScore > coldScore)
}
