import Foundation

/// What an agent is shown when it is asked to move.
///
/// One type, deliberately, so that every consumer of the game - the bot that
/// ships, a self-play harness, a trainer, or a prompt for a language model -
/// is looking at the same thing. If they diverge, whatever you measure is not
/// what you play.
///
/// ## On hidden information
/// `state` is currently the full `GameState`, so an agent can see opponents'
/// hands. That is a deliberate, recorded decision to defer, not an oversight:
/// hiding it changes how strong the bots are and is worth doing on purpose
/// rather than as a side effect of this refactor. When it happens, it happens
/// *here* - by replacing `state` with a masked projection - and no consumer
/// has to change, which is the whole reason this type exists rather than
/// passing `GameState` around directly.
/// Named `GameObservation`, not `Observation`, deliberately: the shorter name
/// shadows Apple's `Observation` module, and any app type marked `@Observable`
/// that also imports this package then fails to compile with
/// "'Observable' is not a member type of struct 'CatanEngine.Observation'".

public struct GameObservation: Codable, Equatable, Sendable {
    /// The seat being asked to move.
    public let seat: PlayerID
    public let state: GameState
    /// Every move `seat` may legally make right now. Precomputed because both
    /// the caller and every policy need it, and it is the most expensive
    /// thing in the loop.
    public let legalMoves: [GameMove]

    public init(seat: PlayerID, state: GameState, legalMoves: [GameMove]) {
        self.seat = seat
        self.state = state
        self.legalMoves = legalMoves
    }
}

/// Something that can choose a move.
///
/// The one seam an alternative agent plugs into. A heuristic bot, a search, a
/// learned policy and a language model all differ only in their implementation
/// of this method.
///
/// `rng` is passed in rather than owned so that a whole game is reproducible
/// from a single seed - a policy that reaches for its own randomness makes the
/// session unmeasurable, which is what `Bot.decide(for:player:)` (the overload
/// without an rng) does and why nothing here uses it.
public protocol Policy: Sendable {
    /// Stable identifier, for evaluation records: "heuristic-v1", "random".
    var id: String { get }
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove
}

/// Drives a game forward, one move at a time, with no notion of elapsed time.
///
/// ## Why this exists
/// There used to be two loops. The app drove bots from `GameViewModel` with
/// sleeps, a re-entrancy guard, a runaway-action cap and trade resolution that
/// lived in the view model; a self-play harness called `Bot.decide` directly
/// and bypassed all of it. So the bots being measured were not the bots being
/// played, and no result from one told you anything reliable about the other.
///
/// This is the single loop both use. It contains only what is true of the game
/// regardless of who is watching. Pacing - the 600ms between bot moves, the
/// pause before a bot accepts an open offer - is presentation and stays in the
/// app, wrapped around `step()`.
public struct GameSession: Sendable {
    public private(set) var state: GameState

    /// Seats this session decides for. A seat with no policy is driven from
    /// outside (the human), and `step()` stops when it is their turn.
    public var policies: [PlayerID: any Policy]

    /// Randomness for policy tie-breaks, separate from `state.rng` so that
    /// changing how a bot breaks ties cannot shift the dice.
    public private(set) var policyRNG: RandomSource

    /// One counted view of the table per seat, maintained as moves are
    /// applied.
    ///
    /// ## Why the session owns this and not the policy
    /// A `Policy` is handed one position and asked for one move; it has no
    /// memory between calls and no sight of the events a move produced. Card
    /// counting is a fold over that event stream, so the only place it can
    /// live without giving every policy mutable state is here - the one loop
    /// every move already passes through.
    ///
    /// Each seat's ledger is folded from events **masked for that seat**, so a
    /// seat is never told the identity of a card it did not see move. That is
    /// the difference between a bot that counts cards and a bot that reads
    /// hands.
    private var ledgers: [PlayerID: PublicLedger] = [:]

    /// What `seat` may legitimately believe about every hand at the table.
    public func ledger(for seat: PlayerID) -> PublicLedger {
        ledgers[seat] ?? PublicLedger.fromPositionAlone(state, observer: seat)
    }

