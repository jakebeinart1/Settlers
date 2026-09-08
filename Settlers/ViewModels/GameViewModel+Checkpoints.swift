import Foundation
import CatanEngine

/// A failed durable write is not an illegal move. Trade and bot callers must
/// retain their decision instead of withdrawing an offer or asserting.
struct MatchPersistenceFailure: LocalizedError {
    let underlying: Error
    var errorDescription: String? { "The game could not be saved: \(underlying.localizedDescription)" }
}

extension GameViewModel {
    /// Checkpoint existence wins over every legacy artifact, including an
    /// intentionally empty table. A failed read never means a fresh install.
    func loadCheckpointAuthority() {
        do {
            if let existing = try checkpointStore.load() {
                checkpointDocument = existing
            } else {
                let migrated = try prepareLegacyCheckpoint()
                try commitDocument(migrated)
            }
            try installCheckpointMatch()
            exportCommittedRecordings()
        } catch {
            checkpointDocument = try? checkpointStore.decodeForRecovery()
            savedGameAvailability = .blocked("Your saved game could not be opened. Original files have been preserved. \(error.localizedDescription)")
            saveWasUnreadable = true
            persistenceBlocked = true
        }
    }

    private func prepareLegacyCheckpoint() throws -> MatchCheckpointDocument {
        let loaded = gameStore.load()
        let active = matchSetupStore.loadActiveMatch()
        let seat = humanSeatStore.load()
        if let problem = Self.recoveryProblem(for: loaded, activeMatch: active, legacySeat: seat) {
            throw SavedGameRecoveryError.blocked(problem)
        }
        guard case .loaded(let state) = loaded else {
            let document = try MatchCheckpointMigration.prepare(statistics: gameStatsStore)
            if FileManager.default.fileExists(atPath: gameStatsStore.fileURL.path) {
                _ = try preserveRecoveryArtifacts(reason: "Original statistics before checkpoint migration")
            }
            return document
        }
        let setup = legacyRealizedSetup(state: state, active: active, seat: seat)
        let profiles = Self.profiles(in: setup)
        let candidate = Self.makeSession(state: state, opponentProfiles: profiles)
        let document = try MatchCheckpointMigration.prepare(
            session: candidate.checkpoint, setup: setup, statistics: gameStatsStore,
            activeLog: legacyActiveLog())
        // Export uses the legacy match UUID. Preserve the original recording
        // before any derived export can replace its path or retention evict it.
        _ = try preserveRecoveryArtifacts(reason: "Original files before checkpoint migration")
        return document
    }

    private func legacyActiveLog() throws -> GameLogDetail? {
        guard let id = try gameLogStore.activeGameID() else { return nil }
        guard let file = try gameLogStore.logFiles().first(where: { $0.deletingPathExtension().lastPathComponent == id.uuidString }) else {
            throw SavedGameRecoveryError.blocked("The saved recording is missing.")
        }
        return try gameLogStore.detail(for: file)
    }

    private func legacyRealizedSetup(state: GameState, active: MatchSetupStore.LoadResult,
                                     seat: PlayerID) -> MatchSetup {
        let roster = Self.restoredRoster(from: active, fallback: seat)
        let civilizations = Self.restoredCivilizations(for: state, humanSeat: seat,
            civilizationStore: civilizationStore, matchSetupStore: matchSetupStore)
        let profiles = Self.opponentProfiles(for: state, humanSeats: roster.seats,
            civilizations: civilizations, realizedSeats: active.value?.seats, preserveLegacySeatOrder: true)
        let chairs = state.players.map { player in
            MatchSetup.Seat(index: player.id.index, isHuman: roster.seats.contains(player.id),
                name: roster.names[player.id] ?? (roster.seats.contains(player.id) ? "You" : ""),
                civilization: civilizations[player.id.index], opponentProfile: profiles[player.id])
        }
        return MatchSetup(seats: chairs, victoryPointTarget: state.victoryPointTarget,
                          randomizedBoard: active.value?.randomizedBoard ?? false, randomizeSeatOrder: false)
    }

