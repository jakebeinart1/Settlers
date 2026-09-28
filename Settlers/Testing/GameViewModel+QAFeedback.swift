#if DEBUG
import CatanEngine

extension GameViewModel {
    /// The human and a rival have five roads each; the rival retains the tie.
    /// Confirming the staged sixth road transfers the actual engine bonus.
    /// Uses a complete Classic board and no fabricated feedback/event values.
    func qaPrepareLongestRoadPosition() {
        let human = humanPlayer
        var fixture = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310)
        let rival = fixture.players.first { $0.id != human }!.id
        let humanEdges = Self.qaHexEdges(HexCoordinate(q: -2, r: 0), board: fixture.board)
        let rivalEdges = Self.qaHexEdges(HexCoordinate(q: 2, r: 0), board: fixture.board)
        fixture.players[human.index].roads = Set(humanEdges.prefix(5))
        fixture.players[rival.index].roads = Set(rivalEdges.prefix(5))
        fixture.players[human.index].resources = [.brick: 1, .lumber: 1]
        fixture.bank[.brick, default: 0] -= 1
        fixture.bank[.lumber, default: 0] -= 1
        fixture.longestRoadPlayer = rival
        fixture.phase = .mainTurn(playerIndex: human.index)
        precondition(LongestRoad.compute(for: fixture) == rival)
        replaceStateForTesting(fixture, humanSeat: human)
        precondition(beginBoardDecision(.buildRoad))
        precondition(selectBoardTarget(.edge(humanEdges[5])))
    }

    private static func qaHexEdges(_ hex: HexCoordinate, board: Board) -> [EdgeID] {
        let corners = board.corners(of: hex)
        return corners.indices.map { EdgeID(corners[$0], corners[($0 + 1) % corners.count]) }
    }
}
#endif
