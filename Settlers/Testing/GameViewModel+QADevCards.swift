#if DEBUG
import Foundation
import CatanEngine

extension GameViewModel {
    /// A legal main-turn position whose next card is deterministic. The actual
    /// UI fixture buys it through Build; this helper never fakes the receipt.
    func qaPrepareDevCardPurchase(_ card: DevCardType) {
        let human = humanPlayer
        var fixture = devCardFixture(seed: 4_201)
        fixture.phase = .mainTurn(playerIndex: human.index)
        NavalQAFixture.replaceHand(Building.devCardCost, for: human, in: &fixture)
        // An older copy makes the reveal prove it describes the exact card
        // just drawn, not the aggregate playability of every card of its type.
        dealFixtureCards([card], to: human, in: &fixture)
        let drawIndex = fixture.devCardDeck.firstIndex(of: card)!
        fixture.devCardDeck.remove(at: drawIndex)
        fixture.devCardDeck.insert(card, at: 0)
        installDevCardFixture(fixture, human: human)
    }

    /// All card types at once, including an older/new Knight stack and a card
    /// that is new-only. This reaches every shelf badge without weakening any
    /// production legality rule.
    func qaPrepareMixedDevCardHand() {
        let human = humanPlayer
        var fixture = devCardFixture(seed: 4_202)
        // Pre-roll is intentional: every active card is legal here, and Road
        // Building once armed an untappable board because the view routed edge
        // taps only during `.mainTurn`.
        fixture.phase = .rollDice(playerIndex: human.index)
        dealFixtureCards([
            .knight, .knight, .roadBuilding, .roadBuilding,
            .yearOfPlenty, .monopoly, .victoryPoint,
        ], to: human, in: &fixture)
        fixture.devCardsBoughtThisTurn[human] = [.knight, .roadBuilding]
        if ProcessInfo.processInfo.arguments.contains("-qaDevCardBankScarce") {
            makeFixtureBankScarce(in: &fixture, human: human)
        }
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
            victoryPointTarget: Ruleset.forMode(.classic).defaultVictoryPointTarget
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
        replaceStateForTesting(fixture, humanSeat: human)
    }

    /// Naval card checks need an actual Naval world, completed legal setup,
    /// home buildings and conserved supply. A standard replacement silently
    /// turned every previous `-qaNavalMode` card launch into a Classic test.
    /// This is an explicit rare-state baseline, never a full-match shortcut.
    private func devCardFixture(seed: UInt64) -> GameState {
        var fixture: GameState
        if let naval = state.naval {
            fixture = Naval.newGame(seed: seed, playerCount: state.players.count, options: naval.options)
            while fixture.phase.isSetup {
                let actor = PlayerID(index: fixture.phase.awaitingSeatIndex!)
                let move = RulesEngine.legalMoves(for: fixture, seat: actor).first!
                do { try RulesEngine.apply(move, by: actor, to: &fixture) }
                catch { preconditionFailure("Naval card setup failed: \(error)") }
            }
        } else {
            fixture = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed,
                                        playerCount: state.players.count, victoryPointTarget: state.victoryPointTarget)
            fixture.players[humanPlayer.index].settlements.insert(fixture.board.onBoardVertices.sorted().first!)
        }
        fixture.victoryPointTarget = state.victoryPointTarget
        for player in fixture.players.map(\.id) {
            NavalQAFixture.replaceHand([:], for: player, in: &fixture)
        }
        return fixture
    }

    private func dealFixtureCards(_ cards: [DevCardType], to human: PlayerID, in fixture: inout GameState) {
        for card in cards {
            let index = fixture.devCardDeck.firstIndex(of: card)!
            fixture.devCardDeck.remove(at: index)
            fixture.players[human.index].devCards.append(card)
        }
    }

    /// The bank retains one Ore and one Grain. All other cards move to a
    /// rival, preserving supply while giving Plenty and Monopoly contrasting
    /// legality. Tests do not display or inspect the rival's private counts.
    private func makeFixtureBankScarce(in fixture: inout GameState, human: PlayerID) {
        let rival = fixture.players.first { $0.id != human }!.id
        for resource in Resource.allCases {
            let retained = resource == .ore || resource == .grain ? 1 : 0
            let amount = fixture.bank[resource, default: 0] - retained
            fixture.bank[resource] = retained
            fixture.players[rival.index].resources[resource, default: 0] += amount
        }
    }
}
#endif
