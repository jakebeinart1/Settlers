import Foundation
import CatanEngine

/// Every unit keeps its ordinary replay move and the session checkpoint after
/// that move. The complete collection still replaces the save only once.
struct NavalHarvestStep: Sendable {
    let step: GameSession.Step
    let checkpoint: GameSession.Checkpoint
}

@MainActor
extension GameViewModel {
    /// Shared human preconditions apply to single moves and complete harvests.
    func validateHumanDecision() throws {
        if let message = savedGameAvailability.recoveryMessage {
            throw SavedGameRecoveryError.blocked(message)
        }
        guard pendingDevCardReveal == nil, pendingDevCardResolution == nil else {
            throw MoveError.other("Review the development card before continuing.")
        }
        guard pendingShipCapture == nil else {
            throw MoveError.other("Review the ship's change of ownership before continuing.")
        }
    }

    struct NavalHarvestObligation {
        let context: NavalHarvestDraft.Context
        let progress: NavalHarvestProgress
        let bank: [Resource: Int]
        var requiredCount: Int {
            min(progress.remaining, Resource.allCases.reduce(0) { $0 + bank[$1, default: 0] })
        }
    }

    var currentNavalHarvestObligation: NavalHarvestObligation? {
        let owner = humanPlayer
        guard let progress = Naval.harvestProgress(for: owner, in: state) else { return nil }
        let context = NavalHarvestDraft.Context(matchID: checkpointDocument?.activeMatch?.id,
            owner: owner, moveCount: checkpointDocument?.activeMatch?.moves.count ?? 0, remaining: progress.remaining)
        return NavalHarvestObligation(context: context, progress: progress, bank: state.bank)
    }

    func prepareNavalHarvestPresentation() {
        guard let obligation = currentNavalHarvestObligation else {
            navalHarvestDraft.reset()
            return
        }
        navalHarvestDraft.reconcile(context: obligation.context, bank: obligation.bank,
                                   required: obligation.requiredCount)
    }

    func selectForNavalHarvest(_ resource: Resource) {
        prepareNavalHarvestPresentation()
        guard let obligation = currentNavalHarvestObligation else { return }
        navalHarvestDraft.add(resource, bank: obligation.bank, required: obligation.requiredCount)
    }

    func deselectFromNavalHarvest(_ resource: Resource) {
        prepareNavalHarvestPresentation()
        navalHarvestDraft.remove(resource)
    }

    var canSubmitNavalHarvest: Bool {
        guard let obligation = currentNavalHarvestObligation, !persistenceBlocked else { return false }
        return obligation.requiredCount > 0 && navalHarvestDraft.context == obligation.context
            && navalHarvestDraft.selectedCount == obligation.requiredCount
    }

    @discardableResult
    func submitNavalHarvest() -> Bool {
        prepareNavalHarvestPresentation()
        guard canSubmitNavalHarvest else { return false }
        do {
            try commitNavalHarvest(navalHarvestDraft.resources)
            navalHarvestDraft.reset()
            Task { await runBotTurnIfNeeded() }
            return true
        } catch {
            navalHarvestDraft.fail(error)
            return false
        }
    }

    /// Validate every chosen card on a session copy before writing anything.
    /// Repeated resources are ordinary successive choices; a rejected card or
    /// failed replacement cannot publish the preceding units of the harvest.
    func commitNavalHarvest(_ resources: [Resource]) throws {
        try validateHumanDecision()
        guard let obligation = currentNavalHarvestObligation, !resources.isEmpty,
              resources.count == obligation.requiredCount,
              let document = checkpointDocument else { throw MoveError.wrongPhase }
        var candidate = session
        var frames: [NavalHarvestStep] = []
        for resource in resources {
            let step = try candidate.applyExternal(.chooseResource(resource), by: obligation.context.owner)
            frames.append(NavalHarvestStep(step: step, checkpoint: candidate.checkpoint))
        }
        let next: MatchCheckpointDocument
        do {
            next = try document.recordingHarvest(frames, elapsedSeconds: currentGameDuration)
            try commitDocument(next)
        } catch let failure as MatchPersistenceFailure {
            throw failure
        } catch {
            throw reportPersistenceFailure(error)
        }
        beginEventBatch()
        publishCommittedSteps(frames.map(\.step), candidate: candidate, document: next)
    }
}
