import Foundation
import CatanEngine

@MainActor
extension GameViewModel {
    /// Resolve a roll's production and capture before ordinary negotiations.
    /// Bots may resolve their own obligations; a human's obligation always waits.
    var hasMandatoryNavalDecision: Bool {
        switch state.phase {
        case .choosingResource, .capturingShip: true
        default: false
        }
    }

    var hasMandatoryHumanNavalDecision: Bool {
        hasMandatoryNavalDecision && state.phase.awaitingSeatIndex.map {
            humanSeats.contains(PlayerID(index: $0))
        } == true
    }

    /// One projection drives both the command dock and the runner. An offer is
    /// either durably presented or actually rejected, never hidden while live.
    var rawIncomingOffer: TradeOffer? {
        state.pendingTradeOffers.first {
            !humanSeats.contains($0.from)
                && Trading.bothSidesCanHonour($0, responder: humanPlayer, state: state)
        }
    }

    func humanTradePolicy(for human: PlayerID) -> HumanTradeOfferPolicy {
        checkpointDocument?.humanTradePolicies?[human.index] ?? HumanTradeOfferPolicy(human: human)
    }

    func tradeOfferContext(_ offer: TradeOffer) -> HumanTradeOfferPolicy.Context {
        let moves = checkpointDocument?.activeMatch?.moves ?? []
        let sequence = moves.lastIndex { $0.move == .proposeTrade(offer) } ?? -1
        let turns = moves.reduce(0) { count, entry in
            if case .endTurn = entry.move { return count + 1 }
            return count
        }
        return .init(completedTurns: turns, proposalSequence: sequence, playerCount: state.players.count)
    }

    /// Called before the runner parks on a human offer, including cold resume.
    /// All housekeeping uses the same revision-checked atomic checkpoint path.
    func reconcileHumanTradeOffers() throws {
        guard appIsActive, !isBlockingSurfaceOpen, !persistenceBlocked, savedGameAvailability.canResume,
              pendingTradeConfirmation == nil, pendingDevCardReveal == nil,
              pendingDevCardResolution == nil, pendingShipCapture == nil, !hasMandatoryNavalDecision else { return }
        while let offer = rawIncomingOffer {
            var policy = humanTradePolicy(for: humanPlayer)
            let context = tradeOfferContext(offer)
            switch policy.decision(for: offer, in: state, context: context) {
            case .notIncoming: return
            case .present where PacingPreferences.shared.blockTradeOffers || isRoundBlocked(context):
                // Declined unseen, so not an explicit human choice: it must not
                // teach a ghost, and it records no rejected exchange class.
                try commitAutomaticResponse(.respondToTrade(offerID: offer.id, accept: false))
            case .present:
                guard !policy.isPresented(offer: offer, context: context) else { return }
                policy.recordPresentation(of: offer, in: state, context: context)
                var policies = checkpointDocument?.humanTradePolicies ?? [:]
                policies[humanPlayer.index] = policy
                guard let document = checkpointDocument else { return }
                try commitDocument(document.recordingTradePresentations(policies))
                return
            case .reject(let move, _):
                try commitAutomaticResponse(move)
            }
        }
    }

    private func isRoundBlocked(_ context: HumanTradeOfferPolicy.Context) -> Bool {
        tradeOffersBlockedUntilTurn.map { context.completedTurns < $0 } ?? false
    }

    /// Declines this offer and every bot offer until the human's next turn.
    /// Offers only arrive on the proposer's own turn, so the turns left in the
    /// round are the seats between the proposer and the human.
    func blockTradeOffersThisRound(after offer: TradeOffer) throws {
        let seats = state.players.count
        let turnsUntilHuman = (humanPlayer.index - offer.from.index + seats) % seats
        tradeOffersBlockedUntilTurn = tradeOfferContext(offer).completedTurns + turnsUntilHuman
        try respondToIncomingTrade(offer, accept: false, explicit: false)
    }

    private func commitAutomaticResponse(_ move: GameMove) throws {
        var candidate = session
        let step = try candidate.applyExternal(move, by: humanPlayer)
        try commitStep(step, candidate: candidate, isHumanDecision: false)
    }

    func tradePolicies(after step: GameSession.Step, declinedOffer: TradeOffer?) -> [Int: HumanTradeOfferPolicy]? {
        guard let offer = declinedOffer else { return checkpointDocument?.humanTradePolicies }
        var policy = humanTradePolicy(for: step.actor)
        policy.recordHumanRejection(of: offer, committed: step, context: tradeOfferContext(offer))
        var policies = checkpointDocument?.humanTradePolicies ?? [:]
        policies[step.actor.index] = policy
        return policies
    }

    /// Timeout means unanswered, not a preference against this exchange class.
    /// Its real response stays in history, but only explicit taps may teach
    /// a ghost; a timeout and a deliberate Decline have the same engine move.
    func respondToIncomingTrade(_ offer: TradeOffer, accept: Bool, explicit: Bool) throws {
        try commitHumanMove(.respondToTrade(offerID: offer.id, accept: accept),
                            declinedOffer: !accept && explicit ? offer : nil, isHumanDecision: explicit)
        Task { await runBotTurnIfNeeded() }
    }
}
