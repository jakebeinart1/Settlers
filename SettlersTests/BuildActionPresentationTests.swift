import Foundation
import Testing
@testable import CatanEngine
@testable import Settlers

/// These cover the distinctions a dim button alone cannot explain: actual
/// shortages, finite supplies, geography, turn ownership and variable prices.
struct BuildActionPresentationTests {
    private let actor = PlayerID(index: 0)

    @Test func screenshotHandReportsOnlyTheResourcesActuallyMissing() throws {
        var state = try NavalQAFixture.make(.voyage)
        replaceHand([.lumber: 1, .wool: 10], in: &state)
        let choices = BuildActionPresentation.menu(in: state, for: actor)
        let ship = try choice(.ship, from: choices)
        #expect(!ship.isEnabled)
        #expect(ship.status == "Unavailable")
        #expect(ship.detail == "Need 1 lumber · 2 ore")
        #expect(ship.costs.map(\.missing) == [1, 2, 0])
        #expect(ship.accessibilityValue.contains("Wool: have 10, cost 1, missing 0"))
        #expect(try choice(.road, from: choices).detail == "Need 1 brick")
        #expect(try choice(.city, from: choices).detail == "Need 3 ore · 2 grain")
        #expect(choices.allSatisfy { !$0.isEnabled })
    }

    @Test func payableShipIsReadyButUnreachableSettlementRemainsUnavailable() throws {
        let state = try NavalQAFixture.make(.voyage)
        let choices = BuildActionPresentation.menu(in: state, for: actor)
        let ship = try choice(.ship, from: choices)
        #expect(ship.isEnabled)
        #expect(ship.status == "Ready")
        #expect(ship.costs.allSatisfy { $0.missing == 0 })
        #expect(ship.detail.contains("Launch at your coast"))
        let settlement = try choice(.settlement, from: choices)
        #expect(!settlement.isEnabled)
        #expect(settlement.costs.allSatisfy { $0.missing == 0 })
        #expect(settlement.detail == "No legal corner reached by your roads or ships")
    }

    @Test func removingCoastalBuildingsDoesNotMasqueradeAsMissingResources() throws {
        var state = try NavalQAFixture.make(.voyage)
        state.players[0].settlements = []
        state.players[0].cities = []
        let ship = try choice(.ship, in: state)
        #expect(ship.costs.allSatisfy { $0.missing == 0 })
        #expect(!ship.isEnabled)
        #expect(ship.detail == "Requires your settlement or city on a charted coast")
    }

    @Test func hullSupplyUsesBuiltCountRatherThanOwnedFleetSize() throws {
        var state = try NavalQAFixture.make(.voyage)
        state.naval?.hullsBuilt[actor] = Naval.hullsPerBuilder
        #expect(state.naval?.ships.isEmpty == true)
        let ship = try choice(.ship, in: state)
        #expect(!ship.isEnabled)
        #expect(ship.detail == "All six hulls have been built")
    }

    @Test(arguments: [BuildActionPresentation.Kind.road, .settlement, .city])
    func exhaustedSupplyHasItsOwnReason(_ kind: BuildActionPresentation.Kind) throws {
        var state = try NavalQAFixture.make(.voyage)
        replaceHand([:], in: &state)
        switch kind {
        case .road: state.players[0].roads = Set(state.board.onBoardEdges.sorted().prefix(state.rules.maxRoadsPerPlayer))
        case .settlement:
            state.players[0].settlements = Set(state.board.onBoardVertices.sorted().prefix(state.rules.pieceLimit(for: .settlement)))
        case .city: state.players[0].cities = Set(state.board.onBoardVertices.sorted().prefix(state.rules.pieceLimit(for: .city)))
        default: Issue.record("Unexpected supply kind")
        }
        let presentation = try choice(kind, in: state)
        #expect(!presentation.isEnabled)
        #expect(presentation.detail.hasPrefix("No \(kind.rawValue) pieces left"))
        #expect(!presentation.detail.hasPrefix("Need"))
    }

    @Test func emptyDevelopmentDeckExplainsBlockEvenWithAffordableCost() throws {
        var state = try NavalQAFixture.make(.voyage)
        state.devCardDeck = []
        let card = try choice(.devCard, in: state)
        #expect(card.costs.allSatisfy { $0.missing == 0 })
        #expect(!card.isEnabled)
        #expect(card.detail == "Development deck is empty")
    }

    @Test func cityWithoutSettlementExplainsUpgradeRequirement() throws {
        var state = try NavalQAFixture.make(.voyage)
        replaceHand(Building.cityCost, in: &state)
        state.players[0].settlements = []
        let city = try choice(.city, in: state)
        #expect(!city.isEnabled)
        #expect(city.detail == "Build a settlement to upgrade first")
    }