    /// Exact policy evaluations performed by the most recent decision or
    /// commit operation. A proposal may ask several responders before one
    /// acceptance wins; all answers matter to evaluators, not only the one
    /// eventually committed. Replaced on each operation, so app callers that
    /// ignore telemetry never accumulate a game-sized history.
    public private(set) var lastPolicyDecisions: [Decision] = []
    /// Monotonic index assigned at the policy call site. A training exporter
    /// can therefore detect omissions and duplicates instead of renumbering a
    /// partial list into something that appears complete.
    public private(set) var policyEvaluationCount = 0

    /// An out-of-turn policy response to the offer just proposed.
    ///
    /// Catan trades are live negotiations: waiting until the responder's own
    /// turn makes every bot-to-bot offer disappear when the proposer ends its
    /// turn. The response is queued here so the app and simulator execute the
    /// same next action and both can log it as an ordinary `Step`.
    private var queuedTradeResponse: Decision?

    /// A single seat may act only this many times in one `.mainTurn` before
    /// being forced to end it.
    ///
    /// A backstop, not a rule. Bots previously deadlocked re-proposing an
    /// identical trade forever; the underlying cause is fixed, but a loop that
    /// can run unbounded on a device is worth a hard stop regardless. It only
    /// bites in `.mainTurn` - every other phase resolves in one move per seat.
    public static let maxActionsPerTurn = 25

    public init(state: GameState, policies: [PlayerID: any Policy], policySeed: UInt64) {
        self.state = state
        self.policies = policies
        self.policyRNG = RandomSource(seed: policySeed)
        self.ledgers = Self.freshLedgers(for: state)
        restorePendingTradeBookkeeping()
    }

    /// Session-only progress is persisted alongside the board, not rebuilt by
    /// re-evaluating policies. In particular a queued trade answer already used
    /// randomness and must not be sampled again on resume.
    public struct Checkpoint: Codable, Equatable, Sendable {
        let version: Int
        public let state: GameState
        let policyIDs: [PlayerID: String]
        let policyRNG: RandomSource
        let policyEvaluationCount: Int
        let queuedTradeResponse: Decision?
        let currentTurnSeat: PlayerID?
        let actionsThisTurn: Int
        /// Counted card beliefs, one per seat.
        ///
        /// Optional so that a checkpoint written before ledgers existed still
        /// decodes - the synthesized decoder uses `decodeIfPresent` for an
        /// optional, and a resumed game with no stored beliefs rebuilds them
        /// from the position alone. That is a weaker belief than a counted one
        /// and never a wrong one; the alternative, silently resetting every
        /// belief on resume without saying so, is the kind of quiet difference
        /// this repository has paid for before.
        let ledgers: [PlayerID: PublicLedger]?

        /// Reject invalid wire state before nextActor indexes a seat or a
        /// decision increments a counter. This checks session invariants;
        /// it does not certify every board/rules invariant in an imported save.
        public func validate() throws {
            let occupied = Set(state.players.map(\.id))
            guard version == 1, (1...GameState.currentSchemaVersion).contains(state.schemaVersion),
                  GameSetup.supportedPlayerCounts.contains(state.players.count),
                  state.players.map({ $0.id.index }).elementsEqual(state.players.indices),
                  Set(policyIDs.keys).isSubset(of: occupied),
                  currentTurnSeat.map(occupied.contains) ?? true,
                  (0...GameSession.maxActionsPerTurn).contains(actionsThisTurn),
                  (currentTurnSeat == nil) == (actionsThisTurn == 0),
                  (0..<Int.max).contains(policyEvaluationCount) else {
                throw CheckpointError.incompatibleCheckpoint
            }
            switch state.phase {
            case .discarding(let pending):
                guard !pending.isEmpty, pending.isSubset(of: occupied) else { throw CheckpointError.incompatibleCheckpoint }
            case .gameOver(let winner):
                guard occupied.contains(winner) else { throw CheckpointError.incompatibleCheckpoint }
            default:
                guard state.phase.awaitingSeatIndex.map(state.players.indices.contains) == true else {
                    throw CheckpointError.incompatibleCheckpoint
                }
            }
            try validateQueuedResponse(occupied: occupied)
        }

