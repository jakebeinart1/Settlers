#if DEBUG
import CatanEngine

extension GameViewModel {
    /// A conserved hand before a real roll. Only setup is seeded; the test must
    /// tap Roll Dice through the same commit/payout/receipt path as a player.
    func qaPrepareProductionPosition() {
        let board = BoardGenerator.standard()
        let ore = HexCoordinate(q: 0, r: 0)
        let grain = HexCoordinate(q: 2, r: -2)
        let tiles = board.tiles.map { tile in
            if tile.coordinate == ore { return Tile(coordinate: ore, kind: .resource(.ore), numberToken: 6) }
            if tile.coordinate == grain { return Tile(coordinate: grain, kind: .resource(.grain), numberToken: 6) }
            return Tile(coordinate: tile.coordinate, kind: tile.kind, numberToken: tile.numberToken == 6 ? 5 : tile.numberToken)
        }
        let fixtureBoard = Board(tiles: tiles, ports: board.ports, onBoardVertices: board.onBoardVertices,
                                 onBoardEdges: board.onBoardEdges, robberTile: board.robberTile)
        var fixture = GameSetup.newGame(board: fixtureBoard, seed: 4_309)
        let player = humanPlayer
        fixture.players[player.index].cities = [board.corners(of: ore)[0]]
        fixture.players[player.index].settlements = [board.corners(of: grain)[0]]
        fixture.phase = .rollDice(playerIndex: player.index)
        let seed = (UInt64(0)..<100).first { seed in
            var rng = RandomSource(seed: seed)
            return Int.random(in: 1...6, using: &rng) + Int.random(in: 1...6, using: &rng) == 6
        }!
        fixture.rng = RandomSource(seed: seed)
        precondition(MainPhase.payouts(for: 6, in: fixture)[player.index] == [.ore: 2, .grain: 1])
        replaceStateForTesting(fixture, humanSeat: player)
    }
}
#endif
