#if DEBUG
import Foundation
import Observation
import CatanEngine
import CatanAI

private enum CompleteMatchQALimits {
    static let maximumMoves = 10_000
}

enum QACompleteMatchFailure: Error {
    case stoppedBeforeGameOver, moveLimitExceeded
}

/// Process-local pause state for one explicitly requested onscreen audit.
/// It observes naturally committed positions and never edits the match, RNG,
/// hand, bank or phase. Native tests inspect ordinary card controls, then use
/// the dedicated Continue control to release the waiting production driver.
@MainActor
@Observable
final class QACompleteMatchInspection {
    static let shared = QACompleteMatchInspection()
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-qaInspectCompleteMatch") }

    private(set) var isPaused = false
    private(set) var message = ""
    private var inspected: Set<String> = []

    func reset() {
        precondition(!isPaused, "Only one onscreen complete-match driver may inspect the QA device")
        message = ""
        inspected = []
    }

    func resume() { isPaused = false }

    func hasInspected(_ stage: String) -> Bool { inspected.contains(stage) }

    func pause(stage: String, moveCount: Int, cards: [DevCardInventoryItem]) async throws {
        guard inspected.insert(stage).inserted else { return }
        let hand = cards.map { "\($0.type.rawValue)=\($0.held)" }.joined(separator: ",")
        message = "\(stage); move=\(moveCount); owned=\(hand)"
        print("QA complete-match inspection: \(message)")
        isPaused = true
        defer { isPaused = false }
        while isPaused {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

extension GameViewModel {
    /// Hosted tests drive production persistence; failures reach the runner
    /// rather than trapping the host and losing unrelated test receipts.
    func qaPlayToEnd() throws {
        var humanRNG = RandomSource(seed: 12345)
        for _ in 0..<CompleteMatchQALimits.maximumMoves {
            try qaAcknowledgeCards()
            if case .gameOver = state.phase { return }
            try qaPlayStep(humanRNG: &humanRNG)
        }
        throw QACompleteMatchFailure.moveLimitExceeded
    }

    /// Yield between committed moves so native accessibility and rendering can
    /// inspect a long match without a main-run-loop timeout hiding the result.
    func qaPlayToEndOnscreen() async throws {
        var humanRNG = RandomSource(seed: 12345)
        let inspection = QACompleteMatchInspection.isEnabled ? QACompleteMatchInspection.shared : nil
        inspection?.reset()
        for _ in 0..<CompleteMatchQALimits.maximumMoves {
            if let inspection { try await qaInspectCardsIfNeeded(inspection) }
            try qaAcknowledgeCards()
            if case .gameOver = state.phase { return }
            try Task.checkCancellation()
            try qaPlayStep(humanRNG: &humanRNG, acknowledgesCards: inspection == nil)
            await Task.yield()
        }
        throw QACompleteMatchFailure.moveLimitExceeded
    }

    private func qaPlayStep(humanRNG: inout RandomSource, acknowledgesCards: Bool = true) throws {
        var candidate = session
        do {
            let step: GameSession.Step
            if case .awaitingExternalSeat(let seat) = candidate.nextActor() {
                let observation = GameObservation(seat: seat, state: state,
                    legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
                let move = HeuristicPolicy(personality: .balanced, id: "qa-human").decide(observation, rng: &humanRNG)
                step = try candidate.applyExternal(move, by: seat)
            } else {
                guard let (seat, move) = candidate.decideNext() else {
                    throw QACompleteMatchFailure.stoppedBeforeGameOver
                }
                step = try candidate.commit(seat: seat, move: move)
            }
            try qaCommitStep(step, candidate: candidate)
            if acknowledgesCards { try qaAcknowledgeCards() }
        } catch {
            try qaRecordFailedCheckpoint(candidate.checkpoint, error: error)
            throw error
        }
    }

    /// The driver owns every chair and models the acknowledgements through
    /// durable APIs rather than overwriting the private receipts.
    private func qaAcknowledgeCards() throws {
        if pendingDevCardReveal != nil { try acknowledgeDevCardReveal() }
        if pendingDevCardResolution != nil { try acknowledgeDevCardResolution() }
        if pendingShipCapture != nil { try acknowledgeShipCapture() }
    }

    /// Four opportunities, each at most once: an actual purchase, mature hand,
    /// active-card result and late-game hand. A game need not produce every
    /// type. Fixtures cover all types separately; this run records only the
    /// checkpoints its ordinary policy-driven match genuinely reaches.
    private func qaInspectCardsIfNeeded(_ inspection: QACompleteMatchInspection) async throws {
        if case .gameOver = state.phase { return }
        let human = humanPlayer
        let hand = DevCardInventoryItem.all(for: human, in: state)
        let stage: String?
        if pendingDevCardReveal?.owner == human, !inspection.hasInspected("purchase") {
            stage = "purchase"
        } else if pendingDevCardResolution?.owner == human, !inspection.hasInspected("resolution") {
            stage = "resolution"
        } else if state.phase.awaitingSeatIndex == human.index,
                  hand.contains(where: { $0.status.isPlayable }), !inspection.hasInspected("mature-hand") {
            stage = "mature-hand"
        } else if qaHumanCardInspectionPhase, !hand.isEmpty,
                  state.victoryPoints(for: human) >= state.victoryPointTarget - 3,
                  !inspection.hasInspected("late-hand") {
            stage = "late-hand"
        } else { stage = nil }
        guard let stage else { return }
        let moveCount = checkpointDocument?.activeMatch?.moves.count ?? 0
        try await inspection.pause(stage: stage, moveCount: moveCount, cards: hand)
    }

    private var qaHumanCardInspectionPhase: Bool {
        switch state.phase {
        case .rollDice(let seat), .mainTurn(let seat): seat == humanPlayer.index
        default: false
        }
    }
}
#endif
