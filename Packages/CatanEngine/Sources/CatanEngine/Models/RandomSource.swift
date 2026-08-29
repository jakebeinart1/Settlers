/// A seedable, serializable random number generator that lives *inside*
/// `GameState`, so every random outcome the rules produce is reproducible.
///
/// ## What this solves
/// Dice rolls and robber steals used to call the global RNG
/// (`Int.random`, `Array.randomElement`) from inside `RulesEngine.apply`.
/// That made the engine irreproducible in three ways that all mattered:
///
/// 1. **Game logs could not be replayed.** `GameLogStore` records the initial
///    state plus the ordered move list and calls that a trajectory, but
///    `GameMove.rollDice` carries no payload — replaying re-rolled different
///    dice and diverged within a few moves.
/// 2. **Bot changes could not be measured.** Two runs of the same board seed
///    produced different games, so any A/B comparison of a heuristic change
///    was measuring noise.
/// 3. **Failing simulations could not be bisected**, because they did not
///    reproduce.
///
/// ## Why the generator is stored in state rather than passed in
/// The alternative — threading an `inout RandomNumberGenerator` through
/// `RulesEngine.apply` — would change every call site in the app, the tests
/// and the AI package, and would still leave save/resume non-deterministic
/// because the generator's position would not survive being written to disk.
/// Keeping it in `GameState` means `apply` keeps its signature, a resumed
/// save continues the same random sequence it would have had, and a recorded
/// move list replays exactly with no per-move payload.
///
/// ## The algorithm
/// SplitMix64: the seed is advanced by the 64-bit golden-ratio constant and
/// the result is passed through two xor-shift/multiply finalizing rounds.
/// Chosen because it is a handful of lines with no lookup tables, has a
/// guaranteed 2^64 period (every seed is as good as any other, so callers can
/// pass a game index straight in), and — unlike `SystemRandomNumberGenerator`
/// — is specified rather than platform-defined, so a seed reproduces the same
/// sequence across machines and OS versions.
public struct RandomSource: RandomNumberGenerator, Codable, Sendable, Hashable {
    /// The generator's position in its sequence. Serialized with the game, so
    /// a save resumes mid-sequence rather than restarting it.
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
