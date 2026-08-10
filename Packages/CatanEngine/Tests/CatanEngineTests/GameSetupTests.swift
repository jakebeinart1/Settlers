import Testing
@testable import CatanEngine

/// Regression tests for `GameSetup.newGame`'s dev card deck: it must be
/// shuffled (not handed out in the fixed knight/VP/roadBuilding/yearOfPlenty/
/// monopoly block order it's built in), while still containing exactly the
/// standard 25-card composition.
@Test func newGameShufflesDevCardDeckDifferentlyForDifferentSeeds() {
    var rngA = SeededGenerator(seed: 1)
    var rngB = SeededGenerator(seed: 2)
    let stateA = GameSetup.newGame(board: BoardGenerator.standard(), rng: &rngA)
    let stateB = GameSetup.newGame(board: BoardGenerator.standard(), rng: &rngB)

    #expect(stateA.devCardDeck != stateB.devCardDeck)
}

@Test func newGameDevCardDeckPreservesStandardComposition() {
    var rng = SeededGenerator(seed: 42)
    let state = GameSetup.newGame(board: BoardGenerator.standard(), rng: &rng)

    #expect(state.devCardDeck.count == 25)
    #expect(state.devCardDeck.filter { $0 == .knight }.count == 14)
    #expect(state.devCardDeck.filter { $0 == .victoryPoint }.count == 5)
    #expect(state.devCardDeck.filter { $0 == .roadBuilding }.count == 2)
    #expect(state.devCardDeck.filter { $0 == .yearOfPlenty }.count == 2)
    #expect(state.devCardDeck.filter { $0 == .monopoly }.count == 2)
}
