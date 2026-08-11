import Observation
import CatanEngine
import CatanAI

/// Drives a single local game: owns the authoritative `GameState`, applies
/// the human's moves through `RulesEngine`, and runs bot turns (via
/// `CatanAI.Bot`) until control returns to the human or the game ends.
/// Persists to `GameStore` after every applied move so the game can resume
/// across app launches.
@MainActor
@Observable
public final class GameViewModel {
    public private(set) var state: GameState
    public let humanPlayer = PlayerID(index: 0)
    public private(set) var isBotThinking: Bool = false

    /// What happened to the most recent trade the human proposed - `nil`
    /// until the first one. `TradePopupView` reads this right after calling
    /// `apply(.proposeTrade(...))` to show the human whether anyone
    /// actually took the offer (and what *every* bot individually decided,
    /// not just whoever ended up taking it), since a bot's accept/reject
    /// otherwise happens silently.
    public struct TradeOutcome: Equatable {
        /// Every bot's individual accept/reject answer, in seat order.
        public let decisions: [(bot: PlayerID, accepted: Bool)]
        public let acceptedBy: PlayerID?

        public static func == (lhs: TradeOutcome, rhs: TradeOutcome) -> Bool {
            lhs.acceptedBy == rhs.acceptedBy
                && lhs.decisions.map(\.bot) == rhs.decisions.map(\.bot)
                && lhs.decisions.map(\.accepted) == rhs.decisions.map(\.accepted)
        }
    }
    public private(set) var lastTradeOutcome: TradeOutcome?

    public init() {
        if let saved = GameStore.shared.load() {
            state = saved
        } else {
            state = GameSetup.newGame(board: BoardGenerator.standard())
        }
    }

    /// Starts a fresh game, discarding whatever `state` currently holds.
    public func startNewGame(randomizedBoard: Bool) {
        let board = randomizedBoard
            ? BoardGenerator.randomized(seed: UInt64.random(in: .min ... .max))
            : BoardGenerator.standard()
        state = GameSetup.newGame(board: board)
        try? GameStore.shared.save(state)
    }

    /// Applies a human move, persists the result, and lets any subsequent
    /// bot turns run. A save failure here is swallowed the same way
    /// `runBotTurnIfNeeded()` swallows one: losing the on-disk save is not
    /// worth surfacing as if the move itself failed (the move already
    /// succeeded against `state`, which is what the caller/UI cares about),
    /// and only `RulesEngine.apply`'s own errors indicate the human's move
    /// itself was rejected.
    public func apply(_ move: GameMove) throws {
        try RulesEngine.apply(move, by: humanPlayer, to: &state)
        if case .proposeTrade(let offer) = move, offer.from == humanPlayer {
            resolveHumanProposedTrade(offer)
        }
        try? GameStore.shared.save(state)
        Task { await runBotTurnIfNeeded() }
    }

    /// Bots only ever get to accept/reject a pending offer as part of their
    /// *own* `mainTurn` (see `RulesEngine.legalMoves`'s `.respondToTrade`
    /// generation) - fine for a trade proposed *during* another bot's turn,
    /// since the bot loop cycles through every seat every turn anyway, but
    /// an offer the human proposes on their own turn would otherwise just
    /// sit in `pendingTradeOffers` doing nothing until the human ends their
    /// turn (and even then, `Bot.decide` picks one move at a time, so
    /// responding to it isn't guaranteed to happen before `endTurn`). Real
    /// Catan trades resolve live, so evaluate every bot against the offer
    /// right here: the first bot that would accept does, immediately;
    /// otherwise the offer is withdrawn (a bot's `TradeHeuristics.evaluate`
    /// answer won't change on its own without some other state change, so
    /// leaving it pending indefinitely would just be a silent dead offer).
    private func resolveHumanProposedTrade(_ offer: TradeOffer) {
        var decisions: [(bot: PlayerID, accepted: Bool)] = []
        var acceptedBy: PlayerID?
        for botIndex in 1..<state.players.count {
            let bot = PlayerID(index: botIndex)
            let accepts = TradeHeuristics.evaluate(offer: offer, receiver: bot, state: state, personality: personality(for: bot))
            decisions.append((bot, accepts))
            if accepts, acceptedBy == nil {
                acceptedBy = bot
            }
        }

        if let acceptedBy {
            try? RulesEngine.apply(.respondToTrade(offerID: offer.id, accept: true), by: acceptedBy, to: &state)
        } else if state.players.count > 1 {
            try? RulesEngine.apply(.respondToTrade(offerID: offer.id, accept: false), by: PlayerID(index: 1), to: &state)
        }
        lastTradeOutcome = TradeOutcome(decisions: decisions, acceptedBy: acceptedBy)
    }

