import Foundation
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

    /// A bot that *would* accept the human's most recent proposal, held here
    /// instead of being applied immediately - `TradePopupView` shows this as
    /// a "Bot X will accept - Confirm?" banner and only actually executes
    /// the swap once the human taps through via `confirmPendingTrade()`
    /// (or backs out via `declinePendingTrade()`). `nil` whenever there's
    /// nothing awaiting confirmation - either no proposal is in flight, or
    /// the most recent one found no willing bot (see `resolveHumanProposedTrade`,
    /// which resolves that case immediately since there's nothing to
    /// confirm).
    public struct PendingTradeConfirmation {
        public let offerID: UUID
        public let acceptedBy: PlayerID
        public let decisions: [(bot: PlayerID, accepted: Bool)]
    }
    public private(set) var pendingTradeConfirmation: PendingTradeConfirmation?

    /// The `GameLogStore` file this session's moves are being appended to,
    /// and when this session started tracking the current game - both
    /// (re)set alongside `state` in `init()`/`startNewGame(randomizedBoard:)`.
    /// A game resumed from `GameStore` after an app relaunch starts a *new*
    /// log segment and a fresh duration clock rather than continuing the
    /// pre-relaunch one - see the design doc's Non-goals for why that's an
    /// accepted simplification rather than a bug.
    private var currentGameLogID: UUID
    private var gameStartedAt: Date

    public init() {
        let initialState: GameState
        if let saved = GameStore.shared.load() {
            initialState = saved
            // A resumed game keeps whichever civilizations it was dealt,
            // read back from disk rather than re-randomized - falls back to
            // a fresh draw if the assignment file is missing/corrupt (e.g.
            // a save from before this file existed) so the board still has
            // *some* consistent lineup instead of `CivilizationAssignment`'s
            // bare default.
            CivilizationAssignment.current = CivilizationAssignmentStore.shared.load()
                ?? Self.drawAssignment(from: CivilizationSettingsStore.shared.load())
        } else {
            initialState = GameSetup.newGame(board: BoardGenerator.standard())
        }
        // `@Observable` requires every stored property assigned before
        // `self` (including `self.state`) can be read - `GameLogStore`
        // reads `initialState` (the local), never `self.state`, to stay
        // fully assign-before-read through this initializer.
        state = initialState
        currentGameLogID = GameLogStore.shared.startNewGame(initialState: initialState)
        gameStartedAt = Date()
    }

    /// Starts a fresh game, discarding whatever `state` currently holds.
    public func startNewGame(randomizedBoard: Bool) {
        let board = randomizedBoard
            ? BoardGenerator.randomized(seed: UInt64.random(in: .min ... .max))
            : BoardGenerator.standard()
        state = GameSetup.newGame(board: board)
        currentGameLogID = GameLogStore.shared.startNewGame(initialState: state)
        gameStartedAt = Date()

        let assignment = Self.drawAssignment(from: CivilizationSettingsStore.shared.load())
        CivilizationAssignment.current = assignment
        try? CivilizationAssignmentStore.shared.save(assignment)

        try? GameStore.shared.save(state)
    }

    /// Applies `move` through `RulesEngine` exactly like a direct call
    /// would, plus logs it to `GameLogStore` and - the first time `state`
    /// transitions into `.gameOver` - finalizes the log and records the
    /// outcome into `GameStatsStore`. Every `RulesEngine.apply` call in this
    /// file routes through here instead of calling it directly, so no path
    /// (human move, bot move, or an auto-resolved trade response) can skip
    /// logging.
    private func applyLogged(_ move: GameMove, by player: PlayerID) throws {
        let wasGameOver: Bool
        if case .gameOver = state.phase { wasGameOver = true } else { wasGameOver = false }

        try RulesEngine.apply(move, by: player, to: &state)
        GameLogStore.shared.appendMove(gameID: currentGameLogID, player: player, move: move)

        if !wasGameOver, case .gameOver(let winner) = state.phase {
            GameLogStore.shared.finalizeGame(gameID: currentGameLogID, winner: winner)
            GameStatsStore.shared.recordGameEnd(
                won: winner == humanPlayer,
                finalVP: state.victoryPoints(for: humanPlayer),
                duration: Date().timeIntervalSince(gameStartedAt)
            )
        }
    }

    /// Seat 0 = the player's chosen civilization; seats 1-3 = 3 distinct
    /// random draws from their included bot roster (falling back to every
    /// other civilization if, somehow, fewer than 3 are included - e.g. a
    /// corrupt settings value that skipped `SettingsView`'s minimum-3
    /// enforcement).
    private static func drawAssignment(from settings: CivilizationSettings) -> [Civilization] {
        var botPool = settings.includedBotCivilizations.subtracting([settings.yourCivilization])
        if botPool.count < CivilizationSettings.minimumIncludedBots {
            botPool = Set(Civilization.allCases).subtracting([settings.yourCivilization])
        }
        let bots = Array(botPool).shuffled().prefix(3)
        return [settings.yourCivilization] + bots
    }

    /// Applies a human move, persists the result, and lets any subsequent
    /// bot turns run. A save failure here is swallowed the same way
    /// `runBotTurnIfNeeded()` swallows one: losing the on-disk save is not
    /// worth surfacing as if the move itself failed (the move already
    /// succeeded against `state`, which is what the caller/UI cares about),
    /// and only `RulesEngine.apply`'s own errors indicate the human's move
    /// itself was rejected.
    public func apply(_ move: GameMove) throws {
        try applyLogged(move, by: humanPlayer)
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
    /// right here.
    ///
    /// A willing bot's accept is *not* applied yet, though - it's held in
    /// `pendingTradeConfirmation` for the human to actually go through with
    /// via `confirmPendingTrade()` (or back out of via
    /// `declinePendingTrade()`), rather than the swap just happening the
    /// instant some bot says yes with no chance to reconsider. If nobody
    /// would accept, there's nothing to confirm, so that case still
    /// resolves immediately - the offer is withdrawn right here (a bot's
    /// `TradeHeuristics.evaluate` answer won't change on its own without
    /// some other state change, so leaving it pending indefinitely would
    /// just be a silent dead offer).
    private func resolveHumanProposedTrade(_ offer: TradeOffer) {
        var decisions: [(bot: PlayerID, accepted: Bool)] = []
        var acceptedBy: PlayerID?
        for botIndex in 1..<state.players.count {
            let bot = PlayerID(index: botIndex)
            // `TradeHeuristics.evaluate` only judges whether the offer is a
            // *good deal* for the bot - it has no idea whether the bot
            // actually holds enough of `offer.want` to go through with it,
            // so a bot could "accept" cards it doesn't have. Confirming
            // that (correctly) then failed inside `Trading.respond`'s own
            // affordability check, but by then the pending-confirmation
            // banner had already told the human this bot would accept -
            // intermittent (only bit when the bot happened to be short on
            // whatever was asked for), and looked like the trade just
            // silently didn't happen. Checking affordability here, before
            // ever offering the bot as a candidate, keeps `acceptedBy`
            // truthful to what `confirmPendingTrade()` can actually deliver.
            guard let botPlayer = state.players.first(where: { $0.id == bot }),
                  offer.want.allSatisfy({ resource, amount in (botPlayer.resources[resource] ?? 0) >= amount }) else {
                decisions.append((bot, false))
                continue
            }
            let accepts = TradeHeuristics.evaluate(offer: offer, receiver: bot, state: state, personality: personality(for: bot))
            decisions.append((bot, accepts))
            if accepts, acceptedBy == nil {
                acceptedBy = bot
            }
        }

        if let acceptedBy {
            pendingTradeConfirmation = PendingTradeConfirmation(offerID: offer.id, acceptedBy: acceptedBy, decisions: decisions)
            lastTradeOutcome = nil
        } else {
            pendingTradeConfirmation = nil
            if state.players.count > 1 {
                try? applyLogged(.respondToTrade(offerID: offer.id, accept: false), by: PlayerID(index: 1))
            }
            lastTradeOutcome = TradeOutcome(decisions: decisions, acceptedBy: nil)
        }
    }

    /// Why `confirmPendingTrade()` didn't go through, when it didn't -
    /// `.succeeded` is the only case where the cards actually moved.
    /// Distinguishing these matters because `try?` swallowing
    /// `Trading.respond`'s failure used to make a failed confirm look
    /// identical to a successful one from the UI's perspective: tapping
    /// "Confirm Trade" would just silently do nothing, no error, no
    /// changed cards, no indication why.
    public enum TradeConfirmationResult {
        case succeeded
        /// The offer itself is gone - e.g. left pending across a full turn
        /// cycle, during which the accepting bot's own legal moves could
        /// include responding to it directly some other way.
        case offerNoLongerAvailable
        /// The offer's still there, but either side has since spent what
        /// made it work - most likely the human building something with
        /// the very cards they'd offered, in the gap between proposing and
        /// confirming.
        case resourcesNoLongerAvailable
    }

    /// Goes through with a trade a bot said it would accept - see
    /// `pendingTradeConfirmation`. Returns `.succeeded` if there was
    /// nothing pending at all too (e.g. called twice, or after
    /// `declinePendingTrade()` already cleared it) - only a genuine
    /// attempt that didn't move any cards reports a failure reason.
    @discardableResult
    public func confirmPendingTrade() -> TradeConfirmationResult {
        guard let pending = pendingTradeConfirmation else { return .succeeded }
        pendingTradeConfirmation = nil

        guard state.pendingTradeOffers.contains(where: { $0.id == pending.offerID }) else {
            lastTradeOutcome = nil
            return .offerNoLongerAvailable
        }
        do {
            try applyLogged(.respondToTrade(offerID: pending.offerID, accept: true), by: pending.acceptedBy)
        } catch {
            // Withdraw the now-stuck offer on the willing bot's behalf
            // rather than leaving it pending forever with nothing left to
            // confirm it with - same "reject" applied `declinePendingTrade`
            // uses.
            try? applyLogged(.respondToTrade(offerID: pending.offerID, accept: false), by: pending.acceptedBy)
            lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: nil)
            try? GameStore.shared.save(state)
            return .resourcesNoLongerAvailable
        }
        lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: pending.acceptedBy)
        try? GameStore.shared.save(state)
        return .succeeded
    }

    /// Backs out of a trade a bot would have accepted, without executing
    /// it - withdraws the offer the same way a bot's own reject does, just
    /// applied on the willing bot's behalf since they're the one whose
    /// legal `.respondToTrade(accept: false)` actually removes it from
    /// `pendingTradeOffers`. See `confirmPendingTrade` for why the offer's
    /// continued presence is re-checked rather than assumed.
    public func declinePendingTrade() {
        guard let pending = pendingTradeConfirmation else { return }
        pendingTradeConfirmation = nil
        guard state.pendingTradeOffers.contains(where: { $0.id == pending.offerID }) else { return }
        try? applyLogged(.respondToTrade(offerID: pending.offerID, accept: false), by: pending.acceptedBy)
        lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: nil)
        try? GameStore.shared.save(state)
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
            try? applyLogged(move, by: botPlayer)
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
