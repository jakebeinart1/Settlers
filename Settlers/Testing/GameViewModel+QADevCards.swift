#if DEBUG
import CatanEngine

extension GameViewModel {
    /// A legal main-turn position whose next card is deterministic. The actual
    /// UI fixture buys it through Build; this helper never fakes the receipt.
    func qaPrepareDevCardPurchase(_ card: DevCardType) {
        let human = humanPlayer
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(),
            seed: 4_201,
            playerCount: state.players.count,
            victoryPointTarget: state.victoryPointTarget
        )
        fixture.phase = .mainTurn(playerIndex: human.index)
        fixture.players[human.index].resources = [.ore: 1, .grain: 1, .wool: 1]
        // An older copy makes the reveal prove it describes the exact card
        // just drawn, not the aggregate playability of every card of its type.
        fixture.players[human.index].devCards = [card]
        fixture.devCardDeck = [card]
        if card == .roadBuilding {
            fixture.players[human.index].settlements.insert(
                fixture.board.onBoardVertices.sorted().first!
            )
        }
        installDevCardFixture(fixture, human: human)
    }

    /// All card types at once, including an older/new Knight stack and a card
    /// that is new-only. This reaches every shelf badge without weakening any
    /// production legality rule.
    func qaPrepareMixedDevCardHand() {
        let human = humanPlayer
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(),
            seed: 4_202,
            playerCount: state.players.count,
            victoryPointTarget: state.victoryPointTarget
        )
        // Pre-roll is intentional: every active card is legal here, and Road
        // Building once armed an untappable board because the view routed edge
        // taps only during `.mainTurn`.
        fixture.phase = .rollDice(playerIndex: human.index)
        fixture.players[human.index].devCards = [
            .knight, .knight, .roadBuilding, .roadBuilding,
            .yearOfPlenty, .monopoly, .victoryPoint,
        ]
        fixture.devCardsBoughtThisTurn[human] = [.knight, .roadBuilding]
        fixture.players[human.index].settlements.insert(fixture.board.onBoardVertices.sorted().first!)
        installDevCardFixture(fixture, human: human)
    }

    /// A legal nine-point position whose next card is the winning tenth point.
    /// The UI still buys the card through `apply`, so this fixture exercises
    /// the same durable private receipt as a naturally reached win.
    func qaPrepareWinningDevCardPurchase() {
        let human = humanPlayer
        var fixture = GameSetup.newGame(
            board: BoardGenerator.standard(),
            seed: 4_203,
            playerCount: state.players.count,
            victoryPointTarget: WinCondition.standardTarget
        )
        let vertices = fixture.board.onBoardVertices.sorted()
        fixture.phase = .mainTurn(playerIndex: human.index)
        fixture.players[human.index].cities = Set(vertices.prefix(3))
        fixture.players[human.index].settlements = Set(vertices.dropFirst(20).prefix(3))
        fixture.players[human.index].resources = [.ore: 1, .grain: 1, .wool: 1]
        fixture.devCardDeck = [.victoryPoint]
        installDevCardFixture(fixture, human: human)
    }

    private func installDevCardFixture(_ fixture: GameState, human: PlayerID) {
        if QALaunchFlag.twoHumans.isSet, fixture.players.count > 1 {
            replaceStateForTesting(
                fixture,
                humanSeats: [human, PlayerID(index: human.index == 0 ? 1 : 0)]
            )
        } else {
            replaceStateForTesting(fixture, humanSeat: human)
        }
    }
}
#endif
