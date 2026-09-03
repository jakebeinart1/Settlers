import Foundation
import CatanEngine

/// One match's state and its replay source travel in the same atomic write.
/// App identity stays outside GameState because it is not a game rule.
struct MatchCheckpoint: Codable, Equatable, Sendable {
    struct RecordedMove: Codable, Equatable, Sendable {
        let actor: PlayerID
        let move: GameMove
        let timestamp: Date
    }

    let id: UUID
    let startedAt: Date
    let initialState: GameState
    let setup: MatchSetup
    private(set) var state: GameState
    private(set) var moves: [RecordedMove] = []
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var sessionCheckpoint: GameSession.Checkpoint?

    init(id: UUID, initialState: GameState, setup: MatchSetup, startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.initialState = initialState
        self.state = initialState
        self.setup = setup
    }

    mutating func apply(_ move: GameMove, by actor: PlayerID, timestamp: Date = Date()) throws {
        var candidate = state
        try RulesEngine.apply(move, by: actor, to: &candidate)
        state = candidate
        moves.append(RecordedMove(actor: actor, move: move, timestamp: timestamp))
        sessionCheckpoint = nil
    }

    mutating func attachSession(_ checkpoint: GameSession.Checkpoint) throws {
        guard checkpoint.state == state else { throw MatchCheckpointStore.StoreError.inconsistentHistory }
        sessionCheckpoint = checkpoint
    }

    mutating func recordElapsedTime(_ seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds >= elapsedSeconds else {
            throw MatchCheckpointStore.StoreError.invalidDuration
        }
        elapsedSeconds = seconds
    }

    /// The engine, not a duplicated move interpreter, validates the history.
    /// Exact equality also checks the saved generator position after dice/cards.
    func validateHistory() throws {
        try validateSetup()
        var replay = initialState
        for entry in moves {
            try RulesEngine.apply(entry.move, by: entry.actor, to: &replay)
        }
        guard replay == state else { throw MatchCheckpointStore.StoreError.inconsistentHistory }
        if let sessionCheckpoint, sessionCheckpoint.state != state {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
        try sessionCheckpoint?.validate()
    }

    /// The app roster and the engine state are one checkpoint generation.
    /// Reject disagreement rather than restoring names or rules for a
    /// different table onto an otherwise replayable board.
    private func validateSetup() throws {
        guard setup.isValidMatch,
              setup.seats.count == state.players.count,
              setup.seats.count == initialState.players.count,
              setup.victoryPointTarget == state.victoryPointTarget,
              setup.victoryPointTarget == initialState.victoryPointTarget,
              state.players.map(\.id.index).elementsEqual(setup.seats.indices),
              initialState.players.map(\.id.index).elementsEqual(setup.seats.indices) else {
            throw MatchCheckpointStore.StoreError.invalidSetup
        }
    }
}

/// Versioned production authority for match state, history, accounting, and
/// retryable exports. Loading validates the complete document before use.
struct MatchCheckpointDocument: Codable, Equatable, Sendable {
    struct Completion: Codable, Equatable, Sendable {
        let winner: PlayerID
        let humanSeat: PlayerID?
        let finalVP: Int
        let duration: TimeInterval
    }

    static let currentSchemaVersion = 1
    let schemaVersion: Int
    private(set) var revision: Int
    private(set) var activeMatch: MatchCheckpoint?
    private(set) var statistics = GameStats()
    private(set) var completions: [UUID: Completion] = [:]
    private(set) var pendingExports: [UUID: MatchCheckpoint] = [:]

    init(activeMatch: MatchCheckpoint?, revision: Int = 0) {
        self.schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.activeMatch = activeMatch
    }

    /// A player can have historical totals without an unfinished game.
    /// Creating the new authority must preserve that baseline too.
    init(legacyStatistics: GameStats) {
        self.init(activeMatch: nil)
        statistics = legacyStatistics
    }

