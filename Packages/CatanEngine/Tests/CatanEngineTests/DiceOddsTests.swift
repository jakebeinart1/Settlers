import Testing
@testable import CatanEngine

/// Pins the dice distribution, which two separate consumers read.
///
/// Worth a test despite being three lines of code: placement scoring and the
/// greedy anchor policy both rank tiles by it, so an error here would quietly
/// change how every bot values every hex rather than failing loudly anywhere.
@Test func pipsMatchTheWaysTwoDiceRollEachNumber() {
    let expected = [2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 8: 5, 9: 4, 10: 3, 11: 2, 12: 1]
    for (token, pips) in expected.sorted(by: { $0.key < $1.key }) {
        #expect(DiceOdds.pips(for: token) == pips, "token \(token)")
    }
    // The 36 outcomes are the ten board numbers plus the six ways to roll 7.
    #expect(expected.values.reduce(0, +) + 6 == 36)
}

@Test func numbersThatAreNotOnTheBoardProduceNothing() {
    // Seven is the robber, never a token; the rest are nonsense input. Both
    // must score zero rather than a plausible-looking number, because these
    // feed a max() over tiles and a wrong nonzero would win it.
    #expect(DiceOdds.pips(for: 7) == 0)
    for token in [-1, 0, 1, 13, 100] { #expect(DiceOdds.pips(for: token) == 0, "token \(token)") }
}
