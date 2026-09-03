import Foundation
import CatanEngine

/// One match's state and its replay source travel in the same atomic write.
/// App identity stays outside GameState because it is not a game rule.
struct MatchCheckpoint: Codable, Equatable, Sendable {
    struct RecordedMove: Codable, Equatable, Sendable {
        let actor: PlayerID
        let move: GameMove
    }

    let id: UUID
    let initialState: GameState
    let setup: MatchSetup
    private(set) var state: GameState
    private(set) var moves: [RecordedMove] = []
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var sessionCheckpoint: GameSession.Checkpoint?

    init(id: UUID, initialState: GameState, setup: MatchSetup) {
        self.id = id
        self.initialState = initialState
        self.state = initialState
        self.setup = setup
    }

    mutating func apply(_ move: GameMove, by actor: PlayerID) throws {
        var candidate = state
        try RulesEngine.apply(move, by: actor, to: &candidate)
        state = candidate
        moves.append(RecordedMove(actor: actor, move: move))
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
        var replay = initialState
        for entry in moves {
            try RulesEngine.apply(entry.move, by: entry.actor, to: &replay)
        }
        guard replay == state else { throw MatchCheckpointStore.StoreError.inconsistentHistory }
        if let sessionCheckpoint, sessionCheckpoint.state != state {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
    }
}

/// Versioned authority under construction; production migration is deliberately
/// not enabled until accounting and interruption tests cover the whole commit.
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

    init(activeMatch: MatchCheckpoint?, revision: Int = 0) {
        self.schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.activeMatch = activeMatch
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

    /// Freeze one receipt and its totals in the same document as the terminal
    /// state. Repeating completion after an unacknowledged commit is a no-op.
    mutating func recordCompletion(duration: TimeInterval) throws {
        guard let match = activeMatch, case .gameOver(let winner) = match.state.phase,
              duration.isFinite, duration >= 0, revision < Int.max else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        guard completions[match.id] == nil else { return }
        let humans = match.setup.humanSeats
        let human = humans.count == 1 ? PlayerID(index: humans[0].index) : nil
        let points = human.map { min(match.state.victoryPoints(for: $0), match.state.victoryPointTarget) } ?? 0
        completions[match.id] = Completion(winner: winner, humanSeat: human, finalVP: points, duration: duration)
        if let human {
            statistics.gamesPlayed += 1
            statistics.gamesWon += winner == human ? 1 : 0
            statistics.totalFinalVP += points
            statistics.totalDurationSeconds += duration
        }
        revision += 1
    }

    /// Reset the displayed totals, not the durable knowledge of which matches
    /// were processed. Otherwise reopening the last winner undoes the reset.
    mutating func resetStatistics() throws {
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        statistics = GameStats()
        revision += 1
    }
}

/// Serializes app-process commits and refuses stale revisions. Atomic replacement
/// means a process interruption leaves the prior or next document, not separate
/// generations of state and roster. This is not a power-loss durability claim.
@MainActor
struct MatchCheckpointStore {
    enum StoreError: Error {
        case unsupportedSchema, staleRevision, inconsistentHistory, invalidCompletion, invalidDuration
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
        try document.activeMatch?.validateHistory()
        return document
    }

    func commit(_ document: MatchCheckpointDocument, replacingRevision expected: Int?) throws {
        let current = try load()
        if current == document { return } // Commit succeeded before its acknowledgement was lost.
        guard current?.revision == expected,
              expected.map({ $0 >= 0 && $0 < Int.max }) ?? true,
              document.revision == (expected.map { $0 + 1 } ?? 0) else {
            throw StoreError.staleRevision
        }
        try document.activeMatch?.validateHistory()
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atCommitStage(.beforeReplace)
        try data.write(to: fileURL, options: .atomic)
        try atCommitStage(.afterReplace)
    }
}