    /// Recovery may salvage independently valid accounting/export state from
    /// a decodable document whose active match metadata is unusable.
    init(recovering document: Self, activeMatch: MatchCheckpoint) throws {
        self.init(activeMatch: activeMatch)
        statistics = document.statistics
        completions = document.completions
        pendingExports = document.pendingExports
        try validateAuthority()
    }

    /// Legacy totals cannot reveal whether a terminal save was already counted.
    /// Preserve them exactly, and mark that save handled rather than guessing
    /// an extra increment. The migration revision is still the initial commit.
    init(migratedMatch: MatchCheckpoint, legacyStatistics: GameStats) throws {
        self.init(activeMatch: migratedMatch)
        if case .gameOver = migratedMatch.state.phase {
            try recordCompletion(duration: migratedMatch.elapsedSeconds)
        }
        statistics = legacyStatistics
        revision = 0
    }

    /// Build an unpublished candidate. The caller commits it before exposing
    /// its state; failures leave this document unchanged. A winning move and
    /// its accounting receipt belong to the same revision.
    func applying(_ move: GameMove, by actor: PlayerID, elapsedSeconds: TimeInterval) throws -> Self {
        guard var match = activeMatch, revision < Int.max else {
            throw MatchCheckpointStore.StoreError.staleRevision
        }
        try match.recordElapsedTime(elapsedSeconds)
        try match.apply(move, by: actor)
        var next = self
        next.activeMatch = match
        if case .gameOver = match.state.phase { try next.recordCompletion(duration: elapsedSeconds) }
        next.revision = revision + 1
        return next
    }

    /// Persist the actual candidate session's bookkeeping after its move.
    /// Replay verifies the step agrees with that session before either reaches
    /// disk. The caller keeps the candidate session, rather than rebuilding it.
    func recording(_ step: GameSession.Step, session: GameSession.Checkpoint,
                   elapsedSeconds: TimeInterval) throws -> Self {
        var next = try applying(step.move, by: step.actor, elapsedSeconds: elapsedSeconds)
        try next.activeMatch?.attachSession(session)
        return next
    }

    /// Bank foreground duration without manufacturing a game action. Finished
    /// matches keep their frozen duration, and identical values are retry-safe.
    func recordingElapsedTime(_ seconds: TimeInterval) throws -> Self {
        guard seconds.isFinite, seconds >= 0 else { throw MatchCheckpointStore.StoreError.invalidDuration }
        guard var match = activeMatch else { return self }
        if case .gameOver = match.state.phase { return self }
        if seconds == match.elapsedSeconds { return self }
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        try match.recordElapsedTime(seconds)
        var next = self
        next.activeMatch = match
        next.revision += 1
        return next
    }

    /// Switching or clearing the table retains the displaced recording in the
    /// same atomic revision. Export failure must never make New Game lose it.
    func replacingActiveMatch(with match: MatchCheckpoint?) throws -> Self {
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        if let match {
            guard match.id != activeMatch?.id, pendingExports[match.id] == nil,
                  completions[match.id] == nil else {
                throw MatchCheckpointStore.StoreError.inconsistentHistory
            }
            try match.validateHistory()
        }
        var next = self
        if let activeMatch { next.pendingExports[activeMatch.id] = activeMatch }
        next.activeMatch = match
        next.revision += 1
        return next
    }

    /// Acknowledge the exact snapshot exported, never just a UUID. A stale
    /// acknowledgement must not erase a newer recording awaiting export.
    func acknowledgingExport(of match: MatchCheckpoint) throws -> Self {
        guard revision < Int.max, pendingExports[match.id] == match else {
            throw MatchCheckpointStore.StoreError.staleRevision
        }
        var next = self
        next.pendingExports[match.id] = nil
        next.revision += 1
        return next
    }

