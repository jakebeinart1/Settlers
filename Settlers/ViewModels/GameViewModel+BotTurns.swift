import Foundation
import CatanEngine

/// Policy evaluation and rule application run on a value snapshot off the UI
/// actor. Durable publication stays serialized on the main actor.
@MainActor
extension GameViewModel {
    public func runBotTurnIfNeeded() async {
        do { try reconcileHumanTradeOffers() } catch { return }
        guard canAdvanceBots else { return }
        guard !isProcessingBotTurns else {
            botRestartRequested = true
            return
        }
        isProcessingBotTurns = true
        let generation = gameGeneration
        defer {
            isProcessingBotTurns = false
            lastBotActionAt = nil
            skipsBotPacing = false
            botPacingWait = nil
            let shouldRestart = generation != gameGeneration || botRestartRequested || Task.isCancelled
            botRestartRequested = false
            if case .failed = botTurnProgress {} else { botTurnProgress = nil }
            if shouldRestart, canAdvanceBots {
                Task { await runBotTurnIfNeeded() }
            }
        }

        // The loop is now only pacing and persistence. Choosing the move,
        // deciding whose turn it is and the runaway-action backstop all live
        // in `GameSession`, which a headless harness runs too - so what is
        // measured offline is what is played here.
        while case .seat(let actor) = session.nextActor() {
            do { try reconcileHumanTradeOffers() } catch { return }
            // Stop while the human has a trade decision on screen.
            //
            // This is why an incoming offer used to flash: the card is a live
            // projection of `pendingTradeOffers`, the proposing bot took its
            // next action about a second later, and `endTurn` clears every
            // pending offer - so the card appeared and vanished before it could
            // be read, let alone answered.
            //
            // **`return`, not a parked continuation.** Parking here would hold
            // `isProcessingBotTurns` for the whole wait, and that flag is what
            // the restart path guards on - so the human's own move would find
            // the loop "already running" and do nothing, and `startNewGame`
            // would bump `gameGeneration` without ever resuming the
            // continuation, leaving the flag stuck true and the new game's bots
            // frozen forever. Returning lets `defer` clear it, and the restart
            // already exists: answering the offer goes through `apply`, which
            // ends in `Task { await runBotTurnIfNeeded() }`.
            if openIncomingOffer != nil || pendingDevCardReveal != nil
                || pendingDevCardResolution != nil { return }

            // Same `return`-don't-park reasoning as the offer check above:
            // parking here would hold `isProcessingBotTurns` for as long as
            // the surface stayed open, and `GameView` restarts the loop when
            // the final blocking surface closes.
            if isBlockingSurfaceOpen { return }

            // The deliberate viewing interval is separate from real CPU work.
            await waitForNextBotAction()
            guard generation == gameGeneration, canAdvanceBots, !Task.isCancelled else { return }
            let revision = checkpointDocument?.revision
            botTurnProgress = .thinking(seat: actor)
            do {
                guard let prepared = try await prepareBotStep() else { break }
                guard generation == gameGeneration, canAdvanceBots, !Task.isCancelled else { return }
                guard revision == checkpointDocument?.revision else { continue }
                beginEventBatch()
                try commitStep(prepared.step, candidate: prepared.session)
                lastBotActionAt = Date()
            } catch is MatchPersistenceFailure {
                return
            } catch {
                guard generation == gameGeneration, revision == checkpointDocument?.revision,
                      appIsActive, !isBlockingSurfaceOpen, !Task.isCancelled else { return }
                // A policy chose a move the rules reject: the two disagree,
                // which is a bug rather than a position to recover from. It was
                // previously a bare `try?`, so the loop simply stopped and the
                // game sat frozen on a bot's turn with nothing said. The
                // rejected candidate never replaces the committed policy RNG.
                botTurnProgress = .failed(seat: actor, message: error.localizedDescription)
                return
            }
        }
    }

    private var canAdvanceBots: Bool {
        guard savedGameAvailability.canResume, appIsActive, !persistenceBlocked,
              !isBlockingSurfaceOpen, openIncomingOffer == nil,
              pendingDevCardReveal == nil, pendingDevCardResolution == nil else { return false }
        if case .failed = botTurnProgress { return false }
        return true
    }

    private func prepareBotStep() async throws -> PreparedBotStep? {
        let snapshot = session
        return try await Task.detached(priority: .userInitiated) {
            var candidate = snapshot
            guard let (seat, move) = candidate.decideNext() else { return nil as PreparedBotStep? }
            let step = try candidate.commit(seat: seat, move: move)
            return PreparedBotStep(session: candidate, step: step)
        }.value
    }

    var activeBotSeat: PlayerID? {
        guard case .seat(let seat) = session.nextActor(), !humanSeats.contains(seat) else { return nil }
        return seat
    }

    /// Skip viewing pauses for this CPU run, never a required human response.
    func skipBotPauses() {
        guard activeBotSeat != nil, canAdvanceBots else { return }
        skipsBotPacing = true
        botPacingWait?.cancel()
        Task { await runBotTurnIfNeeded() }
    }

    func retryBotProgress() {
        if persistenceBlocked, !retryPersistence() { return }
        botTurnProgress = nil
        Task { await runBotTurnIfNeeded() }
    }

}
