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
public struct GameObservation: Sendable {
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
    }

    /// One applied move.
    public struct Step: Sendable {
        public let actor: PlayerID
        public let move: GameMove
        public let events: [GameEvent]
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
        guard case .seat(let seat) = nextActor(), let policy = policies[seat] else { return nil }

        // Seat-scoped: the unscoped list is a union in `.discarding`.
        let legal = RulesEngine.legalMoves(for: state, seat: seat)
        let observation = GameObservation(seat: seat, state: state, legalMoves: legal)
        let chosen = policy.decide(observation, rng: &policyRNG)

        if actionsThisTurn >= Self.maxActionsPerTurn, case .mainTurn = state.phase {
            return (seat, .endTurn)
        }
        return (seat, chosen)
    }

    /// Applies a move a policy chose.
    public mutating func commit(seat: PlayerID, move: GameMove) throws -> Step {
        let events = try RulesEngine.apply(move, by: seat, to: &state)
        recordAction(by: seat, move: move)
        return Step(actor: seat, move: move, events: events)
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
        let events = try RulesEngine.apply(move, by: seat, to: &state)
        recordAction(by: seat, move: move)
        return Step(actor: seat, move: move, events: events)
    }

    /// Replaces the position wholesale - loading a save, or a QA fixture.
    /// Resets the turn bookkeeping, which describes the game being replaced.
    public mutating func replace(state newState: GameState) {
        state = newState
        currentTurnSeat = nil
        actionsThisTurn = 0
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
}