    /// Freeze one receipt and its totals in the same document as the terminal
    /// state. Repeating completion after an unacknowledged commit is a no-op.
    mutating func recordCompletion(duration: TimeInterval) throws {
        guard var match = activeMatch, case .gameOver(let winner) = match.state.phase,
              duration.isFinite, duration >= 0, revision < Int.max else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        guard completions[match.id] == nil else { return }
        let humans = match.setup.humanSeats
        let human = humans.count == 1 ? PlayerID(index: humans[0].index) : nil
        guard human.map({ match.state.players.indices.contains($0.index) }) ?? true else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        let points = human.map { min(match.state.victoryPoints(for: $0), match.state.victoryPointTarget) } ?? 0
        let updatedStatistics = try human.map {
            try addingCompletion(won: winner == $0, points: points, duration: duration)
        } ?? statistics
        try match.recordElapsedTime(duration)
        activeMatch = match
        completions[match.id] = Completion(winner: winner, humanSeat: human, finalVP: points, duration: duration)
        statistics = updatedStatistics
        revision += 1
    }

    /// Validate arithmetic before changing either totals or receipts. A damaged
    /// baseline must produce a recoverable error, not an integer trap or an
    /// infinite duration that JSON cannot persist after the game was counted.
    private func addingCompletion(won: Bool, points: Int, duration: TimeInterval) throws -> GameStats {
        let played = statistics.gamesPlayed.addingReportingOverflow(1)
        let wins = statistics.gamesWon.addingReportingOverflow(won ? 1 : 0)
        let finalVP = statistics.totalFinalVP.addingReportingOverflow(points)
        let totalDuration = statistics.totalDurationSeconds + duration
        guard !played.overflow, !wins.overflow, !finalVP.overflow,
              statistics.gamesPlayed >= 0, statistics.gamesWon >= 0,
              statistics.gamesWon <= statistics.gamesPlayed, statistics.totalFinalVP >= 0,
              statistics.totalDurationSeconds >= 0, points >= 0, totalDuration.isFinite else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        return GameStats(gamesPlayed: played.partialValue, gamesWon: wins.partialValue,
                         totalFinalVP: finalVP.partialValue, totalDurationSeconds: totalDuration)
    }

    /// Reset the displayed totals, not the durable knowledge of which matches
    /// were processed. Otherwise reopening the last winner undoes the reset.
    mutating func resetStatistics() throws {
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        statistics = GameStats()
        revision += 1
    }

    /// Archived histories remain authoritative until exported. Validate them
    /// just like the active match; a valid active board cannot excuse a damaged
    /// recording or an archive key referring to a different match identity.
    func validateAuthority() throws {
        try validateStatistics()
        try activeMatch?.validateHistory()
        for id in pendingExports.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let match = pendingExports[id], match.id == id, id != activeMatch?.id else {
                throw MatchCheckpointStore.StoreError.inconsistentHistory
            }
            try match.validateHistory()
        }
        try validateCompletions()
    }

    private func validateStatistics() throws {
        guard revision >= 0, statistics.gamesPlayed >= 0, statistics.gamesWon >= 0,
              statistics.gamesWon <= statistics.gamesPlayed, statistics.totalFinalVP >= 0,
              statistics.totalDurationSeconds.isFinite, statistics.totalDurationSeconds >= 0 else {
            throw MatchCheckpointStore.StoreError.invalidStatistics
        }
    }

    private func validateCompletions() throws {
        let retained = retainedMatchesByID()
        for id in completions.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let completion = completions[id], completion.winner.index >= 0,
                  completion.humanSeat.map({ $0.index >= 0 }) ?? true,
                  completion.finalVP >= 0, completion.duration.isFinite, completion.duration >= 0 else {
                throw MatchCheckpointStore.StoreError.invalidCompletion
            }
            if let match = retained[id] { try validate(completion, against: match) }
        }
    }

    private func retainedMatchesByID() -> [UUID: MatchCheckpoint] {
        var retained = pendingExports
        if let activeMatch { retained[activeMatch.id] = activeMatch }
        return retained
    }

    private func validate(_ completion: Completion, against match: MatchCheckpoint) throws {
        guard case .gameOver(let winner) = match.state.phase, completion.winner == winner else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        let humans = match.setup.humanSeats
        let expectedHuman = humans.count == 1 ? humans[0].index : nil
        let expectedPoints = expectedHuman.map {
            min(match.state.victoryPoints(for: PlayerID(index: $0)), match.state.victoryPointTarget)
        } ?? 0
        guard completion.humanSeat?.index == expectedHuman,
              completion.finalVP == expectedPoints,
              completion.duration == match.elapsedSeconds else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
    }
}

