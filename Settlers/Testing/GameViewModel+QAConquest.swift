#if DEBUG
import CatanEngine

extension GameViewModel {
    /// Main-turn Conquest position on the standard board: the human settled on a
    /// 6 and a 9, holding the 9 at 6; seat 1 settled on the same 6 and holding a
    /// 5 elsewhere at 4; the human has army cards [2, 5] (the 5 bought this turn)
    /// and 5 of each resource.
    func qaPrepareConquestPosition() {
        let human = humanPlayer
        let rival = PlayerID(index: (human.index + 1) % state.players.count)
        var fixture = GameSetup.newGame(board: BoardGenerator.standard(), seed: 4_310,
                                        playerCount: state.players.count, variant: .conquest)
        let tiles = fixture.board.tiles.sorted { $0.coordinate < $1.coordinate }
        let six = tiles.first { $0.numberToken == 6 }!
        let nine = tiles.first { $0.numberToken == 9 }!
        let five = tiles.first { $0.numberToken == 5 }!
        fixture.players[human.index].settlements.formUnion([
            fixture.board.corners(of: six.coordinate)[0], fixture.board.corners(of: nine.coordinate)[0],
        ])
        fixture.players[rival.index].settlements.formUnion([
            fixture.board.corners(of: six.coordinate)[3], fixture.board.corners(of: five.coordinate)[3],
        ])
        fixture.garrisons[nine.coordinate] = Garrison(owner: human, strength: 6)
        fixture.garrisons[five.coordinate] = Garrison(owner: rival, strength: 4)
        fixture.armyHands[human] = [2, 5]
        fixture.armyCardsBoughtThisTurn[human] = [5]
        fixture.armyHands[rival] = [3, 7]
        fixture.players[human.index].resources = Dictionary(uniqueKeysWithValues: Resource.allCases.map { ($0, 5) })
        for resource in Resource.allCases { fixture.bank[resource, default: 0] -= 5 }
        fixture.phase = .mainTurn(playerIndex: human.index)
        replaceStateForTesting(fixture, humanSeat: human)
    }
}
#endif