    @Test(arguments: [0, 2])
    func otherActorsMovesNeverEnableDisplayedHumanButtons(_ humanIndex: Int) throws {
        var state = try NavalQAFixture.make(.voyage)
        let human = PlayerID(index: humanIndex)
        replaceHand([.brick: 10, .lumber: 10, .ore: 10, .grain: 10, .wool: 10], for: human, in: &state)
        state.phase = .mainTurn(playerIndex: humanIndex == 0 ? 2 : 0)
        let before = state
        let choices = BuildActionPresentation.menu(in: state, for: human)
        #expect(!RulesEngine.legalMoves(for: state).isEmpty)
        #expect(choices.allSatisfy { !$0.isEnabled && $0.detail == "Available on your turn" })
        #expect(state == before, "Opening Build must not spend, reveal, roll or mutate RNG")
    }

    @Test func rollAndMandatoryDecisionHaveDifferentInstructions() throws {
        var state = try NavalQAFixture.make(.voyage)
        state.phase = .rollDice(playerIndex: actor.index)
        #expect(try choice(.ship, in: state).detail == "Roll the dice before building")
        state.phase = .movingRobber(playerIndex: actor.index)
        #expect(try choice(.ship, in: state).detail == "Finish the current decision first")
        state.phase = .gameOver(winner: actor)
        #expect(try choice(.ship, in: state).detail == "The game has finished")
    }

    @Test(arguments: ArmyPrice.allCases)
    func conquestPriceUsesConfiguredPaymentRatherThanHardcodedThree(_ price: ArmyPrice) throws {
        var state = try conquestState()
        state.armyPrice = price
        replaceHand([.wool: 1], in: &state)
        let card = try choice(.armyCard, in: state)
        switch price {
        case .anyOne:
            #expect(card.isEnabled)
            #expect(card.flexibleCost == "Any 1 · have 1 card")
        case .anyThree:
            #expect(!card.isEnabled)
            #expect(card.flexibleCost == "Any 3 · have 1 card")
            #expect(card.detail == "Need 2 more resource cards")
        case .oneOfEach:
            #expect(!card.isEnabled)
            #expect(card.flexibleCost == nil)
            #expect(card.costs.count == 5)
            #expect(card.detail == "Need 1 brick · 1 lumber · 1 ore · 1 grain")
        }
    }

    @Test func conquestDeployAndDeckRespectTurnAndOwnResources() throws {
        var state = try conquestState()
        #expect(!Conquest.deployMoves(for: actor, in: state).isEmpty)
        state.phase = .rollDice(playerIndex: actor.index)
        #expect(!Conquest.deployMoves(for: actor, in: state).isEmpty)
        let waiting = try choice(.deployArmy, in: state)
        #expect(!waiting.isEnabled)
        #expect(waiting.detail == "Roll the dice before building")
        state.phase = .mainTurn(playerIndex: actor.index)
        state.armyHands[actor] = [6, 1, 3]
        state.armyDeck = []
        let army = try choice(.armyCard, in: state)
        #expect(army.detail == "Army deck is empty")
        #expect(army.inventoryDetail == "Yours: 1, 3, 6")
        state.armyHands[actor] = []
        #expect(try choice(.deployArmy, in: state).detail == "Buy an army card first")
    }

    @Test func geographyReasonUsesNoHiddenTerrainMetadata() throws {
        var state = try NavalQAFixture.make(.voyage)
        let original = BuildActionPresentation.menu(in: state, for: actor)
        let tiles = state.board.tiles.map { tile in
            Naval.isRevealed(tile.coordinate, in: state) ? tile : Tile(coordinate: tile.coordinate, kind: .resource(.ore), numberToken: 6)
        }
        state.board = Board(tiles: tiles, ports: state.board.ports, onBoardVertices: state.board.onBoardVertices,
                            onBoardEdges: state.board.onBoardEdges, robberTile: state.board.robberTile)
        #expect(BuildActionPresentation.menu(in: state, for: actor) == original)
    }

    private func choice(_ kind: BuildActionPresentation.Kind, in state: GameState) throws -> BuildActionPresentation {
        try choice(kind, from: BuildActionPresentation.menu(in: state, for: actor))
    }

    private func choice(_ kind: BuildActionPresentation.Kind,
                        from choices: [BuildActionPresentation]) throws -> BuildActionPresentation {
        try #require(choices.first { $0.kind == kind })
    }

    private func replaceHand(_ hand: [Resource: Int], for seat: PlayerID? = nil, in state: inout GameState) {
        let index = (seat ?? actor).index
        for resource in Resource.allCases {
            state.bank[resource, default: 0] += state.players[index].resources[resource, default: 0] - hand[resource, default: 0]
        }
        state.players[index].resources = hand
    }

    private func conquestState() throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 6_220, variant: .conquest)
        while state.phase.isSetup {
            let seat = PlayerID(index: state.phase.awaitingSeatIndex!)
            try RulesEngine.apply(RulesEngine.legalMoves(for: state, seat: seat).first!, by: seat, to: &state)
        }
        state.phase = .mainTurn(playerIndex: actor.index)
        return state
    }
}