/// Serializes app-process commits and refuses stale revisions. Atomic replacement
/// means a process interruption leaves the prior or next document, not separate
/// generations of state and roster. This is not a power-loss durability claim.
@MainActor
struct MatchCheckpointStore {
    enum StoreError: Error {
        case unsupportedSchema, staleRevision, inconsistentHistory, invalidSetup
        case invalidStatistics, invalidCompletion, invalidDuration, recoveryNotPreserved
    }
    enum CommitStage: Sendable { case beforeReplace, afterReplace }

    let fileURL: URL
    private let atCommitStage: (CommitStage) throws -> Void

    /// The hook models an interruption at the filesystem boundary, not a
    /// gameplay collaborator. Production leaves it empty; process-kill tests
    /// can terminate a child at either side of the atomic replacement.
    init(fileURL: URL, atCommitStage: @escaping (CommitStage) throws -> Void = { _ in }) {
        self.fileURL = fileURL
        self.atCommitStage = atCommitStage
    }

    func load() throws -> MatchCheckpointDocument? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let document = try JSONDecoder().decode(MatchCheckpointDocument.self, from: data)
        guard document.schemaVersion == MatchCheckpointDocument.currentSchemaVersion else {
            throw StoreError.unsupportedSchema
        }
        try document.validateAuthority()
        return document
    }

    /// Recovery-only decode. Callers must never publish this value directly;
    /// it exists so valid independent accounting can survive a bad active match.
    func decodeForRecovery() throws -> MatchCheckpointDocument? {
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile { return nil }
        let document = try JSONDecoder().decode(MatchCheckpointDocument.self, from: data)
        guard document.schemaVersion == MatchCheckpointDocument.currentSchemaVersion else {
            throw StoreError.unsupportedSchema
        }
        return document
    }

    /// Explicit recovery replacement is allowed only after an independent copy
    /// preserves the exact source bytes. Recheck at the write boundary so a
    /// stale backup cannot authorize replacing a subsequently changed save.
    func replaceAfterRecovery(_ document: MatchCheckpointDocument, preservedOriginalAt backup: URL) throws {
        guard backup.resolvingSymlinksInPath() != fileURL.resolvingSymlinksInPath(),
              document.schemaVersion == MatchCheckpointDocument.currentSchemaVersion,
              document.revision == 0 else { throw StoreError.recoveryNotPreserved }
        try document.validateAuthority()
        let original = try Data(contentsOf: fileURL)
        guard try Data(contentsOf: backup) == original else { throw StoreError.recoveryNotPreserved }
        let encoded = try JSONEncoder().encode(document)
        try atCommitStage(.beforeReplace)
        guard try Data(contentsOf: fileURL) == original,
              try Data(contentsOf: backup) == original else { throw StoreError.recoveryNotPreserved }
        try encoded.write(to: fileURL, options: .atomic)
        try atCommitStage(.afterReplace)
    }

    func commit(_ document: MatchCheckpointDocument, replacingRevision expected: Int?) throws {
        let current = try load()
        if current == document { return } // Commit succeeded before its acknowledgement was lost.
        guard current?.revision == expected,
              expected.map({ $0 >= 0 && $0 < Int.max }) ?? true,
              document.revision == (expected.map { $0 + 1 } ?? 0) else {
            throw StoreError.staleRevision
        }
        try document.validateAuthority()
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atCommitStage(.beforeReplace)
        try data.write(to: fileURL, options: .atomic)
        try atCommitStage(.afterReplace)
    }
}
