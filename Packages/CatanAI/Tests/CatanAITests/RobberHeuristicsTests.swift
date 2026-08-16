import Testing
import CatanEngine
@testable import CatanAI

@Test func robberTargetsLeadingOpponentsTile() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = state.board.tiles.first { $0.coordinate != state.board.robberTile }!.coordinate
    let leaderVertex = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(tile) }!
    state.players[2].settlements.insert(leaderVertex)
    state.players[2].cities.insert(leaderVertex) // artificially boost VP to make player 2 the leader
    let (chosenTile, victim) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0), personality: .balanced)
    #expect(chosenTile == tile)
    #expect(victim == PlayerID(index: 2))
}

@Test func robberAvoidsOwnTilesWhenAlternativeExists() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tiles = state.board.tiles.map(\.coordinate).filter { $0 != state.board.robberTile }
    let ownTile = tiles[0]
    let otherTile = tiles[1]

    let ownVertex = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(ownTile) }!
    let opponentVertex = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(otherTile) }!

    state.players[0].settlements.insert(ownVertex)
    state.players[1].settlements.insert(opponentVertex)

    let (chosenTile, _) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0), personality: .balanced)
    #expect(chosenTile != ownTile)
}

@Test func robberDisruptionScalesWithRelativeThreatNotJustRawVictoryPoints() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let candidateTiles = state.board.tiles.map(\.coordinate).filter { $0 != state.board.robberTile }

    // Pick two tiles whose chosen vertices share *no* touching tile at all
    // (not just each other): a vertex can touch up to 3 tiles, so two
    // "unrelated" tiles could otherwise both border some third tile, and if
    // that third tile ends up touching both injected settlements its
    // combined disruption could beat either tile alone. `.sorted().first`
    // (rather than the Set's unordered `.first`) also keeps the specific
    // vertex chosen - and therefore its production value - identical across
    // process runs, since `onBoardVertices`' Set iteration order isn't
    // stable across runs.
    func vertex(touching tile: HexCoordinate) -> VertexID {
        state.board.onBoardVertices.filter { state.board.neighborTiles(of: $0).contains(tile) }.sorted().first!
    }
    var tileA = candidateTiles[0]
    var tileB = candidateTiles[1]
    var vertexA = vertex(touching: tileA)
    var vertexB = vertex(touching: tileB)
    outer: for a in candidateTiles {
        for b in candidateTiles where b != a {
            let va = vertex(touching: a)
            let vb = vertex(touching: b)
            let tilesOfA = Set(state.board.neighborTiles(of: va))
            let tilesOfB = Set(state.board.neighborTiles(of: vb))
            if tilesOfA.isDisjoint(with: tilesOfB) {
                tileA = a; tileB = b; vertexA = va; vertexB = vb
                break outer
            }
        }
    }

    // Player 1 sits on tileA with a single settlement; player 2 sits on
    // tileB with an equal settlement but a huge dev card stash - equal
    // building count/VP, wildly different threat. The dev card gap (75
    // points) is chosen to swamp any possible production-value difference
    // between vertexA/vertexB (bounded well under that), so the outcome
    // doesn't depend on which vertex a given board layout happens to touch.
    state.players[1].settlements.insert(vertexA)
    state.players[2].settlements.insert(vertexB)
    state.players[2].devCards = Array(repeating: DevCardType.knight, count: 50)

    let (chosenTile, _) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0), personality: .aggressive)
    #expect(chosenTile == tileB)
}
