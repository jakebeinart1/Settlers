/// How likely each number token is to be rolled.
///
/// This lives in the engine, not in a bot, because it is a fact about two
/// six-sided dice rather than an opinion about how to play. Two separate
/// consumers - placement scoring and the greedy anchor policy - had otherwise
/// each grown their own copy of the same table, which is a fact stated twice
/// and therefore a fact that can disagree with itself.
///
/// "Pips" is the Catan term: the dots printed under a number token, equal to
/// the number of the 36 dice combinations that produce it. Six is 5 pips
/// because there are five ways to roll it (1+5, 2+4, 3+3, 4+2, 5+1); seven is
/// excluded from the board entirely, being the robber.
public enum DiceOdds {

    /// Combinations of two dice that produce `token`, out of 36.
    ///
    /// Computed from the distance to seven rather than looked up from a table:
    /// the distribution is a triangle peaking at seven, so the count is
    /// `6 - |token - 7|`. Writing it as the formula makes the shape obvious and
    /// removes eleven magic numbers.
    ///
    /// - Returns: 0 for anything off the board (seven, or a nonsense token),
    ///   which is correct - those tiles never produce.
    public static func pips(for token: Int) -> Int {
        guard (2...12).contains(token), token != 7 else { return 0 }
        return 6 - abs(token - 7)
    }
}