        private func validateQueuedResponse(occupied: Set<PlayerID>) throws {
            guard let queued = queuedTradeResponse else { return }
            guard occupied.contains(queued.seat), policyIDs[queued.seat] != nil,
                  queued.observation.seat == queued.seat, queued.observation.state == state,
                  (0..<policyEvaluationCount).contains(queued.evaluationIndex),
                  case .respondToTrade(let offerID, _) = queued.move,
                  let offer = state.pendingTradeOffers.first(where: { $0.id == offerID }),
                  occupied.contains(offer.from), offer.from != queued.seat else {
                throw CheckpointError.incompatibleCheckpoint
            }
            var legal: [GameMove] = [.respondToTrade(offerID: offerID, accept: false)]
            if Trading.bothSidesCanHonour(offer, responder: queued.seat, state: state) {
                legal.insert(.respondToTrade(offerID: offerID, accept: true), at: 0)
            }
            guard legal == queued.observation.legalMoves, legal.contains(queued.move) else {
                throw CheckpointError.incompatibleCheckpoint
            }
        }
    }

    public enum CheckpointError: Error { case incompatibleCheckpoint }

    public var checkpoint: Checkpoint {
        Checkpoint(version: 1, state: state, policyIDs: policies.mapValues { $0.id },
                   policyRNG: policyRNG, policyEvaluationCount: policyEvaluationCount,
                   queuedTradeResponse: queuedTradeResponse,
                   currentTurnSeat: currentTurnSeat, actionsThisTurn: actionsThisTurn,
                   ledgers: ledgers)
    }

    /// Callers supply the same policy implementations/configurations identified
    /// by the saved IDs. Executable policies are not serialized into save files.
    /// Last-operation telemetry is transient; queued-decision telemetry is not.
    public init(checkpoint: Checkpoint, policies: [PlayerID: any Policy]) throws {
        try checkpoint.validate()
        guard checkpoint.policyIDs == policies.mapValues({ $0.id }) else {
            throw CheckpointError.incompatibleCheckpoint
        }
        self.state = checkpoint.state
        self.policies = policies
        self.policyRNG = checkpoint.policyRNG
        self.policyEvaluationCount = checkpoint.policyEvaluationCount
        self.queuedTradeResponse = checkpoint.queuedTradeResponse
        self.currentTurnSeat = checkpoint.currentTurnSeat
        self.actionsThisTurn = checkpoint.actionsThisTurn
        self.ledgers = checkpoint.ledgers ?? Self.freshLedgers(for: checkpoint.state)
    }

    /// A position-only ledger for every seat, with no counted history behind it.
    static func freshLedgers(for state: GameState) -> [PlayerID: PublicLedger] {
        var ledgers: [PlayerID: PublicLedger] = [:]
        for player in state.players {
            ledgers[player.id] = PublicLedger.fromPositionAlone(state, observer: player.id)
        }
        return ledgers
    }

    /// The seat and vertex of a second-placement settlement, if this move was
    /// one. The vertex is the settlement the seat did not have before, which
    /// only a caller holding both states can identify.
    private func initialGrant(
        in events: [GameEvent],
        stateBefore: GameState
    ) -> (seat: PlayerID, vertex: VertexID)? {
        guard case .setupBackward = stateBefore.phase else { return nil }
        for event in events {
            guard case .placedInitialSettlement(let seat) = event,
                  let before = stateBefore.players.first(where: { $0.id == seat }),
                  let after = state.players.first(where: { $0.id == seat }),
                  let vertex = after.settlements.subtracting(before.settlements).sorted().first
            else { continue }
            return (seat, vertex)
        }
        return nil
    }

    /// Folds one applied move's events into every seat's ledger.
    ///
    /// Called from the two places a move can be applied, with the state as it
    /// was *before* the move: a roll's payout depends on where the robber was
    /// and what the bank held at the moment it was rolled.
    private mutating func recordInLedgers(_ events: [GameEvent], stateBefore: GameState) {
        let grant = initialGrant(in: events, stateBefore: stateBefore)
        for seat in ledgers.keys.sorted() {
            guard var ledger = ledgers[seat] else { continue }
            for event in events {
                ledger.apply(event.masked(for: seat), stateBefore: stateBefore)
            }
            if let grant {
                ledger.creditInitialGrant(to: grant.seat, at: grant.vertex, board: state.board)
            }
            ledger.reconcileHandSizes(from: state)
            ledger.reconcileObserverHand(from: state)
            ledgers[seat] = ledger
        }
    }

