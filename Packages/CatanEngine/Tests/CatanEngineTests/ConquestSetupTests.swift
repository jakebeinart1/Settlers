import Testing
@testable import CatanEngine

@Test func aConquestGameStartsWithEveryProducingHexHeldByATribeAtItsPipCount() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, variant: .conquest)
    for tile in state.board.tiles {
        guard let token = tile.numberToken else {
            #expect(state.garrisons[tile.coordinate] == nil, "the desert is never garrisoned")
            continue
        }
        #expect(state.garrisons[tile.coordinate] == Garrison(owner: nil, strength: DiceOdds.pips(for: token)))
    }
}

@Test func aConquestGameShufflesTheFullClassicArmyDeck() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, variant: .conquest)
    #expect(state.armyDeck.count == 29)
    #expect(state.armyDeck.sorted() == Conquest.buildArmyDeck(Ruleset.classicArmyDeck))
    #expect(state.armyDeck != Conquest.buildArmyDeck(Ruleset.classicArmyDeck), "the deck is shuffled")
}

@Test func vastDoublesTheArmyDeck() {
    #expect(Ruleset.forMode(.vast).armyDeck.values.reduce(0, +) == 58)
    #expect(Ruleset.forMode(.vast).armyDeck[9] == 2)
}

@Test func aStandardGameHasNoConquestStateAndDrawsTheSameRandomSequence() {
    let before = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42)
    let explicit = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42, variant: .standard)
    #expect(before == explicit)
    #expect(before.garrisons.isEmpty && before.armyDeck.isEmpty && before.armyHands.isEmpty)
}

@Test func conquestDoesNotChangeTheDevDeckOrDiceSeedOfTheSameSeed() {
    let standard = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42)
    let conquest = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42, variant: .conquest)
    #expect(standard.devCardDeck == conquest.devCardDeck)
    #expect(standard.rng == conquest.rng)
}

@Test func armyCardsCostAnyThreeResourcesByDefault() {
    let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3, variant: .conquest)
    #expect(state.armyPrice == .anyThree)
}
