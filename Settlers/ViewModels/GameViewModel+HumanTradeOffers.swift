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

    /// A named offer always needs a reply, even when its recipient lacks
    /// cards. A bot broadcast only considers people who can pay for it.
    private var incomingTradeCandidates: (offer: TradeOffer, seats: [PlayerID])? {
        guard case .mainTurn = state.phase else { return nil }
        if let directed = state.pendingTradeOffers.first(where: { $0.recipient != nil }),
           let recipient = directed.recipient {
            return humanSeats.contains(recipient) ? (directed, [recipient]) : nil
        }
        for offer in state.pendingTradeOffers where !humanSeats.contains(offer.from) {
            let seats = sortedHumanSeats.filter { Trading.bothSidesCanHonour(offer, responder: $0, state: state) }
            if !seats.isEmpty { return (offer, seats) }
        }
        return nil
    }

    /// The runner must settle an unresolved bot proposal even when it won't
    /// ask a person to answer it.
    var hasUnresolvedTradeResponse: Bool { incomingTradeCandidates != nil }

    /// Personal suppression skips that seat without declining for the whole
    /// table. A durably presented offer keeps its eligible recipient on cold
    /// resume, when an earlier seat's temporary round block has reset.
    private var nextTradeResponse: (seat: PlayerID, offer: TradeOffer, needsReply: Bool)? {
        guard let (offer, seats) = incomingTradeCandidates, let first = seats.first else { return nil }
        guard isLocalMultiplayer, offer.recipient == nil else { return (first, offer, true) }

        let context = tradeOfferContext(offer)
        var firstAvailable: PlayerID?
        for seat in seats {
            let policy = humanTradePolicy(for: seat)
            let decision = policy.decision(for: offer, in: state, context: context)
            guard automaticTradeResponse(to: offer, by: seat, decision: decision, context: context) == nil else { continue }
            if policy.isPresented(offer: offer, context: context) { return (seat, offer, true) }
            if firstAvailable == nil { firstAvailable = seat }
        }
        return (firstAvailable ?? first, offer, firstAvailable != nil)
    }

    var owedTradeResponseSeat: PlayerID? {
        guard let response = nextTradeResponse, response.needsReply else { return nil }
        return response.seat
    }

    func tradeResponseOffer(for seat: PlayerID) -> TradeOffer? {
        guard let response = nextTradeResponse, response.seat == seat, response.needsReply else { return nil }
        return response.offer
    }

    /// The suppression and presentation budget applies only to bot offers.
    var rawIncomingOffer: TradeOffer? {
        guard let response = incomingTradeCandidates, response.offer.recipient == nil else { return nil }
        return response.offer
    }

    /// A directed reply is the last move until the proposer reclaims the
    /// phone and acts again. Read it from durable history so a cold resume
    /// at that handoff still shows what the other player decided.
    struct LocalTradeReply: Equatable {
        let proposalID: UUID
        let responder: PlayerID
        let accepted: Bool
    }

    func latestLocalTradeReply(for seat: PlayerID) -> LocalTradeReply? {
        guard let match = checkpointDocument?.activeMatch, let last = match.moves.last,
              case .respondToTrade(let offerID, let accepted) = last.move else { return nil }
        let proposal: TradeOffer?
        if let prior = match.moves.dropLast().last, case .proposeTrade(let offer) = prior.move {
            proposal = offer
        } else {
            proposal = match.initialState.pendingTradeOffers.first { $0.id == offerID }
        }
        guard let proposal, proposal.id == offerID, proposal.from == seat,
              proposal.recipient == last.actor, humanSeats.contains(last.actor) else { return nil }
        return LocalTradeReply(proposalID: offerID, responder: last.actor, accepted: accepted)
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
        while let response = nextTradeResponse, response.offer.recipient == nil {
            let (seat, offer, _) = response
            var policy = humanTradePolicy(for: seat)
            let context = tradeOfferContext(offer)
            let decision = policy.decision(for: offer, in: state, context: context)
            if let move = automaticTradeResponse(to: offer, by: seat, decision: decision, context: context) {
                try commitAutomaticResponse(move, by: seat)
                continue
            }
            guard decision == .present, !needsLocalHandoff,
                  !policy.isPresented(offer: offer, context: context),
                  let document = checkpointDocument else { return }
            policy.recordPresentation(of: offer, in: state, context: context)
            var policies = document.humanTradePolicies ?? [:]
            policies[seat.index] = policy
            try commitDocument(document.recordingTradePresentations(policies))
            return
        }
    }

    private func automaticTradeResponse(
        to offer: TradeOffer, by seat: PlayerID, decision: HumanTradeOfferPolicy.Decision,
        context: HumanTradeOfferPolicy.Context
    ) -> GameMove? {
        switch decision {
        case .reject(let move, _): return move
        case .present where PacingPreferences.shared.blockTradeOffers || isRoundBlocked(context, for: seat):
            // An unseen decline never spends an interruption or teaches a ghost.
            return .respondToTrade(offerID: offer.id, accept: false)
        default: return nil
        }
    }

    private func isRoundBlocked(_ context: HumanTradeOfferPolicy.Context, for seat: PlayerID) -> Bool {
        tradeOffersBlockedUntilTurn[seat].map { context.completedTurns < $0 } ?? false
    }

    /// Declines this offer and every bot offer until the human's next turn.
    /// Offers only arrive on the proposer's own turn, so the turns left in the
    /// round are the seats between the proposer and the human.
    func blockTradeOffersThisRound(after offer: TradeOffer) throws {
        guard offer.recipient == nil else { throw MoveError.invalidTradeTarget }
        let responder = humanPlayer
        let seats = state.players.count
        let turnsUntilHuman = (responder.index - offer.from.index + seats) % seats
        let blockedUntil = tradeOfferContext(offer).completedTurns + turnsUntilHuman
        try respondToIncomingTrade(offer, accept: false, explicit: false)
        tradeOffersBlockedUntilTurn[responder] = blockedUntil
    }

    private func commitAutomaticResponse(_ move: GameMove, by seat: PlayerID) throws {
        var candidate = session
        let step = try candidate.applyExternal(move, by: seat)
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
        guard tradeResponseOffer(for: humanPlayer) == offer,
              offer.recipient == nil || explicit else { throw MoveError.invalidTradeTarget }
        try commitHumanMove(.respondToTrade(offerID: offer.id, accept: accept),
                            declinedOffer: !accept && explicit && offer.recipient == nil ? offer : nil,
                            isHumanDecision: explicit)
        Task { await runBotTurnIfNeeded() }
    }
}
