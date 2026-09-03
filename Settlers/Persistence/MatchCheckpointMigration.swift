import Foundation
import CatanEngine

/// Builds a checkpoint without modifying any legacy artifact. The caller's
/// first atomic commit creates the new authority; failed preparation cannot
/// delete or silently normalize the original save, roster, log, or totals.
@MainActor
enum MatchCheckpointMigration {
    enum MigrationError: Error, Equatable { case incompatibleRoster, historyMismatch }

    static func prepare(session: GameSession.Checkpoint, setup: MatchSetup,
                        statistics: GameStatsStore, activeLog: GameLogDetail?) throws -> MatchCheckpointDocument {
        try session.validate()
        guard setup.isStartable, setup.seats.count == session.state.players.count,
              setup.victoryPointTarget == session.state.victoryPointTarget else {
            throw MigrationError.incompatibleRoster
        }
        let baseline = try statistics.loadForMigration()
        var match = MatchCheckpoint(id: activeLog?.summary.gameID ?? UUID(),
                                    initialState: activeLog?.initialState ?? session.state, setup: setup)
        if let activeLog {
            guard activeLog.roster.humanSeats == Set(setup.humanSeats.map { PlayerID(index: $0.index) }) else {
                throw MigrationError.incompatibleRoster
            }
            for entry in activeLog.events { try match.apply(entry.move, by: entry.player) }
        }
        guard match.state == session.state else { throw MigrationError.historyMismatch }
        // Legacy active duration was memory-only. Archive wall-clock duration
        // includes time away from the app and must not be invented as play time.
        try match.attachSession(session)
        return try MatchCheckpointDocument(migratedMatch: match, legacyStatistics: baseline)
    }
}
