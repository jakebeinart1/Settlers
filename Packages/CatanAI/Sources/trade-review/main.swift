import CatanAI
import CatanEngine
import Foundation

/// Small, bounded offline input: selected historical evaluations, not whole
/// games. Original scores remain evidence; recomputed contributions must match
/// them before they can explain the recorded choice. No policy is invoked.
private struct Input: Decodable {
    let id: String
    let observation: GameObservation
    let chosenMove: GameMove
    let policyID: String
    let tradeAssessments: [TradeAssessment]
}

private struct Output: Encodable {
    let schemaVersion = 1
    let id: String
    let provenance: String
    let scalarRelativeTolerance: Double
    let context: TradeReviewContext
    let assessment: TradeAssessment?
}

// Legacy offers do not preserve Dictionary reduction order across processes.
// Allow rounding noise, never a different accept/reject result or material score.
private let scalarRelativeTolerance = 1e-12

private enum ReviewError: Error {
    case invalidInput(String)
    case scoreMismatch
}

private func personality(_ id: String) throws -> BotPersonality {
    switch id {
    case "heuristic-balanced": .balanced
    case "heuristic-aggressive": .aggressive
    case "heuristic-cautious": .cautious
    default: throw ReviewError.invalidInput("unsupported policy \(id)")
    }
}

private func sameScalars(_ left: TradeAssessment, _ right: TradeAssessment) -> Bool {
    let values: [KeyPath<TradeAssessment, Double>] = [
        \.gainValue, \.costValue, \.netGain, \.baseThreshold, \.threatShift,
        \.standingShift, \.suspicionShift, \.unlockShift, \.threshold,
    ]
    return left.offer == right.offer && left.receiver == right.receiver
        && left.accepted == right.accepted
        && values.allSatisfy {
            let a = left[keyPath: $0], b = right[keyPath: $0]
            return a.isFinite && b.isFinite
                && abs(a - b) <= scalarRelativeTolerance * max(1, abs(a), abs(b))
        }
}

private func enrich(_ input: Input) throws -> Output {
    guard case .respondToTrade(let offerID, _) = input.chosenMove,
          input.observation.legalMoves.contains(input.chosenMove),
          let offer = input.observation.state.pendingTradeOffers.first(where: { $0.id == offerID })
    else { throw ReviewError.invalidInput("not a legal recorded trade response") }
    let context = try TradeReviewContext.make(observation: input.observation, offerID: offerID)
    let profile = try personality(input.policyID)
    var score: TradeAssessment?
    if context.acceptInRecordedMask {
        guard context.nativeAcceptanceError == nil,
              let original = input.tradeAssessments.last(where: { $0.offer.id == offerID }),
              let recomputed = TradeHeuristics.assessment(
                offer: offer, receiver: input.observation.seat, state: input.observation.state,
                personality: profile, includeContributions: true), sameScalars(original, recomputed)
        else { throw ReviewError.scoreMismatch }
        score = recomputed
    }
    let provenance = score == nil ? "native-context-only-no-scalar-match-claimed"
        : "offline-native-recomputation-numerically-matched-to-recorded-scalars"
    return Output(id: input.id, provenance: provenance, scalarRelativeTolerance: scalarRelativeTolerance,
                  context: context, assessment: score)
}

private func run() throws {
    let maxBytes = 8 * 1024 * 1024
    let maxCases = 120
    guard CommandLine.arguments.count == 2 else {
        throw ReviewError.invalidInput("usage: trade-review selected-evaluations.jsonl")
    }
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[1]))
    defer { try? handle.close() } // Read-only input; output errors below are never discarded.
    let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
    guard data.count <= maxBytes, data.last == 0x0A else {
        throw ReviewError.invalidInput("oversized, empty or truncated input")
    }
    let lines = data.split(separator: 0x0A)
    guard lines.count <= maxCases else { throw ReviewError.invalidInput("too many cases") }
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    var ids: Set<String> = []
    for line in lines {
        let input = try decoder.decode(Input.self, from: Data(line))
        guard ids.insert(input.id).inserted else { throw ReviewError.invalidInput("duplicate case ID") }
        var result = try encoder.encode(enrich(input))
        result.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: result)
    }
}

do {
    try run()
} catch {
    try FileHandle.standardError.write(contentsOf: Data("trade-review: \(error)\n".utf8))
    exit(1)
}
