import CatanAI
import CatanEngine

/// Building the policies that play a table.
///
/// Its own file because `GameViewModel.swift` sits against SwiftLint's
/// 1,250-line limit, and this is the one self-contained concern in it that
/// already has a clear boundary: given a table and a difficulty, which brains
/// sit in the chairs. `+Checkpoints` set the precedent for splitting the type
/// this way.
extension GameViewModel {

    /// Only new matches and legacy migration seed a session from the board.
    /// Modern resume restores the saved policy RNG and negotiation bookkeeping.
    static func makeSession(
        state: GameState,
        opponentProfiles: [PlayerID: OpponentProfile],
        difficulty: BotDifficulty
    ) -> GameSession {
        var seedSource = state.rng
        return GameSession(
            state: state,
            policies: makePolicies(opponentProfiles, difficulty: difficulty),
            policySeed: seedSource.next()
        )
    }

    /// The policies for one table.
    ///
    /// `difficulty` has no default on purpose. A caller that forgot it would
    /// silently seat the tier nobody chose, and "the arm was silently played by
    /// the default opponent" is the exact shape of every bogus strength claim
    /// this project has had to retract.
    static func makePolicies(
        _ profiles: [PlayerID: OpponentProfile],
        difficulty: BotDifficulty
    ) -> [PlayerID: any Policy] {
        profiles.mapValues { difficulty.policy(for: $0) }
    }
}
