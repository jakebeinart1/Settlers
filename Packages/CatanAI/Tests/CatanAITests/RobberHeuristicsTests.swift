import Testing
import CatanEngine
@testable import CatanAI

@Test func robberTargetsLeadingOpponentsTile() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let tile = state.board.tiles.first { $0.coordinate != state.board.robberTile }!.coordinate
    let leaderVertex = state.board.onBoardVertices.first { state.board.neighborTiles(of: $0).contains(tile) }!
    state.players[2].settlements.insert(leaderVertex)
    state.players[2].cities.insert(leaderVertex) // artificially boost VP to make player 2 the leader
    let (chosenTile, victim) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0))
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

    let (chosenTile, _) = RobberHeuristics.chooseRobberTarget(state: state, player: PlayerID(index: 0))
    #expect(chosenTile != ownTile)
}
