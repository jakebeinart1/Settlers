import Foundation
import CatanEngine

/// Builds a checkpoint without modifying any legacy artifact. The caller's
/// first atomic commit creates the new authority; failed preparation cannot
/// delete or silently normalize the original save, roster, log, or totals.
@MainActor
enum MatchCheckpointMigration {
    enum MigrationError: LocalizedError, Equatable {
        case incompatibleRoster
        case historyMismatch
        /// A saved position without its replay source cannot honestly become
        /// a zero-move recording. The caller reports and preserves the legacy
        /// artifacts instead of inventing a new beginning for an old match.
        case historyUnavailable

        var errorDescription: String? {
            switch self {
            case .incompatibleRoster:
                return "The saved match and its player roster do not agree."
            case .historyMismatch:
                return "The saved match and its recorded move history do not agree."
            case .historyUnavailable:
                return "The saved match has no associated move history, so it cannot be migrated safely."
            }
        }
    }

    static func prepare(statistics: GameStatsStore) throws -> MatchCheckpointDocument {
        try MatchCheckpointDocument(legacyStatistics: statistics.loadForMigration())
    }

    static func prepare(session: GameSession.Checkpoint, setup: MatchSetup,
                        statistics: GameStatsStore, activeLog: GameLogDetail?) throws -> MatchCheckpointDocument {
        try session.validate()
        guard setup.isStartable, setup.seats.count == session.state.players.count,
              setup.victoryPointTarget == session.state.victoryPointTarget else {
            throw MigrationError.incompatibleRoster
        }
        let baseline = try statistics.loadForMigration()
        guard let activeLog else {
            guard isPristineInitialPosition(session.state) else { throw MigrationError.historyUnavailable }
            var match = MatchCheckpoint(id: UUID(), initialState: session.state, setup: setup)
            try match.attachSession(session)
            return try MatchCheckpointDocument(migratedMatch: match, legacyStatistics: baseline)
        }
        var match = MatchCheckpoint(id: activeLog.summary.gameID,
                                    initialState: activeLog.initialState, setup: setup,
                                    startedAt: activeLog.summary.startedAt)
        guard activeLog.roster.humanSeats == Set(setup.humanSeats.map { PlayerID(index: $0.index) }) else {
            throw MigrationError.incompatibleRoster
        }
        for entry in activeLog.events {
            try match.apply(entry.move, by: entry.player, timestamp: entry.timestamp)
        }
        guard match.state == session.state else { throw MigrationError.historyMismatch }
        // Legacy active duration was memory-only. Archive wall-clock duration
        // includes time away from the app and must not be invented as play time.
        try match.attachSession(session)
        return try MatchCheckpointDocument(migratedMatch: match, legacyStatistics: baseline)
    }

    /// A missing recording can truthfully mean zero moves only before the
    /// first setup placement. Any progressed position needs its replay source.
    private static func isPristineInitialPosition(_ state: GameState) -> Bool {
        guard state.phase == .setupForward(playerIndex: 0), state.lastDiceRoll == nil,
              state.pendingTradeOffers.isEmpty else { return false }
        return state.players.allSatisfy {
            $0.resources.values.allSatisfy { $0 == 0 }
                && $0.devCards.isEmpty && $0.settlements.isEmpty
                && $0.cities.isEmpty && $0.roads.isEmpty
                && $0.playedKnights == 0
        }
    }
}
