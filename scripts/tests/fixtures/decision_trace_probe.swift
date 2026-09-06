import CatanEngine
import Foundation

/// Small executable test fixture for the actual sim writer, not another game loop.
@main struct DecisionTraceProbe {
    enum Failure: Error { case assertion(String) }
    static func check(_ value: Bool, _ message: String) throws {
        if !value { throw Failure.assertion(message) }
    }

    private struct FixturePolicy: Policy {
        let id = "trace-fixture"
        func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
            _ = rng.next()
            return observation.legalMoves.first {
                switch $0 {
                case .respondToTrade(_, false), .bankTrade: return true
                default: return false
                }
            } ?? .endTurn
        }
    }

    static func start(_ writer: DecisionTraceWriter, _ state: GameState) throws {
        try writer.start(seed: 971, metadata: .init(buildID: "fixture", policyIDs: ["trace-fixture"],
            boardMode: "standard", checkpointPath: nil, declaredCheckpointID: nil, state: state))
    }

    static func fixture(_ mode: String, path: String) throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 971)
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].resources = [.brick: 200]
        state.players[1].resources = [.grain: 1]
        let policies = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, FixturePolicy() as any Policy) })
        var session = GameSession(state: state, policies: policies, policySeed: 817)
        let writer = try DecisionTraceWriter(path: path)
        try start(writer, state)
        if mode == "queued" {
            let offer = TradeOffer.enumerated(from: PlayerID(index: 0), give: [.brick: 1], want: [.grain: 1])
            let step = try session.commit(seat: PlayerID(index: 0), move: .proposeTrade(offer))
            let unchanged = session.checkpoint
            try writer.commit(step, session: session)
            try writer.end(reason: "moveCap", session: session)
            try check(session.checkpoint == unchanged, "tracing re-evaluated queued reply")
        } else {
            for _ in 0...GameSession.maxActionsPerTurn {
                guard let decision = session.decideNextDetailed() else { throw Failure.assertion("no decision") }
                try writer.evaluations(session)
                let step = try session.commit(seat: decision.seat, move: decision.move)
                try writer.commit(step, session: session)
            }
            try writer.end(reason: "fixtureStop", session: session)
        }
        try writer.finish()
    }

    static func limit(path: String) throws {
        let state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 971)
        let writer = try DecisionTraceWriter(path: path, byteLimit: 128 * 1024)
        do {
            for _ in 0..<100 { try start(writer, state) }
            throw Failure.assertion("byte limit was ignored")
        } catch DecisionTraceWriter.Failure.byteLimit {
            try writer.finish()
        }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: path))
        try check(bytes.count <= 128 * 1024, "file exceeded budget")
        try check(DecisionTraceWriter.maximumBytes == 256 * 1024 * 1024, "production budget changed")
    }

    private struct EvaluationRow: Decodable { let payload: GameSession.Decision }
    private struct EndPayload: Decodable, Equatable {
        let state: GameState
        let policyRNG: RandomSource
        let evaluationCount: Int
    }
    private struct EndRow: Decodable { let payload: EndPayload }
    private struct CommitPayload: Decodable, Equatable {
        let actor: PlayerID
        let move: GameMove
        let events: [GameEvent]
        let policyTrace: PolicyTrace?
    }
    private struct CommitRow: Decodable { let payload: CommitPayload }

    static func compare(_ first: String, _ second: String) throws {
        let lhs = try String(contentsOfFile: first, encoding: .utf8).split(separator: "\n")
        let rhs = try String(contentsOfFile: second, encoding: .utf8).split(separator: "\n")
        try check(lhs.count == rhs.count, "row counts differ")
        let decoder = JSONDecoder()
        for (left, right) in zip(lhs, rhs) {
            let a = Data(left.utf8), b = Data(right.utf8)
            let row = try JSONSerialization.jsonObject(with: a) as? [String: Any]
            switch row?["type"] as? String {
            case "evaluation":
                // Typed equality respects map/set semantics AND ordered legal moves.
                try check(decoder.decode(EvaluationRow.self, from: a).payload == decoder.decode(EvaluationRow.self, from: b).payload,
                          "observation/legal/selection differs")
            case "commit":
                try check(decoder.decode(CommitRow.self, from: a).payload == decoder.decode(CommitRow.self, from: b).payload,
                          "actual committed move/events differ")
            case "end":
                try check(decoder.decode(EndRow.self, from: a).payload == decoder.decode(EndRow.self, from: b).payload,
                          "final state/RNG/count differs")
            default: break
            }
        }
    }

    static func main() throws {
        let args = CommandLine.arguments
        switch args[1] {
        case "compare": try compare(args[2], args[3])
        case "limit": try limit(path: args[2])
        default: try fixture(args[1], path: args[2])
        }
    }
}
