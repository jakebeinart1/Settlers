import CatanEngine
import Foundation

/// Diagnostic observations, not training examples. Keeps only one encoded row and
/// one operation's evaluations; the 256 MiB file budget reserves a failure footer.
/// Collection order inside Codable states is not canonical JSON byte order. Legal
/// move arrays retain the exact order supplied to the policy, without recomputation.
final class DecisionTraceWriter {
    static let maximumBytes = 256 * 1024 * 1024
    private static let footerBytes = 4096
    private let handle: FileHandle
    private let encoder = JSONEncoder()
    private let byteLimit: Int
    private var bytesWritten = 0
    private var sequence = 0
    private var seed: UInt64 = 0
    private var moveIndex = 0
    private var nextEvaluation = 0
    private var exhausted = false

    enum Failure: Error { case byteLimit, invalidEvaluationOrder, invalidLimit }

    private struct Row<Payload: Encodable>: Encodable {
        let schemaVersion = 1
        let type: String
        let sequence: Int
        let seed: UInt64
        let moveIndex: Int
        let payload: Payload
    }

    struct Start: Encodable {
        let buildID: String
        let policyIDs: [String]
        let boardMode: String
        let checkpointPath: String?
        let declaredCheckpointID: String?
        let state: GameState
        let informationPolicy = "full-diagnostic-state"
    }

    private struct Commit: Encodable {
        let actor: PlayerID
        let move: GameMove
        let events: [GameEvent]
        let policyTrace: PolicyTrace?
        let phase: GamePhase
        let victoryPoints: [Int]
    }

    private struct End: Encodable {
        let reason: String
        let winner: Int?
        let victoryPoints: [Int]
        let evaluationCount: Int
        let state: GameState
        let policyRNG: RandomSource
        let fingerprint: String?
        let error: String?
    }

    private struct Limit: Encodable {
        let reason = "traceByteLimit"
        let complete = false
        let byteLimit: Int
        let evaluationCount: Int
    }

    init(path: String, byteLimit: Int = maximumBytes) throws {
        guard byteLimit >= Self.footerBytes * 2 else { throw Failure.invalidLimit }
        self.byteLimit = byteLimit
        let url = URL(fileURLWithPath: path)
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    func start(seed: UInt64, metadata: Start) throws {
        self.seed = seed
        moveIndex = 0
        nextEvaluation = 0
        try write("start", metadata)
    }

    /// The queued answer is evaluated during a proposal commit, not when it is
    /// returned next iteration. Include it now and ignore its later re-delivery.
    func evaluations(_ session: GameSession) throws {
        var decisions = session.lastPolicyDecisions
        if let queued = session.queuedPolicyDecision,
           !decisions.contains(where: { $0.evaluationIndex == queued.evaluationIndex }) {
            decisions.append(queued)
        }
        for decision in decisions.sorted(by: { $0.evaluationIndex < $1.evaluationIndex }) {
            if decision.evaluationIndex < nextEvaluation { continue }
            guard decision.evaluationIndex == nextEvaluation,
                  decision.policyTrace?.evaluationIndex == nextEvaluation else {
                throw Failure.invalidEvaluationOrder
            }
            try write("evaluation", decision)
            nextEvaluation += 1
        }
        guard nextEvaluation == session.policyEvaluationCount else { throw Failure.invalidEvaluationOrder }
    }

    /// Rule application precedes responder evaluations inside commit. Write the
    /// authoritative applied result first, then drain those responder evaluations.
    func commit(_ step: GameSession.Step, session: GameSession) throws {
        try write("commit", Commit(actor: step.actor, move: step.move, events: step.events,
                                   policyTrace: step.policyTrace, phase: session.state.phase,
                                   victoryPoints: points(session.state)))
        moveIndex += 1
        try evaluations(session)
    }

    func end(reason: String, session: GameSession, fingerprint: String? = nil, error: String? = nil) throws {
        try evaluations(session)
        var winner: Int?
        if case .gameOver(let seat) = session.state.phase { winner = seat.index }
        try write("end", End(reason: reason, winner: winner, victoryPoints: points(session.state),
                             evaluationCount: session.policyEvaluationCount, state: session.state,
                             policyRNG: session.policyRNG, fingerprint: fingerprint, error: error))
    }

    func finish() throws {
        try handle.synchronize()
        try handle.close()
    }

    private func points(_ state: GameState) -> [Int] {
        state.players.map { state.victoryPoints(for: $0.id) }
    }

    private func encoded<Payload: Encodable>(_ type: String, _ payload: Payload) throws -> Data {
        var data = try encoder.encode(Row(type: type, sequence: sequence, seed: seed,
                                          moveIndex: moveIndex, payload: payload))
        data.append(0x0A)
        return data
    }

    private func write<Payload: Encodable>(_ type: String, _ payload: Payload) throws {
        guard !exhausted else { throw Failure.byteLimit }
        let data = try encoded(type, payload)
        guard data.count <= byteLimit - Self.footerBytes - bytesWritten else {
            exhausted = true
            let footer = try encoded("end", Limit(byteLimit: byteLimit, evaluationCount: nextEvaluation))
            try append(footer)
            try handle.synchronize()
            throw Failure.byteLimit
        }
        try append(data)
    }

    /// A short/failed write must not leave half a JSON row masquerading as evidence.
    /// Disk-full cannot guarantee a footer; the retained complete prefix plus the
    /// nonzero process exit is authoritative in that case, never a success row.
    private func append(_ data: Data) throws {
        do {
            try handle.write(contentsOf: data)
        } catch {
            try handle.truncate(atOffset: UInt64(bytesWritten))
            try handle.seekToEnd()
            throw error
        }
        bytesWritten += data.count
        sequence += 1
    }
}