    /// One applied move.
    public struct Step: Sendable {
        public let actor: PlayerID
        public let move: GameMove
        public let events: [GameEvent]
        /// Buyer-scoped information that must never enter the public event
        /// stream or exported move history.
        public let privateEvents: [PrivateGameEvent]
    }

    /// One policy choice together with the exact action mask it received.
    /// Evaluation consumers need the mask to distinguish preference from
    /// opportunity; ordinary app callers can keep using `decideNext()`.
    public struct Decision: Codable, Equatable, Sendable {
        public let evaluationIndex: Int
        public let seat: PlayerID
        public let move: GameMove
        public let observation: GameObservation
    }

    /// Who acts next, or why nobody can.
    ///
    /// A plain enum rather than `Result`: neither non-seat case is an error -
    /// "the human's turn" and "the game is over" are both ordinary outcomes,
    /// and `Result` would have required pretending otherwise.
    public enum NextActor: Sendable, Equatable {
        case seat(PlayerID)
        case gameOver(winner: PlayerID)
        /// A seat this session does not decide for - the human's turn.
        case awaitingExternalSeat(PlayerID)
    }

    public func nextActor() -> NextActor {
        if let queuedTradeResponse { return .seat(queuedTradeResponse.seat) }
        let seat: PlayerID
        switch state.phase {
        case .setupForward(let index), .setupBackward(let index),
             .rollDice(let index), .mainTurn(let index), .movingRobber(let index):
            seat = state.players[index].id
        case .discarding(let pending):
            // No single seat owns this phase - anyone still pending may go.
            // Sorted so the choice does not depend on `Set` iteration order,
            // which Swift seeds per process.
            let ordered = pending.sorted()
            // An empty pending set means nobody owes a discard, so the phase
            // should already have ended - both transitions into `.discarding`
            // guard against it. This used to return `.awaitingExternalSeat` for
            // seat 0, which is the engine guessing that seat 0 is the human:
            // the fifth copy of an assumption that has produced a real bug
            // every previous time (the log called a bot "You" in three games
            // out of four). The engine has no way to know where the human
            // sits, so it must not answer as though it did.
            guard let first = ordered.first else {
                preconditionFailure("reached .discarding with nobody pending; the phase should have ended")
            }
            // Prefer a seat this session drives, so a human who owes a discard
            // does not block the bots who also owe one.
            seat = ordered.first(where: { policies[$0] != nil }) ?? first
        case .gameOver(let winner):
            return .gameOver(winner: winner)
        }
        guard policies[seat] != nil else { return .awaitingExternalSeat(seat) }
        return .seat(seat)
    }

    /// Asks the policy whose turn it is for a move, without applying it.
    ///
    /// Split from `commit` so a caller can do something between the decision
    /// and the move landing - the app holds a bot back for a couple of seconds
    /// before it accepts an offer the human is still reading, which it cannot
    /// decide to do until it knows what the bot chose. **Advances `policyRNG`,
    /// so a decision taken must be committed**, or the sequence diverges from
    /// a replay of the same seed.
    public mutating func decideNext() -> (seat: PlayerID, move: GameMove)? {
        guard let decision = decideNextDetailed() else { return nil }
        return (decision.seat, decision.move)
    }

    /// Rich form of `decideNext()` for evaluators and trainers.
    /// Advances policy RNG exactly once, like the compact API.
    public mutating func decideNextDetailed() -> Decision? {
        lastPolicyDecisions = []
        if let queuedTradeResponse {
            lastPolicyDecisions = [queuedTradeResponse]
            return queuedTradeResponse
        }
        guard case .seat(let seat) = nextActor(), let policy = policies[seat] else { return nil }

        // Seat-scoped: the unscoped list is a union in `.discarding`.
        let legal = RulesEngine.legalMoves(for: state, seat: seat).filter {
            guard case .proposeTrade = $0 else { return true }
            let alreadyPendingFromSeat = state.pendingTradeOffers.contains { $0.from == seat }
            let attemptsUsed = state.declinedTradeOffersThisTurn[seat]?.count ?? 0
            return !alreadyPendingFromSeat && attemptsUsed < RulesEngine.maxTradeProposalsPerTurn
        }
        let observation = GameObservation(seat: seat, state: state, legalMoves: legal)
        let chosen = decide(with: policy, observation: observation, seat: seat)
        precondition(
            legal.contains(chosen),
            "policy \(policy.id) returned a move outside its action mask"
        )

        if actionsThisTurn >= Self.maxActionsPerTurn, case .mainTurn = state.phase {
            let decision = recordedDecision(seat: seat, move: .endTurn, observation: observation)
            lastPolicyDecisions = [decision]
            return decision
        }
        let decision = recordedDecision(seat: seat, move: chosen, observation: observation)
        lastPolicyDecisions = [decision]
        return decision
    }

