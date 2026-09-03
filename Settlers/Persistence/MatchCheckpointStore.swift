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
    }

    /// The engine, not a duplicated move interpreter, validates the history.
    /// Exact equality also checks the saved generator position after dice/cards.
    func validateHistory() throws {
        var replay = initialState
        for entry in moves {
            try RulesEngine.apply(entry.move, by: entry.actor, to: &replay)
        }
        guard replay == state else { throw MatchCheckpointStore.StoreError.inconsistentHistory }
    }
}

/// Versioned authority under construction; production migration is deliberately
/// not enabled until accounting and interruption tests cover the whole commit.
struct MatchCheckpointDocument: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let revision: Int
    let activeMatch: MatchCheckpoint?

    init(activeMatch: MatchCheckpoint?, revision: Int = 0) {
        self.schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.activeMatch = activeMatch
    }
}

/// Serializes app-process commits and refuses stale revisions. Atomic replacement
/// means a process interruption leaves the prior or next document, not separate
/// generations of state and roster. This is not a power-loss durability claim.
@MainActor
struct MatchCheckpointStore {
    enum StoreError: Error { case unsupportedSchema, staleRevision, inconsistentHistory }
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
        guard current?.revision == expected,
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
