import Foundation
import CatanEngine

/// App-owned limits on interruptions, independent of the policy choosing bot moves.
///
/// Evaluate only bot proposals for this human. A suppression carries a real
/// engine response: the caller must commit it through the checkpoint transaction
/// before removing the offer from presentation or continuing the bot loop. On a
/// failed write, retain the offer and the existing persistence blocker. Never use
/// this type as a hide-only predicate while the session still awaits the human.
///
/// Persist this value as optional app checkpoint metadata, defaulting old saves
/// to a fresh policy for their human seat. Presentation accounting must survive
/// resume; it cannot be reconstructed from engine moves alone. Candidate copies
/// become authoritative only after the surrounding checkpoint write succeeds.
/// Decode is not validation: call validate() before using saved metadata, then
/// validate(for:expectedHuman:committedMoves:initialOffers:) against the owning checkpoint.
struct HumanTradeOfferPolicy: Codable, Equatable, Sendable {
    struct Limits: Codable, Equatable, Sendable {
        let perTurn: Int
        let perRound: Int

        init(perTurn: Int = 1, perRound: Int = 3) {
            precondition(perTurn > 0 && perRound > 0)
            self.perTurn = perTurn
            self.perRound = perRound
        }
    }

    /// Derive completedTurns from committed endTurn moves since the checkpoint's
    /// initial position. A table round contains playerCount turns; migration can
    /// start that accounting from a mid-game position rather than seat zero.
    /// proposalSequence is the committed proposal's zero-based move index, not the
    /// checkpoint revision. The sole sentinel, -1, denotes an offer inherited in
    /// initialState.pendingTradeOffers, checked against initialOffers at load.
    /// Rerenders/resume retain the index; a new recorded proposal changes it
    /// even when the content-derived offer UUID repeats. Start a new policy on
    /// restart/new match, and keep a separate value for every human in hot-seat.
    struct Context: Sendable {
        let completedTurns: Int
        let proposalSequence: Int
        let playerCount: Int

        init(completedTurns: Int, proposalSequence: Int, playerCount: Int) {
            precondition(completedTurns >= 0 && proposalSequence >= -1)
            precondition(GameSetup.supportedPlayerCounts.contains(playerCount))
            self.completedTurns = completedTurns
            self.proposalSequence = proposalSequence
            self.playerCount = playerCount
        }

        var round: Int { completedTurns / playerCount }
    }

    enum Reason: Equatable, Sendable {
        case bankEquivalentOrBetter
        case rejectedExchangeClass
        case turnBudget
        case roundBudget
    }

    enum ValidationError: Error, Equatable, Sendable {
        case invalidSeat
        case invalidLimits
        case invalidCounters
        case invalidOccurrence
        case invalidRejectionClass
    }

    enum Decision: Equatable, Sendable {
        case present
        case reject(move: GameMove, reason: Reason)
        /// Not a live, affordable bot proposal in its proposing main turn.
        /// Existing session negotiation handles this case; it is not suppression.
        case notIncoming
    }

    private struct Presentation: Codable, Equatable, Sendable {
        let offerID: UUID
        let proposalSequence: Int
    }

    /// Human-side quantities, deliberately independent of resource identities.
    /// A refused 3-for-1 excludes equal/worse ratios, but leaves 2-for-1 eligible.
    private struct ExchangeClass: Codable, Equatable, Sendable {
        let given: Int
        let received: Int

        init(offer: TradeOffer) {
            given = Resource.allCases.reduce(0) { $0 + offer.want[$1, default: 0] }
            received = Resource.allCases.reduce(0) { $0 + offer.give[$1, default: 0] }
        }

        var isLopsided: Bool { received > 0 && given > received }

        func isAtLeastAsLopsided(as other: Self) -> Bool {
            Double(given) * Double(other.received) >= Double(other.given) * Double(received)
        }
    }

    let human: PlayerID
    let limits: Limits
    private var completedTurns: Int?
    private var round: Int?
    private var presentations: [Presentation] = []
    private var roundPresentationCount = 0
    private var rejectedExchange: ExchangeClass?

    init(human: PlayerID, limits: Limits = Limits()) {
        self.human = human
        self.limits = limits
    }

    /// Structural validation for stand-alone decoded metadata checks.
    /// No runtime preconditions are reached on damaged decoded values. Without
    /// checkpoint history this cannot detect a future index or verify an offer
    /// identity; the contextual overload checks those after history validation.
    func validate() throws {
        guard GameSetup.supportedPlayerCounts.contains(where: { human.index >= 0 && human.index < $0 }) else {
            throw ValidationError.invalidSeat
        }
        guard limits.perTurn > 0, limits.perRound > 0 else { throw ValidationError.invalidLimits }
        try validateStoredCounters()
        try validateStoredOccurrences()
        if let rejectedExchange, !rejectedExchange.isLopsided { throw ValidationError.invalidRejectionClass }
    }

