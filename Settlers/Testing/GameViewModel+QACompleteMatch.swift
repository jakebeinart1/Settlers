#if DEBUG
import CatanEngine
import CatanAI

private enum CompleteMatchQALimits {
    static let maximumMoves = 10_000
}

enum QACompleteMatchFailure: Error {
    case stoppedBeforeGameOver, moveLimitExceeded
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
        for _ in 0..<CompleteMatchQALimits.maximumMoves {
            try qaAcknowledgeCards()
            if case .gameOver = state.phase { return }
            try Task.checkCancellation()
            try qaPlayStep(humanRNG: &humanRNG)
            await Task.yield()
        }
        throw QACompleteMatchFailure.moveLimitExceeded
    }

    private func qaPlayStep(humanRNG: inout RandomSource) throws {
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
            try qaAcknowledgeCards()
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
    }
}
#endif
