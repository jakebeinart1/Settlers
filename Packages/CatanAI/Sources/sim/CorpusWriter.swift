import CatanAI
import CatanEngine
import Foundation

enum CorpusError: Error, CustomStringConvertible {
    case byteCap(Int)
    case invariant(String)

    var description: String {
        switch self {
        case .byteCap(let limit): "decision trace byte cap exceeded (\(limit) bytes)"
        case .invariant(let message): message
        }
    }
}

/// Per-invocation export, never global telemetry. Policy requires Sendable;
/// this reference is @unchecked because Foundation's encoder/handle and the
/// counters are mutable. Every access after init, including the entire policy
/// call, is under `lock`. No handle, encoder or mutable state escapes. Serial
/// calls therefore have one actual invocation/return order, not an order
/// reconstructed from GameSession's delayed trade-response telemetry.
final class CorpusWriter: @unchecked Sendable {
    static let defaultMaxBytes = 256 * 1024 * 1024
    private static let failureReserve = 512
    private let lock = NSLock()
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private let maxBytes: Int
    private var bytesWritten = 0
    private var seed: UInt64 = 0
    private var invocations = 0
    private var evaluations = 0

    init(path: String, maxBytes: Int) throws {
        self.maxBytes = maxBytes
        let url = URL(fileURLWithPath: path)
        // Exclusive creation, not an existence check followed by truncation.
        // Write directly to the requested path so crashes retain their prefix.
        try Data().write(to: url, options: .withoutOverwriting)
        handle = try FileHandle(forWritingTo: url)
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    }

    var invocationCount: Int { locked { invocations } }
    var evaluationCount: Int { locked { evaluations } }

    func start(seed: UInt64, payload: CorpusStart) {
        locked {
            self.seed = seed
            invocations = 0
            evaluations = 0
            try append(type: "start", payload: payload)
        }
    }

    /// The invocation is on disk before calling the policy. A crash in the
    /// policy leaves an unmatched invocation containing its full input state.
    func decide(
        policyID: String,
        observation: GameObservation,
        rng: inout RandomSource,
        choose: (inout RandomSource, inout [TradeAssessment]) -> GameMove
    ) -> GameMove {
        locked {
            let index = invocations
            let before = rng
            try append(type: "invocation", payload: CorpusInvocation(
                evaluationIndex: index, policyID: policyID,
                observation: observation, policyRNGBefore: before))
            invocations += 1
            var assessments: [TradeAssessment] = []
            let chosen = choose(&rng, &assessments)
            try append(type: "evaluation", payload: CorpusEvaluation(
                evaluationIndex: index, policyID: policyID, observation: observation,
                observationText: StateEncoding.promptDescription(observation),
                chosenMove: chosen, tradeAssessments: assessments,
                policyRNGBefore: before, policyRNGAfter: rng))
            evaluations += 1
            return chosen
        }
    }

    func verify(session: GameSession) {
        locked {
            guard invocations == evaluations, evaluations == session.policyEvaluationCount else {
                throw CorpusError.invariant("trace/session policy evaluation counts disagree")
            }
        }
    }

    func commit(moveIndex: Int, step: GameSession.Step, session: GameSession) {
        locked {
            try append(type: "commit", payload: CorpusCommit(
                moveIndex: moveIndex, actor: step.actor, move: step.move,
                checkpoint: session.checkpoint))
        }
    }

    func end(session: GameSession, moves: Int) {
        locked {
            let reason: String
            var winner: Int?
            switch session.nextActor() {
            case .gameOver(let seat): reason = "gameOver"; winner = seat.index
            case .awaitingExternalSeat: reason = "awaitingExternalSeat"
            case .seat: reason = "moveCap"
            }
            try append(type: "end", payload: CorpusEnd(
                reason: reason, winner: winner, moves: moves,
                evaluationCount: evaluations, checkpoint: session.checkpoint))
        }
    }

    func finish() {
        locked {
            try handle.synchronize()
            try handle.close()
        }
    }

    func abort(_ error: any Error) -> Never {
        lock.lock()
        terminate(error)
    }

    private func locked<Value>(_ action: () throws -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        do { return try action() } catch { terminate(error) }
    }

    private func line<Payload: Encodable>(type: String, payload: Payload) throws -> Data {
        var data = try encoder.encode(CorpusRecord(type: type, seed: seed, payload: payload))
        data.append(0x0A)
        return data
    }

    private func append<Payload: Encodable>(type: String, payload: Payload) throws {
        let data = try line(type: type, payload: payload)
        let usableBytes = max(0, maxBytes - Self.failureReserve)
        guard data.count <= usableBytes - bytesWritten else { throw CorpusError.byteCap(maxBytes) }
        try handle.write(contentsOf: data)
        bytesWritten += data.count
    }

    /// Only called with the lock held. Failed writes may leave a torn final
    /// line; truncate back to the last checked line before attempting a footer.
    /// Failure to write/close the footer is itself reported, never swallowed.
    private func terminate(_ error: any Error) -> Never {
        var message = "sim: decision export failed: \(error); retained trace prefix"
        do {
            try handle.truncate(atOffset: UInt64(bytesWritten))
            try handle.seek(toOffset: UInt64(bytesWritten))
            let reason = error is CorpusError ? String(describing: error) : "traceIOOrEncodingFailure"
            let data = try line(type: "failure", payload: CorpusFailure(
                reason: reason, invocationCount: invocations, evaluationCount: evaluations))
            if data.count <= maxBytes - bytesWritten {
                try handle.write(contentsOf: data)
            } else {
                message += "; no room for failure footer"
            }
            try handle.synchronize()
            try handle.close()
        } catch {
            message += "; failure footer could not be completed: \(error)"
        }
        do {
            try FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
        } catch {
            fatalError("\(message); stderr write failed: \(error)")
        }
        exit(1)
    }
}