    /// Throw at checkpoint load, never assert on untrusted decoded metadata.
    /// Pass the realized human and complete, independently validated move history
    /// since the checkpoint's initial state. Older accounting is valid: a turn
    /// without an interruption need not update this policy. Future/inconsistent
    /// counters, invented proposals and duplicate/out-of-order indices are not.
    /// Screen exposure and explicit-tap origin cannot be reconstructed from moves;
    /// their persisted counts are checked for consistency, not regenerated.
    func validate(for state: GameState, expectedHuman: PlayerID, committedMoves: [GameMove],
                  initialOffers: [TradeOffer] = []) throws {
        try validate()
        let playerCount = state.players.count
        guard GameSetup.supportedPlayerCounts.contains(playerCount), human == expectedHuman,
              human.index >= 0, human.index < playerCount,
              state.players[human.index].id == human else { throw ValidationError.invalidSeat }
        let historyTurns = committedMoves.filter { $0 == .endTurn }.count
        try validateCounters(playerCount: playerCount, historyTurns: historyTurns)
        try validateOccurrences(in: committedMoves, playerCount: playerCount, initialOffers: initialOffers)
    }

    /// Pure accounting query, not permission to hide a pending engine offer.
    /// Main must use the durably published policy, not an uncommitted candidate,
    /// and combine this with .present before showing a policy-managed card.
    /// Eligibility alone does not reserve a presentation; a repeated UUID at a
    /// different proposal index is a new interruption. No state or budget changes.
    func isPresented(offer: TradeOffer, context: Context) -> Bool {
        guard context.completedTurns >= 0, context.proposalSequence >= -1,
              GameSetup.supportedPlayerCounts.contains(context.playerCount),
              round == context.round else { return false }
        return alreadyPresented(offer, context: context)
    }

    /// Pure: inspecting a candidate neither spends an interruption nor records
    /// a rejection. Limits include accepted and fair offers, not just bad asks.
    /// Default round capacity is capped to one slot per other occupied seat, so
    /// each opponent can have one fair interruption at three/four-player tables.
    func decision(for offer: TradeOffer, in state: GameState, context: Context) -> Decision {
        validate(context, state: state)
        guard offer.from != human, state.pendingTradeOffers.contains(offer),
              case .mainTurn(let index) = state.phase, state.players[index].id == offer.from,
              Trading.bothSidesCanHonour(offer, responder: human, state: state) else { return .notIncoming }
        if bankMatchesOrImproves(offer, in: state) { return rejection(offer, reason: .bankEquivalentOrBetter) }
        let exchange = ExchangeClass(offer: offer)
        if round == context.round, let rejectedExchange,
           exchange.isLopsided, exchange.isAtLeastAsLopsided(as: rejectedExchange) {
            return rejection(offer, reason: .rejectedExchangeClass)
        }
        if alreadyPresented(offer, context: context) { return .present }
        if completedTurns == context.completedTurns, presentations.count >= limits.perTurn {
            return rejection(offer, reason: .turnBudget)
        }
        if round == context.round, roundPresentationCount >= min(limits.perRound, context.playerCount - 1) {
            return rejection(offer, reason: .roundBudget)
        }
        return .present
    }

    /// Reserve once before showing a new interruption, persisting the candidate
    /// policy with its checkpoint. Repeat renders of that occurrence cost nothing;
    /// a later identical proposal has a different sequence and consumes a slot.
    mutating func recordPresentation(of offer: TradeOffer, in state: GameState, context: Context) {
        precondition(decision(for: offer, in: state, context: context) == .present)
        guard !alreadyPresented(offer, context: context) else { return }
        advance(to: context)
        presentations.append(Presentation(offerID: offer.id, proposalSequence: context.proposalSequence))
        roundPresentationCount += 1
    }

    /// Call only for an explicit human rejection, with its successfully applied
    /// engine step, then publish this candidate only after durable commit. Do not
    /// call for timeouts or automatic suppression: neither is a human preference.
    /// Rejections apply across proposers/resources for the rest of this round.
    mutating func recordHumanRejection(of offer: TradeOffer, committed step: GameSession.Step, context: Context) {
        precondition(step.actor == human && step.move == .respondToTrade(offerID: offer.id, accept: false))
        precondition(step.events.contains(.rejectedTrade(human, from: offer.from)))
        advance(to: context)
        let exchange = ExchangeClass(offer: offer)
        guard exchange.isLopsided else { return }
        if let previous = rejectedExchange, exchange.isAtLeastAsLopsided(as: previous) { return }
        rejectedExchange = exchange
    }

    private func validate(_ context: Context, state: GameState) {
        precondition(context.playerCount == state.players.count)
        precondition(state.players.contains { $0.id == human })
        precondition(context.completedTurns >= (completedTurns ?? 0), "stale trade context")
    }