    /// Runs bot turns in a loop for as long as the active player (or, during
    /// `.discarding`, the next pending bot) isn't the human and the game
    /// hasn't ended, pausing briefly before each move so bot play reads as
    /// "thinking" rather than instant.
    ///
    /// `sameBotActionCap` guards against a bot never producing `.endTurn`:
    /// manual verification (see task-12-report.md) found `Bot.decide` could
    /// keep proposing the same trade offer forever once it had a resource
    /// surplus but no affordable build. Task 16 fixed the root cause in
    /// `CatanAI` (`TradeHeuristics.proposeTrades` now skips proposing an
    /// offer that's functionally identical to one of the player's own
    /// offers already sitting in `pendingTradeOffers`, and `Bot
    /// .decideMainTurn` actively rejects a pending offer it doesn't want
    /// once nothing more valuable is available, so unwanted offers don't
    /// linger forever either) - `Bot.decide` now genuinely converges on
    /// `.endTurn` on its own in this situation. This cap stays as a
    /// defensive backstop in case some other, not-yet-seen path through
    /// `Bot.decide` fails to converge; once the same bot has acted this
    /// many times in a row without the active player changing, force
    /// `.endTurn` for it instead of trusting `Bot.decide` again.
    /// `isProcessingBotTurns` makes this method non-reentrant. Found during
    /// Task 16 simulator verification: `apply(_:)` spawns a fresh
    /// `Task { await runBotTurnIfNeeded() }` after *every* human move -
    /// including a human's own `.discard` response while other bots are
    /// still resolving theirs from the same 7-roll (`.discarding` can have
    /// several players pending at once, human included). That let two
    /// invocations of this loop run concurrently against the same shared
    /// `state`: one captures `botPlayer` from `nextBotPlayer()`, sleeps
    /// 600ms, and by the time it wakes and calls `bot.decide(for: state,
    /// player: botPlayer)`, the *other* invocation may have already
    /// resolved that same player's pending action (e.g. their discard) -
    /// `Bot.decide`'s `.discarding` branch doesn't re-check membership in
    /// `pending` before deciding, so it would recompute against
    /// `RulesEngine.legalMoves(for:)`'s now-empty set of moves for that
    /// player and crash with `Bot.decideDiscard`'s "no legal discard
    /// combination found" `preconditionFailure` - reproduced via a
    /// disposable headless harness matching the exact crash log verbatim
    /// (see task-16-report.md). A second call arriving while a loop is
    /// already in flight is a safe no-op: the in-flight loop re-derives
    /// `nextBotPlayer()` fresh every iteration, so it naturally picks up
    /// whatever new bot work the human's move created without needing a
    /// second concurrent copy of this loop.
    private var isProcessingBotTurns = false

    public func runBotTurnIfNeeded() async {
        guard !isProcessingBotTurns else { return }
        isProcessingBotTurns = true
        defer { isProcessingBotTurns = false }

        let sameBotActionCap = 25
        var currentBot: PlayerID?
        var actionsForCurrentBot = 0

        while let botPlayer = nextBotPlayer() {
            isBotThinking = true
            try? await Task.sleep(for: .milliseconds(600))

            if botPlayer == currentBot {
                actionsForCurrentBot += 1
            } else {
                currentBot = botPlayer
                actionsForCurrentBot = 1
            }

            // Only `.mainTurn` allows an unbounded number of actions before
            // the phase moves on (build, trade, play dev cards, repeat) -
            // `.movingRobber`/`.discarding` each resolve in a single move
            // per player, so the cap only ever needs to bite here.
            let move: GameMove
            if actionsForCurrentBot > sameBotActionCap, case .mainTurn = state.phase {
                move = .endTurn
            } else {
                let bot = Bot(personality: personality(for: botPlayer))
                move = bot.decide(for: state, player: botPlayer)
            }
            try? RulesEngine.apply(move, by: botPlayer, to: &state)
            try? GameStore.shared.save(state)
        }
        isBotThinking = false
    }

    /// The bot that should act next, or `nil` if it's the human's turn or
    /// the game is over. `.discarding` has no single active player, so this
    /// picks any one bot still in `pending`; it's re-derived each loop
    /// iteration so it naturally advances to the next pending bot (or to
    /// `nil` once only the human remains).
    private func nextBotPlayer() -> PlayerID? {
        switch state.phase {
        case .setupForward(let playerIndex),
             .setupBackward(let playerIndex),
             .rollDice(let playerIndex),
             .mainTurn(let playerIndex),
             .movingRobber(let playerIndex):
            let player = PlayerID(index: playerIndex)
            return player == humanPlayer ? nil : player
        case .discarding(let pending):
            return pending.first { $0 != humanPlayer }
        case .gameOver:
            return nil
        }
    }

    private func personality(for player: PlayerID) -> BotPersonality {
        switch player.index {
        case 1: return .balanced
        case 2: return .aggressive
        case 3: return .cautious
        default: return .balanced
        }
    }
}
