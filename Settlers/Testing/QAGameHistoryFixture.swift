import Foundation
import CatanEngine

#if DEBUG
/// Writes one deterministic finished recording into the archive so the history
/// list and the replay screen have something real to open.
///
/// ## Why a fixture at all
/// A recording only exists after a match has been played, and a played match
/// takes a bot loop, pacing delays and a minute or two of wall clock. A UI test
/// for "can I open a replay and scrub it" should not be a test of how fast the
/// bots are. Everything here goes through the production writer
/// (`GameLogStore.startNewGame`/`appendMove`/`finalizeGame`) and the production
/// rules, so what lands on disk is the same shape a real game leaves behind -
/// the moves are chosen by a fixed rule rather than played by anybody.
///
/// ## Why "first legal move"
/// `RulesEngine.legalMoves` is order-stable by contract (see the determinism
/// invariants in CLAUDE.md), so taking its first element every time gives the
/// same game on every launch without needing a policy, a seed table, or any
/// part of `CatanAI`. It plays badly. That is fine: the screen under test
/// renders a board and a score, not good play.
enum QAGameHistoryFixture {
    /// Enough moves to fill the opening placements and a few rounds beyond
    /// them, so the scrubber has real distance to travel and the score strip
    /// has something to count.
    private static let moveBudget = 90

    static func seedIfRequested(store: GameLogStore = .shared) {
        guard QALaunchFlag.seedGameHistory.isSet else { return }
        do {
            try seed(store: store)
        } catch {
            preconditionFailure("Could not seed the QA game history: \(error)")
        }
    }

    private static func seed(store: GameLogStore) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard())
        let roster = GameLogStore.SeatRoster(
            humanSeats: [PlayerID(index: 0)],
            humanNames: [0: "UI Tester"],
            botProfileNames: [1: "Rome", 2: "Japan", 3: "Aztec"],
            botPersonalities: [1: "balanced", 2: "balanced", 3: "balanced"],
            civilizations: Dictionary(uniqueKeysWithValues: state.players.indices.map {
                ($0, Civilization.allCases[$0 % Civilization.allCases.count].displayName)
            }))
        let gameID = try store.startNewGame(initialState: state, roster: roster)

        for _ in 0..<moveBudget {
            guard let seat = actingSeat(in: state),
                  let move = RulesEngine.legalMoves(for: state, seat: seat).first else { break }
            try RulesEngine.apply(move, by: seat, to: &state)
            try store.appendMove(gameID: gameID, player: seat, move: move)
            if case .gameOver = state.phase { break }
        }
        try store.finalizeGame(gameID: gameID, winner: leader(in: state))
    }

    /// `.discarding` is the one phase waiting on several seats at once, so it
    /// cannot be answered by `awaitingSeatIndex` alone; the lowest pending seat
    /// keeps the choice deterministic.
    private static func actingSeat(in state: GameState) -> PlayerID? {
        switch state.phase {
        case .gameOver: return nil
        case .discarding(let pending): return pending.min { $0.index < $1.index }
        default: return state.phase.awaitingSeatIndex.map { PlayerID(index: $0) }
        }
    }

    private static func leader(in state: GameState) -> PlayerID {
        if case .gameOver(let winner) = state.phase { return winner }
        return state.players
            .max { state.victoryPoints(for: $0.id) < state.victoryPoints(for: $1.id) }?
            .id ?? PlayerID(index: 0)
    }
}
#endif