    private func validateCounters(playerCount: Int, historyTurns: Int) throws {
        guard roundPresentationCount >= 0, roundPresentationCount >= presentations.count,
              roundPresentationCount <= min(limits.perRound, playerCount - 1),
              presentations.count <= limits.perTurn,
              (completedTurns == nil) == (round == nil) else { throw ValidationError.invalidCounters }
        guard let completedTurns, let round else {
            guard presentations.isEmpty, roundPresentationCount == 0,
                  rejectedExchange == nil else { throw ValidationError.invalidCounters }
            return
        }
        guard completedTurns >= 0, completedTurns <= historyTurns,
              round >= 0, round == completedTurns / playerCount else { throw ValidationError.invalidCounters }
    }

    private func validateStoredCounters() throws {
        guard roundPresentationCount >= 0, roundPresentationCount >= presentations.count,
              presentations.count <= limits.perTurn,
              (completedTurns == nil) == (round == nil) else { throw ValidationError.invalidCounters }
        guard let completedTurns, let round else {
            guard presentations.isEmpty, roundPresentationCount == 0,
                  rejectedExchange == nil else { throw ValidationError.invalidCounters }
            return
        }
        guard completedTurns >= 0, round >= 0,
              GameSetup.supportedPlayerCounts.contains(where: {
                  human.index < $0 && round == completedTurns / $0
                      && roundPresentationCount <= min(limits.perRound, $0 - 1)
              }) else { throw ValidationError.invalidCounters }
    }

    private func validateStoredOccurrences() throws {
        var previous = -2
        var inheritedIDs: Set<UUID> = []
        for presentation in presentations {
            if presentation.proposalSequence == -1 {
                guard previous <= -1, completedTurns == 0, inheritedIDs.insert(presentation.offerID).inserted else {
                    throw ValidationError.invalidOccurrence
                }
            } else {
                guard presentation.proposalSequence > previous,
                      presentation.proposalSequence >= (completedTurns ?? 0) else {
                    throw ValidationError.invalidOccurrence
                }
            }
            previous = presentation.proposalSequence
        }
    }

    private func validateOccurrences(in moves: [GameMove], playerCount: Int, initialOffers: [TradeOffer]) throws {
        let inherited = presentations.filter { $0.proposalSequence == -1 }
        for presentation in inherited {
            guard initialOffers.contains(where: { $0.id == presentation.offerID && $0.from != human }) else {
                throw ValidationError.invalidOccurrence
            }
        }
        guard presentations.allSatisfy({ $0.proposalSequence < moves.count }) else { throw ValidationError.invalidOccurrence }
        var turn = 0
        var nextPresentation = inherited.count
        var roundProposals = round == 0 ? initialOffers.filter { $0.from != human }.count : 0
        for (index, move) in moves.enumerated() {
            if nextPresentation < presentations.count, presentations[nextPresentation].proposalSequence == index {
                guard case .proposeTrade(let offer) = move, offer.from != human,
                      offer.id == presentations[nextPresentation].offerID,
                      turn == completedTurns else { throw ValidationError.invalidOccurrence }
                nextPresentation += 1
            }
            if case .proposeTrade(let offer) = move, offer.from != human, turn / playerCount == round {
                roundProposals += 1
            }
            if move == .endTurn { turn += 1 }
        }
        guard roundPresentationCount <= roundProposals else { throw ValidationError.invalidCounters }
    }

    private func alreadyPresented(_ offer: TradeOffer, context: Context) -> Bool {
        completedTurns == context.completedTurns && presentations.contains {
            $0.offerID == offer.id && $0.proposalSequence == context.proposalSequence
        }
    }

    private mutating func advance(to context: Context) {
        precondition(context.completedTurns >= (completedTurns ?? 0), "stale trade context")
        if round != context.round {
            roundPresentationCount = 0
            rejectedExchange = nil
            round = context.round
        }
        if completedTurns != context.completedTurns {
            presentations = []
            completedTurns = context.completedTurns
        }
    }

    private func rejection(_ offer: TradeOffer, reason: Reason) -> Decision {
        .reject(move: .respondToTrade(offerID: offer.id, accept: false), reason: reason)
    }

    /// Only a one-resource-for-another exchange admits this exact comparison.
    /// The human exports the bot's wanted resource at the HUMAN's matching rate.
    /// The bank must supply the same received quantity for no more exported cards;
    /// equal price qualifies because it avoids funding the proposing opponent.
    /// Bundles are left to the human rather than guessed at with a card ratio.
    private func bankMatchesOrImproves(_ offer: TradeOffer, in state: GameState) -> Bool {
        guard offer.give.count == 1, offer.want.count == 1,
              let exported = Resource.allCases.first(where: { offer.want[$0] != nil }),
              let received = Resource.allCases.first(where: { offer.give[$0] != nil }),
              exported != received else { return false }
        let rate = Trading.bestRate(for: exported, player: human, state: state)
        let (cost, overflow) = rate.multipliedReportingOverflow(by: offer.give[received, default: 0])
        guard !overflow, cost > 0, cost <= offer.want[exported, default: 0] else { return false }
        return Trading.bankTradeProblem(give: [exported: cost], get: offer.give, by: human, state: state) == nil
    }
}