    /// Applies a move a policy chose.
    public mutating func commit(seat: PlayerID, move: GameMove) throws -> Step {
        lastPolicyDecisions = []
        let stateBefore = state
        let result = try RulesEngine.applyReportingPrivateEvents(move, by: seat, to: &state)
        recordInLedgers(result.events, stateBefore: stateBefore)
        if queuedTradeResponse?.seat == seat, queuedTradeResponse?.move == move {
            queuedTradeResponse = nil
        }
        recordAction(by: seat, move: move)
        if case .proposeTrade(let offer) = move {
            queueAutomatedResponse(to: offer)
        }
        return Step(actor: seat, move: move, events: result.events, privateEvents: result.privateEvents)
    }

    /// Decide and apply in one go. Returns `nil` when the game is over or it
    /// is an external seat's turn - ask `nextActor()` for which.
    public mutating func step() throws -> Step? {
        guard let (seat, move) = decideNext() else { return nil }
        return try commit(seat: seat, move: move)
    }

    /// Applies a move decided outside this session - the human's.
    ///
    /// Routed through the session rather than applied to `state` directly so
    /// that there is exactly one path by which the game advances. The turn
    /// bookkeeping the runaway backstop depends on is only correct if every
    /// move passes through here.
    @discardableResult
    public mutating func applyExternal(_ move: GameMove, by seat: PlayerID) throws -> Step {
        lastPolicyDecisions = []
        let stateBefore = state
        let result = try RulesEngine.applyReportingPrivateEvents(move, by: seat, to: &state)
        recordInLedgers(result.events, stateBefore: stateBefore)
        recordAction(by: seat, move: move)
        return Step(actor: seat, move: move, events: result.events, privateEvents: result.privateEvents)
    }

    /// Replaces the position wholesale - loading a save, or a QA fixture.
    /// Resets the turn bookkeeping, which describes the game being replaced.
    public mutating func replace(state newState: GameState) {
        lastPolicyDecisions = []
        state = newState
        // A wholesale replacement is a different game; counted beliefs about
        // the old one would be worse than none.
        ledgers = Self.freshLedgers(for: newState)
        currentTurnSeat = nil
        actionsThisTurn = 0
        policyEvaluationCount = 0
        restorePendingTradeBookkeeping()
    }

    /// Runs until the game ends or an external seat has to act.
    ///
    /// `limit` is a guard against a rules bug producing an endless game, not a
    /// normal stopping condition - a real game is a few hundred moves.
    @discardableResult
    public mutating func run(limit: Int = 10_000) throws -> NextActor {
        for _ in 0..<limit {
            let next = nextActor()
            guard case .seat = next else { return next }
            guard try step() != nil else { break }
        }
        return nextActor()
    }

    // MARK: - Runaway backstop

    private var currentTurnSeat: PlayerID?
    private var actionsThisTurn = 0

    private mutating func recordAction(by seat: PlayerID, move: GameMove) {
        if case .respondToTrade = move { return }
        if seat == currentTurnSeat, case .endTurn = move {
            currentTurnSeat = nil
            actionsThisTurn = 0
        } else if seat == currentTurnSeat {
            actionsThisTurn += 1
        } else {
            currentTurnSeat = seat
            actionsThisTurn = 1
        }
    }

    // MARK: - Live policy trades

    /// Reconstructs the session-only half of a negotiation after loading or
    /// replacing state. The offer itself is durable in `GameState`; the queued
    /// responder and one-proposal guard are derived from it so force-quitting
    /// between proposal and response cannot change how the turn continues.
    private mutating func restorePendingTradeBookkeeping() {
        queuedTradeResponse = nil
        guard let offer = state.pendingTradeOffers.first else { return }
        queueAutomatedResponse(to: offer)
    }

