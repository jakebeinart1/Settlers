#if DEBUG
import CatanEngine

extension GameViewModel {
    /// Main-turn position that can afford and legally stage every paid piece.
    func qaPreparePaidBuildPosition(starting intent: BoardDecisionIntent? = nil) {
        let human = humanPlayer
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 4_301,
            playerCount: state.players.count, victoryPointTarget: state.victoryPointTarget
        )
        let start = fixture.board.onBoardVertices.sorted().first!
        let first = fixture.board.edgesTouching(start).sorted().first!
        let endpoints = fixture.board.vertices(of: first)
        let middle = endpoints.0 == start ? endpoints.1 : endpoints.0
        let second = fixture.board.edgesTouching(middle).sorted().first { $0 != first }!
        fixture.players[human.index].settlements.insert(start)
        fixture.players[human.index].roads.formUnion([first, second])
        fixture.players[human.index].resources = Dictionary(
            uniqueKeysWithValues: Resource.allCases.map { ($0, 5) }
        )
        for resource in Resource.allCases { fixture.bank[resource, default: 0] -= 5 }
        fixture.phase = .mainTurn(playerIndex: human.index)
        replaceStateForTesting(fixture, humanSeat: human)
        if let intent {
            precondition(beginBoardDecision(intent), "QA paid build decision did not start")
        }
    }

    /// Real Road Building card in a legal pre-roll position.
    func qaPrepareRoadBuildingDecision() {
        let human = humanPlayer
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 4_302,
            playerCount: state.players.count, victoryPointTarget: state.victoryPointTarget
        )
        fixture.phase = .rollDice(playerIndex: human.index)
        fixture.players[human.index].devCards = [.roadBuilding]
        fixture.players[human.index].settlements.insert(fixture.board.onBoardVertices.sorted().first!)
        replaceStateForTesting(fixture, humanSeat: human)
        precondition(beginBoardDecision(.roadBuilding), "QA Road Building decision did not start")
    }

    /// Mandatory seven-driven robber decision with all three rival identities
    /// available on one destination. It exercises the maximum-width picker.
    func qaPrepareMandatoryRobberDecision(selectDestination: Bool = false) {
        let human = qaFixtureHuman
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 4_303,
            playerCount: qaFixturePlayerCount, victoryPointTarget: state.victoryPointTarget
        )
        let destination = fixture.board.tiles.first {
            $0.coordinate != fixture.board.robberTile
        }!.coordinate
        let vertices = fixture.board.onBoardVertices.sorted().filter {
            fixture.board.neighborTiles(of: $0).contains(destination)
        }
        let rivals = fixture.players.map(\.id).filter { $0 != human }
        for (player, vertex) in zip(rivals, vertices) {
            fixture.players[player.index].settlements.insert(vertex)
            fixture.players[player.index].resources = [.ore: 1]
            fixture.bank[.ore, default: 0] -= 1
        }
        fixture.phase = .movingRobber(playerIndex: human.index)
        fixture.robberMoverIndex = human.index
        replaceStateForTesting(fixture, humanSeat: human)
        if selectDestination {
            precondition(
                selectBoardTarget(.tile(destination)),
                "QA mandatory robber destination was rejected"
            )
        }
    }

    /// Installs a real playable Knight and starts the production board-decision
    /// path. The optional second stage chooses a destination that has a victim,
    /// so screenshots and UI tests never fake coordinator state.
    func qaPrepareKnightBoardDecision(selectDestinationWithVictim: Bool) {
        let human = qaFixtureHuman
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(), seed: 4_304,
            playerCount: qaFixturePlayerCount, victoryPointTarget: state.victoryPointTarget
        )
        let destination = fixture.board.tiles.first {
            $0.coordinate != fixture.board.robberTile
        }!.coordinate
        let vertices = fixture.board.onBoardVertices.sorted().filter {
            fixture.board.neighborTiles(of: $0).contains(destination)
        }
        let rivals = fixture.players.map(\.id).filter { $0 != human }
        for (player, vertex) in zip(rivals, vertices) {
            fixture.players[player.index].settlements.insert(vertex)
            fixture.players[player.index].resources = [.ore: 1]
            fixture.bank[.ore, default: 0] -= 1
        }
        fixture.phase = .rollDice(playerIndex: human.index)
        fixture.players[human.index].devCards = [.knight]
        replaceStateForTesting(fixture, humanSeat: human)

        precondition(beginBoardDecision(.knight), "QA Knight decision did not start")
        guard selectDestinationWithVictim else { return }
        let move = RulesEngine.legalMoves(for: state, seat: human).first {
            if case .playKnight(_, let victim?) = $0 { return victim != human }
            return false
        }
        guard case .playKnight(let tile, _)? = move else {
            preconditionFailure("QA Knight fixture has no destination with a victim")
        }
        precondition(selectBoardTarget(.tile(tile)), "QA robber destination was rejected")
    }

    private var qaFixturePlayerCount: Int {
        QALaunchFlag.threePlayerTable.isSet ? 3 : state.players.count
    }

    private var qaFixtureHuman: PlayerID {
        QALaunchFlag.humanSeatTwo.isSet ? PlayerID(index: 1) : humanPlayer
    }
}
#endif
