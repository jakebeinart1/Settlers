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

/// Two vertices with identical raw pip production - one touches only a
/// resource the player's first settlement already covers, the other
/// touches a resource that's still new. Scoring the second settlement
/// against the first's coverage should favor the new-resource vertex, even
/// though it doesn't with no `alreadyCovered` set (a real setup-placement
/// priority the plain pip/diversity score alone doesn't capture).
@Test func alreadyCoveredResourceScoresLowerThanNewResourceAtEqualPips() {
    let repeatTiles = [Tile(coordinate: HexCoordinate(q: 0, r: 0), kind: .resource(.grain), numberToken: 6)]
    let newTiles = [Tile(coordinate: HexCoordinate(q: 5, r: 0), kind: .resource(.ore), numberToken: 6)]

    let repeatVertex = VertexID(touchingTiles: Set(repeatTiles.map(\.coordinate)))
    let newVertex = VertexID(touchingTiles: Set(newTiles.map(\.coordinate)))

    let board = Board(
        tiles: repeatTiles + newTiles,
        ports: [],
        onBoardVertices: [repeatVertex, newVertex],
        onBoardEdges: [],
        robberTile: HexCoordinate(q: 100, r: 100)
    )

    let alreadyCovered: Set<Resource> = [.grain]
    let repeatScore = PlacementHeuristics.score(vertex: repeatVertex, board: board, alreadyCovered: alreadyCovered)
    let newScore = PlacementHeuristics.score(vertex: newVertex, board: board, alreadyCovered: alreadyCovered)
    #expect(newScore > repeatScore)

    // With no coverage passed (first placement), the two score identically -
    // the tie only breaks once we know what's already covered.
    #expect(PlacementHeuristics.score(vertex: repeatVertex, board: board) == PlacementHeuristics.score(vertex: newVertex, board: board))
}
