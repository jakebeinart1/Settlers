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
    let tiles = state.board.tiles.map(\.coordinate).filter { $0 != state.board.robberTile }
    let tileA = tiles[0]
    let tileB = tiles[1]

    let vertexA = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(tileA) }!
    let vertexB = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(tileB) }!

    // Player 1 sits on tileA with a single settlement; player 2 sits on
    // tileB but is far more developed overall (more dev cards, more
    // production) despite an equal VP count - relative threat should send
    // the robber to tileB, not just wherever VP happens to be highest.
    state.players[1].settlements.insert(vertexA)
    state.players[2].settlements.insert(vertexB)
    state.players[2].devCards = [.knight, .knight, .knight, .knight]

    let (chosenTile, _) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0), personality: .aggressive)
    #expect(chosenTile == tileB)
}
