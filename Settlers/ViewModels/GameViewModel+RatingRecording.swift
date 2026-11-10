import CatanEngine
import Foundation

extension GameViewModel {
    /// Project the saved match contract into replay evidence. Ghost games
    /// retain their historic ladder; ordinary AI games carry an explicit
    /// mode/tier pool. Completion dates never change on a resumed result.
    func sharedRatedMatch(_ match: MatchCheckpoint, abandoned: Bool) -> SharedMatch? {
        let setup = match.setup
        guard setup.humanSeats.count == 1 else { return nil }
        let pool = RatingPool.eligible(for: setup)
        guard pool != nil || (setup.mode == .classic && setup.variant == .standard) else { return nil }
        let date = seatStatsStore.record(for: match.id)?.date
            ?? (abandoned ? match.abandonedAt ?? Date() : match.moves.last?.timestamp ?? match.startedAt)
        let owner = playerDirectory.resolvedID(match.playerID ?? playerDirectory.me)
        return SharedMatch(version: SharedMatch.currentVersion, match: match.id, date: date,
                           seats: setup.seats.map { Self.ratedEntity(for: $0, in: setup, me: owner).key },
                           initialState: match.initialState,
                           moves: match.moves.map {
                               SharedMatch.Move(player: $0.actor, move: $0.move, isHumanDecision: $0.isHumanDecision,
                                                rulesVersion: $0.rulesVersion)
                           }, abandoned: abandoned ? true : nil, ratingPool: pool)
    }

    /// Full replay evidence is written first. A stats/rating write interrupted
    /// afterwards can be retried from that outbox on the next launch. Stats
    /// are the authority; both rating presentations are derived from them.
    func persistRatingMatch(_ shared: SharedMatch) throws {
        let verified = try seatStatsStore.queueVerifiedMatch(shared, resolveOwner: playerDirectory.resolvedID,
                                                             verify: verifiedRatingRecord)
        try writeRatingRecord(verified)
        try ratingStore.rebuild(from: seatStatsStore.all())
    }

    private func verifiedRatingRecord(_ match: SharedMatch) throws -> SeatStatsRecord {
        guard match.personIDs.count == 1, let savedID = match.personIDs.first else {
            throw SharedMatch.Rejection.personIsNotUploader
        }
        return try match.verified(owner: playerDirectory.resolvedID(savedID))
    }

    private func writeRatingRecord(_ verified: SeatStatsRecord) throws {
        if var held = seatStatsStore.record(for: verified.match) {
            if held.ratingPool == nil { held.ratingPool = verified.ratingPool }
            if held.abandoned == nil { held.abandoned = verified.abandoned }
            try seatStatsStore.replace(held)
        } else {
            try seatStatsStore.record(verified)
        }
    }

    /// The old match remains in the checkpoint's pending export set until
    /// this succeeds. Thus a crash after switching tables cannot erase a
    /// restart loss, while a failed switch never rates a game still in play.
    func persistDisplacedRatingMatch(_ match: MatchCheckpoint) throws {
        let abandoned: Bool
        if case .gameOver = match.state.phase {
            guard !match.moves.isEmpty else { return } // Forced QA wins are not games.
            abandoned = false
        } else {
            guard match.abandonedAt != nil else { return } // QA replacements are not player restarts.
            abandoned = true
        }
        guard let shared = sharedRatedMatch(match, abandoned: abandoned) else { return }
        try persistRatingMatch(shared)
    }

    /// Repair interrupted local writes and enrich retained legacy records
    /// from their actual archive. An existing record proves the person's ID;
    /// typed archive names alone must not transfer another account's games.
    func recoverCompletedRatingRecords() throws -> Bool {
        var changed = false
        for file in try seatStatsStore.pendingUploadFiles() {
            do {
                let shared = try seatStatsStore.queuedMatch(at: file)
                if needsRatingRecord(for: shared) {
                    try writeRatingRecord(verifiedRatingRecord(shared))
                }
                changed = true // An interrupted rating write may follow valid stats.
            } catch where RatingMatchOutboxError.isRejectedEvidence(error) {
                // Retain the original evidence so a checkpoint can repair it.
                continue
            }
        }
        for var record in seatStatsStore.all() where record.ratingPool == nil {
            do {
                guard let pool = try archivedRatingPool(for: record) else { continue }
                record.ratingPool = pool
                try seatStatsStore.replace(record)
                changed = true
            } catch is GameLogStore.ReadError {
                continue
            }
        }
        return changed
    }

    private func needsRatingRecord(for match: SharedMatch) -> Bool {
        guard let record = seatStatsStore.record(for: match.match) else { return true }
        return (record.ratingPool == nil && match.ratingPool != nil)
            || (record.abandoned == nil && match.abandoned != nil)
    }

    private func archivedRatingPool(for record: SeatStatsRecord) throws -> RatingPool? {
        let entities = record.seats.compactMap { RatedEntity(key: $0.entity) }
        let tiers = entities.filter { $0 == .classic || $0 == .expert }
        guard tiers.count == entities.count - 1, let first = tiers.first,
              tiers.allSatisfy({ $0 == first }),
              let detail = try gameLogStore.detail(for: record.match), detail.summary.isComplete,
              detail.summary.humanSeats.count == 1 else { return nil }
        let tier: BotDifficulty = first == .expert ? .expert : .classic
        guard detail.roster.difficulty == nil || detail.roster.difficulty == tier else { return nil }
        return RatingPool(mode: detail.initialState.mode, variant: detail.initialState.variant, difficulty: tier)
    }
}