    private mutating func queueAutomatedResponse(to offer: TradeOffer) {
        let externalCanAnswer = state.players.map(\.id).contains {
            policies[$0] == nil && $0 != offer.from
                && Trading.bothSidesCanHonour(offer, responder: $0, state: state)
        }
        guard !externalCanAnswer else { return }

        let responders = state.players.map(\.id).sorted().filter {
            $0 != offer.from && policies[$0] != nil
        }
        var firstRejection: Decision?
        for seat in responders {
            guard let decision = tradeDecision(for: seat, offer: offer) else { continue }
            if firstRejection == nil { firstRejection = decision }
            if case .respondToTrade(_, true) = decision.move {
                queuedTradeResponse = decision
                removeQueuedDecisionFromCurrentTelemetry()
                return
            }
        }
        if let firstRejection {
            queuedTradeResponse = firstRejection
            removeQueuedDecisionFromCurrentTelemetry()
        }
    }

    private mutating func tradeDecision(for seat: PlayerID, offer: TradeOffer) -> Decision? {
        guard let policy = policies[seat] else { return nil }
        let observation = tradeObservation(for: seat, offer: offer)
        let chosen = decide(with: policy, observation: observation, seat: seat)
        precondition(observation.legalMoves.contains(chosen), "policy \(policy.id) returned a non-response to an open trade")
        let decision = recordedDecision(seat: seat, move: chosen, observation: observation)
        lastPolicyDecisions.append(decision)
        return decision
    }

    private mutating func recordedDecision(
        seat: PlayerID,
        move: GameMove,
        observation: GameObservation
    ) -> Decision {
        defer { policyEvaluationCount += 1 }
        return Decision(
            evaluationIndex: policyEvaluationCount,
            seat: seat,
            move: move,
            observation: observation
        )
    }

    private func tradeObservation(for seat: PlayerID, offer: TradeOffer) -> GameObservation {
        let reject = GameMove.respondToTrade(offerID: offer.id, accept: false)
        var legal = [reject]
        if Trading.bothSidesCanHonour(offer, responder: seat, state: state) {
            legal.insert(.respondToTrade(offerID: offer.id, accept: true), at: 0)
        }
        return GameObservation(seat: seat, state: state, legalMoves: legal)
    }

    /// The queued reply is reported when it becomes the next decision. The
    /// other replies were evaluated but discarded, so they are reported by
    /// the proposal commit. Splitting them prevents double-counting while
    /// still preserving a queued reply reconstructed from a save.
    private mutating func removeQueuedDecisionFromCurrentTelemetry() {
        guard let queuedTradeResponse else { return }
        lastPolicyDecisions.removeAll {
            $0.seat == queuedTradeResponse.seat && $0.move == queuedTradeResponse.move
        }
    }
}

/// A policy that wants the counted view of the table as well as the position.
///
/// ## Why this is a second protocol and not a field on `GameObservation`
/// Adding the ledger to the observation looked simpler and is not. The
/// observation is `Codable` and `Equatable`, it is stored inside a session
/// checkpoint's queued trade response, and `Checkpoint.validate()` asserts
/// that the stored observation's state equals the session's. A belief folded
/// from a different event history would fail that comparison and reject a
/// perfectly good save. It is also serialised into every exported training
/// example, where it is not wanted.
///
/// So the ledger travels beside the observation instead. A policy that does
/// not adopt this protocol is called exactly as before and cannot tell the
/// difference.
public protocol LedgerAwarePolicy: Policy {
    func decide(_ observation: GameObservation, ledger: PublicLedger, rng: inout RandomSource) -> GameMove
}

extension GameSession {
    /// Calls `policy`, handing it the counted view if it asked for one.
    mutating func decide(with policy: any Policy, observation: GameObservation, seat: PlayerID) -> GameMove {
        if let aware = policy as? any LedgerAwarePolicy {
            return aware.decide(observation, ledger: ledger(for: seat), rng: &policyRNG)
        }
        return policy.decide(observation, rng: &policyRNG)
    }
}
