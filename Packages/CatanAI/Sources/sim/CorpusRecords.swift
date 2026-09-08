import CatanAI
import CatanEngine

/// Diagnostic records preserve native Codable state, including unordered sets
/// and non-string-keyed dictionaries. Compare those collections semantically,
/// not as raw JSON bytes; ordered moves, decks and evaluations remain ordered.
struct CorpusRecord<Payload: Encodable>: Encodable {
    let schemaVersion = 1
    let type: String
    let seed: UInt64
    let payload: Payload
}

struct CorpusStart: Encodable {
    let buildID: String
    let policyIDs: [String]
    let boardMode: EvaluationBoardMode
    let initialState: GameState
    let weights = BotWeights.default
}

struct CorpusInvocation: Encodable {
    let evaluationIndex: Int
    let policyID: String
    let observation: GameObservation
    let policyRNGBefore: RandomSource
}

struct CorpusEvaluation: Encodable {
    let evaluationIndex: Int
    let policyID: String
    let observation: GameObservation
    let observationText: String
    let chosenMove: GameMove
    let tradeAssessments: [TradeAssessment]
    let policyRNGBefore: RandomSource
    let policyRNGAfter: RandomSource
}

struct CorpusCommit: Encodable {
    let moveIndex: Int
    let actor: PlayerID
    let move: GameMove
    let checkpoint: GameSession.Checkpoint
}

struct CorpusEnd: Encodable {
    let reason: String
    let winner: Int?
    let moves: Int
    let evaluationCount: Int
    let checkpoint: GameSession.Checkpoint

    // An explicit null distinguishes a nondecisive run from a missing field.
    enum CodingKeys: String, CodingKey {
        case reason, winner, moves, evaluationCount, checkpoint
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reason, forKey: .reason)
        try container.encode(winner, forKey: .winner)
        try container.encode(moves, forKey: .moves)
        try container.encode(evaluationCount, forKey: .evaluationCount)
        try container.encode(checkpoint, forKey: .checkpoint)
    }
}

/// A failed export is not an ordinary end or a training outcome. A small
/// reserved footer reports incomplete data without exceeding the byte cap.
struct CorpusFailure: Encodable {
    let reason: String
    let invocationCount: Int
    let evaluationCount: Int
}
