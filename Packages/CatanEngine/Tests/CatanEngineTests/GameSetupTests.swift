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

/// `DevCardType.deckBuildOrder` (not `allCases`' own declaration order) is
/// what the deck is stacked in before it is shuffled - pinned to the
/// historical knight/VP/roadBuilding/yearOfPlenty/monopoly order because
/// `SeededGameFingerprintTests` depends on that exact pre-shuffle stacking
/// producing the same seeded permutation it always has. If a rank ever
/// collides or drifts, this fails before a fingerprint has to.
@Test func deckBuildOrderRanksArePreservedAndDistinct() {
    let stacked = DevCardType.allCases.sorted { $0.deckBuildOrder < $1.deckBuildOrder }
    #expect(stacked == [.knight, .victoryPoint, .roadBuilding, .yearOfPlenty, .monopoly])

    let ranks = Set(DevCardType.allCases.map(\.deckBuildOrder))
    #expect(ranks.count == DevCardType.allCases.count, "every case must have a distinct rank")
}