    /// Restore the saved policy cursor, never rebuild it from today's board.
    /// Realized roster validation precedes all seat indexing and presentation.
    func installCheckpointMatch() throws {
        guard let match = checkpointDocument?.activeMatch else {
            savedGameAvailability = .absent
            activeSince = nil
            boardDecisionCoordinator.clear()
            return
        }
        if let problem = Self.recoveryProblem(for: .loaded(match.state),
                                              activeMatch: .loaded(match.setup), legacySeat: PlayerID(index: 0)) {
            throw SavedGameRecoveryError.blocked(problem)
        }
        if let problem = match.setup.realizedIdentityProblem {
            throw SavedGameRecoveryError.blocked(
                "The saved player identity roster is incomplete. \(problem)"
            )
        }
        let playerRoster = PlayerRoster(realizedSetup: match.setup)
        let profiles = playerRoster.opponentProfiles
        guard profiles.count == match.setup.aiSeats.count, let savedSession = match.sessionCheckpoint else {
            throw SavedGameRecoveryError.blocked("The saved session or realized opponents are missing.")
        }
        let restored = try GameSession(checkpoint: savedSession, policies: Self.makePolicies(profiles))
        session = restored
        self.playerRoster = playerRoster
        pendingDevCardReveal = checkpointDocument?.pendingDevCardReveal
        pendingDevCardResolution = checkpointDocument?.pendingDevCardResolution
        seatAtDevice = humanSeats.count == 1 ? humanSeats.first : nil
        CivilizationAssignment.humanSeat = humanPlayer
        CivilizationAssignment.humanNames = playerRoster.humanNames
        CivilizationAssignment.current = match.setup.seats.compactMap(\.civilization)
        accumulatedActiveDuration = match.elapsedSeconds
        activeSince = { if case .gameOver = match.state.phase { return nil }; return Date() }()
        savedGameAvailability = .playable
        saveWasUnreadable = false
        persistenceBlocked = false
        restorePendingNegotiation()
        reconcileBoardDecision()
    }

    private static func profiles(in setup: MatchSetup) -> [PlayerID: OpponentProfile] {
        Dictionary(uniqueKeysWithValues: setup.aiSeats.compactMap { chair in
            chair.opponentProfile.map { (PlayerID(index: chair.index), $0) }
        })
    }

    /// One acknowledgement point for gameplay, accounting and export receipts.
    /// An error after replacement may mean success: only exact read-back of the
    /// candidate licenses publication; an unreadable result stops further bots.
    func commitDocument(_ candidate: MatchCheckpointDocument) throws {
        do {
            do {
                try checkpointStore.commit(candidate, replacingRevision: checkpointDocument?.revision)
            } catch {
                guard try checkpointStore.load() == candidate else { throw error }
            }
            checkpointDocument = candidate
            persistenceBlocked = false
            persistenceErrorMessage = nil
        } catch {
            throw reportPersistenceFailure(error)
        }
    }

    func reportPersistenceFailure(_ error: Error) -> MatchPersistenceFailure {
        persistenceBlocked = true
        let failure = MatchPersistenceFailure(underlying: error)
        persistenceErrorMessage = failure.localizedDescription
        return failure
    }

    /// Exports are retryable projections, never authority for a resumed game.
    /// A failed export or acknowledgement leaves the exact queued history live.
    func exportCommittedRecordings() {
        guard let document = checkpointDocument else { return }
        do {
            if let active = document.activeMatch, !active.moves.isEmpty {
                _ = try gameLogStore.export(checkpoint: active)
            }
            for id in document.pendingExports.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let match = checkpointDocument?.pendingExports[id], let current = checkpointDocument else { continue }
                _ = try gameLogStore.export(checkpoint: match)
                try commitDocument(current.acknowledgingExport(of: match))
            }
            if let current = checkpointDocument {
                var protectedIDs = Set(current.pendingExports.keys)
                if let active = current.activeMatch { protectedIDs.insert(active.id) }
                try gameLogStore.pruneExportedRecordings(protecting: protectedIDs)
            }
            if case .export = gameLogWarningState { gameLogWarningState = nil }
        } catch {
            gameLogWarningState = .export(
                "The recording is preserved and export will be retried: \(error.localizedDescription)"
            )
        }
    }
}
