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
    /// The one loop. Bots are decided by policies inside this session, and
    /// the human's own moves go through `applyExternal`, so the app and any
    /// headless harness advance the game through identical code. They used to
    /// be two loops: this one had sleeps, a re-entrancy guard, an action cap
    /// and its own trade resolution, none of which a harness ever executed -
    /// so the bots being measured were not the bots being played.
    ///
    /// Pacing stays out here. `GameSession` has no notion of elapsed time.
    private var session: GameSession

    public var state: GameState { session.state }
    /// Which seat the human occupies this game - always index 0 unless
    /// "Randomize Seat" was on when `startNewGame` was called. Persisted via
    /// `HumanSeatStore` so a resumed game keeps the same seat.
    public private(set) var humanPlayer: PlayerID

    /// What happened to the most recent trade the human proposed - `nil`
    /// until the first one. `TradePopupView` reads this right after calling
    /// `apply(.proposeTrade(...))` to show the human whether anyone
    /// actually took the offer (and what *every* bot individually decided,
    /// not just whoever ended up taking it), since a bot's accept/reject
    /// otherwise happens silently.
    public struct TradeOutcome: Equatable {
        /// Every bot's individual accept/reject answer, in seat order, each
        /// with its own flavor line - a bot always has *something* to say
        /// about a proposal, whether it took the deal or not.
        public let decisions: [(bot: PlayerID, accepted: Bool, message: String)]
        public let acceptedBy: PlayerID?

        public static func == (lhs: TradeOutcome, rhs: TradeOutcome) -> Bool {
            lhs.acceptedBy == rhs.acceptedBy
                && lhs.decisions.map(\.bot) == rhs.decisions.map(\.bot)
                && lhs.decisions.map(\.accepted) == rhs.decisions.map(\.accepted)
                && lhs.decisions.map(\.message) == rhs.decisions.map(\.message)
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
        /// Which accepting bot the trade will actually go through with if
        /// confirmed - defaults to the first bot that accepted (so a
        /// single-accepter trade needs no extra tap), but the human can
        /// switch it to any other accepting bot via `selectTradePartner`
        /// before confirming.
        public let selectedBot: PlayerID
        public let decisions: [(bot: PlayerID, accepted: Bool, message: String)]
    }
    public private(set) var pendingTradeConfirmation: PendingTradeConfirmation?

    /// The `GameLogStore` file this session's moves are being appended to -
    /// (re)set alongside `state` in `init()`/`startNewGame(randomizedBoard:)`.
    /// A game resumed from `GameStore` after an app relaunch starts a *new*
    /// log segment rather than continuing the pre-relaunch one - see the
    /// design doc's Non-goals for why that's an accepted simplification
    /// rather than a bug.
    /// `nil` until the game's first move is actually applied.
    ///
    /// This used to be created eagerly in `init()`, which writes a file
    /// immediately - so every cold launch left a ~20-40 KB start-only log
    /// behind even if the player just looked at the menu and quit, and those
    /// orphans then competed with real games for the retention budget.
    private var currentGameLogID: UUID?

    /// When each currently-pending trade offer was first proposed -
    /// `TradeOffer` itself carries no timestamp, so this is tracked
    /// separately. Used by `runBotTurnIfNeeded` to hold off a bot accepting
    /// someone else's offer for a randomized 2-4s (real Catan only lets you
    /// act on your own turn, but a bot's turn arriving right after the
    /// proposal - with none of the human's read-and-decide time - would
    /// otherwise let it snap up an offer shown to the human before they've
    /// had any real chance at it). Populated in `applyLogged` on every
    /// `.proposeTrade`; pruned there too once an offer leaves
    /// `state.pendingTradeOffers` (accepted, rejected, or otherwise gone).
    private var offerProposedAt: [UUID: Date] = [:]

    /// Foreground time banked so far this game (from previous active spans,
    /// each ended by `appWillResignActive`), plus `activeSince` (when the
    /// current active span began, `nil` while backgrounded) - together these
    /// track actual time spent *playing*, for `GameStatsStore`'s "average
    /// game time" stat, rather than wall-clock time since the game started,
    /// which would also count time the app spent backgrounded/locked.
    private var accumulatedActiveDuration: TimeInterval = 0
    private var activeSince: Date?

    /// The full elapsed foreground time this game, as of right now.
    private var currentGameDuration: TimeInterval {
        accumulatedActiveDuration + (activeSince.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// Resumes the active-time clock - called from `ContentView` on
    /// `scenePhase` becoming `.active`. A no-op if already active (e.g. the
    /// very first call after a game starts, when nothing has resigned
    /// active yet to clear `activeSince`).
    public func appDidBecomeActive() {
        guard activeSince == nil else { return }
        activeSince = Date()
    }

    /// Banks the current active span - called from `ContentView` on
    /// `scenePhase` becoming `.inactive`/`.background`, so that time doesn't
    /// silently keep counting while the app isn't actually on screen.
    public func appWillResignActive() {
        guard let activeSince else { return }
        accumulatedActiveDuration += Date().timeIntervalSince(activeSince)
        self.activeSince = nil
    }

    public init() {
        let initialState: GameState
        let seat: PlayerID
        var saveWasUnreadable = false
        switch GameStore.shared.load() {
        case .loaded(let saved):
            initialState = saved
            // A resumed game keeps whichever seat/civilizations it was
            // dealt, read back from disk rather than re-randomized - falls
            // back to seat 0 / a fresh civilization draw if either file is
            // missing/corrupt (e.g. a save from before these existed) so
            // the game still has *some* consistent lineup instead of the
            // bare defaults.
            seat = HumanSeatStore.shared.load()
            CivilizationAssignment.current = CivilizationAssignmentStore.shared.load()
                ?? Self.drawAssignment(from: CivilizationSettingsStore.shared.load(), humanSeat: seat)
        case .unreadable:
            // A save exists but will not decode. Start a fresh game so the app
            // still launches, but say so rather than pretending there was
            // never a game - and leave the file alone so it can be recovered.
            saveWasUnreadable = true
            initialState = GameSetup.newGame(board: BoardGenerator.standard())
            seat = PlayerID(index: 0)
        case .none:
            initialState = GameSetup.newGame(board: BoardGenerator.standard())
            seat = PlayerID(index: 0)
        }
        CivilizationAssignment.humanSeat = seat
        // `@Observable` requires every stored property assigned before
        // `self` (including `self.state`) can be read - `GameLogStore`
        // reads `initialState` (the local), never `self.state`, to stay
        // fully assign-before-read through this initializer.
        session = Self.makeSession(state: initialState, humanSeat: seat)
        humanPlayer = seat
        currentGameLogID = nil
        self.saveWasUnreadable = saveWasUnreadable
        activeSince = Date()
    }

    /// Starts a fresh game, discarding whatever `state` currently holds.
    /// `randomizeSeat` picks a random seat (0-3) for the human instead of
    /// always seat 0 - covers both draft order and regular turn order,
    /// since both are driven by the same seat rotation in this engine.
    public func startNewGame(randomizedBoard: Bool, randomizeSeat: Bool) {
        let board = randomizedBoard
            ? BoardGenerator.randomized(seed: UInt64.random(in: .min ... .max))
            : BoardGenerator.standard()
        let fresh = GameSetup.newGame(board: board)
        currentGameLogID = nil
        // Invalidate any bot loop still sleeping against the previous game.
        gameGeneration &+= 1
        // Per-game negotiation state, which used to survive a restart: a
        // confirmation banner left open before Restart carried into the new
        // game, where confirming it failed against an offer that no longer
        // existed.
        pendingTradeConfirmation = nil
        lastTradeOutcome = nil
        eventBatch = EventBatch(sequence: eventBatch.sequence + 1, events: [])
        offerProposedAt = [:]
        accumulatedActiveDuration = 0
        activeSince = Date()

        humanPlayer = randomizeSeat ? PlayerID(index: Int.random(in: 0...3)) : PlayerID(index: 0)
        session = Self.makeSession(state: fresh, humanSeat: humanPlayer)
        CivilizationAssignment.humanSeat = humanPlayer
        HumanSeatStore.shared.save(humanPlayer)

        let assignment = Self.drawAssignment(from: CivilizationSettingsStore.shared.load(), humanSeat: humanPlayer)
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

        // Open the log on the first real move rather than at launch, so a
        // session that never plays leaves nothing behind. `stateBeforeMove` is
        // captured first: the `start` line has to describe the position the
        // move list is relative to, not the one after the first move.
        let stateBeforeMove = state
        let gameLogID = currentGameLogID ?? {
            let id = GameLogStore.shared.startNewGame(initialState: stateBeforeMove, roster: seatRoster())
            currentGameLogID = id
            return id
        }()

        eventBatch = EventBatch(
            sequence: eventBatch.sequence,
            events: eventBatch.events + (try session.applyExternal(move, by: player).events))
        GameLogStore.shared.appendMove(gameID: gameLogID, player: player, move: move)

        if case .proposeTrade(let offer) = move {
            offerProposedAt[offer.id] = Date()
        }
        let stillPending = Set(state.pendingTradeOffers.map(\.id))
        offerProposedAt = offerProposedAt.filter { stillPending.contains($0.key) }

        if !wasGameOver, case .gameOver(let winner) = state.phase {
            GameLogStore.shared.finalizeGame(gameID: gameLogID, winner: winner)
            GameStatsStore.shared.recordGameEnd(
                won: winner == humanPlayer,
                // The winning move can push a player past the 10-VP
                // threshold in one jump (e.g. a knight simultaneously
                // claiming Largest Army) - real, legal, and not a bug, but
                // 10 is what "won" means, so that's what the stat reflects,
                // not whatever the actual final tally happened to land on.
                finalVP: min(state.victoryPoints(for: humanPlayer), 10),
                duration: currentGameDuration
            )
        }
    }

    /// Who is sitting in each seat this game, for the log's `start` line.
    ///
    /// Both halves are otherwise unrecoverable from the log: the human's seat
    /// lives in a single `UserDefaults` integer that the next new game
    /// overwrites, and a bot's personality is derived from seat order relative
    /// to that seat rather than stored anywhere.
    private func seatRoster() -> GameLogStore.SeatRoster {
        var personalities: [Int: String] = [:]
        var civilizations: [Int: String] = [:]
        for player in state.players {
            let index = player.id.index
            civilizations[index] = Civilization.forSeat(index).displayName
            guard player.id != humanPlayer else { continue }
            personalities[index] = personalityName(for: player.id)
        }
        return GameLogStore.SeatRoster(
            humanSeat: humanPlayer,
            botPersonalities: personalities,
            civilizations: civilizations
        )
    }

    /// `humanSeat` = the player's chosen civilization; the other 3 seats
    /// (in seat order) = 3 distinct random draws from their included bot
    /// roster (falling back to every other civilization if, somehow, fewer
    /// than 3 are included - e.g. a corrupt settings value that skipped
    /// `SettingsView`'s minimum-3 enforcement).
    private static func drawAssignment(from settings: CivilizationSettings, humanSeat: PlayerID) -> [Civilization] {
        var botPool = settings.includedBotCivilizations.subtracting([settings.yourCivilization])
        if botPool.count < CivilizationSettings.minimumIncludedBots {
            botPool = Set(Civilization.allCases).subtracting([settings.yourCivilization])
        }
        var assignment = Array(Array(botPool).shuffled().prefix(3))
        assignment.insert(settings.yourCivilization, at: humanSeat.index)
        return assignment
    }

    /// Applies a human move, persists the result, and lets any subsequent
    /// bot turns run. A save failure here is swallowed the same way
    /// `runBotTurnIfNeeded()` swallows one: losing the on-disk save is not
    /// worth surfacing as if the move itself failed (the move already
    /// succeeded against `state`, which is what the caller/UI cares about),
    /// and only `RulesEngine.apply`'s own errors indicate the human's move
    /// itself was rejected.
    public func apply(_ move: GameMove) throws {
        beginEventBatch()
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
    #if DEBUG
    // Both methods below exist only to put a screen into a state worth
    // photographing. They are compiled out of release builds and are no longer
    // `public`: `qaForceHumanWin` in particular mutates `phase` directly rather
    // than going through `applyLogged`, so the "win" it produces is invisible
    // to the game log and to `GameStatsStore`. That is correct for a
    // screenshot and wrong for anything else, and while it sat on the public
    // API surface nothing said so at the call site.
    //
    // (The two doc comments here were previously stacked above the same
    // function, so `qaForceHumanWin` carried the description of its
    // neighbour - a symptom of edit-by-append.)

    /// Forces `state.phase` straight to a human win, for screenshotting
    /// `EndGameView` (see `QALaunchFlag.showEndGame`) without playing a game
    /// out to 10 VP. Deliberately records no log entry and no stats.
    func qaForceHumanWin() {
        var forced = session.state
        forced.phase = .gameOver(winner: humanPlayer)
        session.replace(state: forced)
    }

    /// Seeds `pendingTradeConfirmation` with every bot accepting, without a
    /// real offer behind it - lets `QALaunchFlag.showPendingTradeConfirmation`
    /// screenshot `TradePopupView.pendingConfirmationBanner` at its worst case
    /// (every bot seat shown) without scripting a real bot-accepted trade,
    /// which would depend on `TradeHeuristics` agreeing to something.
    /// Confirm/Decline still call the real `respondToTrade`, which will
    /// legitimately fail against this bogus `offerID` - this exists to
    /// photograph the banner's layout, not to be played through.
    func qaSeedPendingTradeConfirmation() {
        let bots = state.players.map(\.id).filter { $0 != humanPlayer }
        guard let selectedBot = bots.first else { return }
        let offerID = UUID()
        pendingTradeConfirmation = PendingTradeConfirmation(
            offerID: offerID,
            selectedBot: selectedBot,
            decisions: bots.map { ($0, true, tradeResponseMessage(for: $0, offerID: offerID, accepted: true)) }
        )
    }
    #endif

    /// The flavor line a bot's accept/reject decision carries, themed to
    /// its empire (see `TradeMessages`) - every bot gets one regardless of
    /// which way it went, so a proposal nobody accepts still comes back
    /// with real reactions instead of a silent wall of rejections. Only
    /// needs the offer's `id` (not the full `TradeOffer`) since
    /// `TradeMessages` only ever keys off that for its deterministic pick.
    private func tradeResponseMessage(for bot: PlayerID, offerID: UUID, accepted: Bool) -> String {
        let empire = Civilization.forSeat(bot.index).tradeMessagesEmpire
        return TradeMessages.response(offer: TradeOffer(id: offerID, from: bot, give: [:], want: [:]), empire: empire, accepted: accepted)
    }

    private func resolveHumanProposedTrade(_ offer: TradeOffer) {
        var decisions: [(bot: PlayerID, accepted: Bool, message: String)] = []
        var firstAccepter: PlayerID?
        // Every *other* seat, not `1..<state.players.count` - that range
        // silently assumed the human always sits in seat 0, which
        // `startNewGame(randomizeSeat: true)` breaks (`humanPlayer` can be
        // any of seats 0-3). With the human elsewhere, the old range
        // evaluated the human's own seat as if it were a bot deciding on
        // their own proposal (showing the human's own name in the
        // confirmation banner) and skipped whichever real bot sat in seat
        // 0 entirely.
        for bot in state.players.map(\.id) where bot != humanPlayer {
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
            // ever offering the bot as a candidate, keeps the accepting
            // bots truthful to what `confirmPendingTrade()` can actually
            // deliver.
            guard let botPlayer = state.players.first(where: { $0.id == bot }),
                  offer.want.allSatisfy({ resource, amount in (botPlayer.resources[resource] ?? 0) >= amount }) else {
                decisions.append((bot, false, tradeResponseMessage(for: bot, offerID: offer.id, accepted: false)))
                continue
            }
            let accepts = TradeHeuristics.evaluate(offer: offer, receiver: bot, state: state, personality: personality(for: bot))
            let message = tradeResponseMessage(for: bot, offerID: offer.id, accepted: accepts)
            decisions.append((bot, accepts, message))
            if accepts, firstAccepter == nil {
                firstAccepter = bot
            }
        }

        if let firstAccepter {
            pendingTradeConfirmation = PendingTradeConfirmation(offerID: offer.id, selectedBot: firstAccepter, decisions: decisions)
            lastTradeOutcome = nil
        } else {
            pendingTradeConfirmation = nil
            // Withdraw the now-universally-rejected offer on any bot's
            // behalf, since a bot's own legal `.respondToTrade(accept:
            // false)` is what actually removes it from
            // `pendingTradeOffers` - `decisions.first?.bot` rather than the
            // old hardcoded `PlayerID(index: 1)`, which broke identically to
            // the loop above whenever the human sat in seat 1
            // (`randomizeSeat`): `Trading.respond` requires `responder !=
            // offer.from`, so applying as the human (`== offer.from`) threw,
            // `try?` swallowed it, and the offer was left stuck in
            // `pendingTradeOffers` forever.
            if let anyBot = decisions.first?.bot {
                try? applyLogged(.respondToTrade(offerID: offer.id, accept: false), by: anyBot)
            }
            lastTradeOutcome = TradeOutcome(decisions: decisions, acceptedBy: nil)
        }
    }

    /// Switches which accepting bot `pendingTradeConfirmation` will confirm
    /// against - a no-op if `bot` didn't actually accept (or nothing's
    /// pending), since the human can only choose among bots that said yes.
    public func selectTradePartner(_ bot: PlayerID) {
        guard let pending = pendingTradeConfirmation else { return }
        guard pending.decisions.contains(where: { $0.bot == bot && $0.accepted }) else { return }
        pendingTradeConfirmation = PendingTradeConfirmation(offerID: pending.offerID, selectedBot: bot, decisions: pending.decisions)
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
        beginEventBatch()
        guard let pending = pendingTradeConfirmation else { return .succeeded }
        pendingTradeConfirmation = nil

        guard state.pendingTradeOffers.contains(where: { $0.id == pending.offerID }) else {
            lastTradeOutcome = nil
            return .offerNoLongerAvailable
        }
        do {
            try applyLogged(.respondToTrade(offerID: pending.offerID, accept: true), by: pending.selectedBot)
        } catch {
            // Withdraw the now-stuck offer on the willing bot's behalf
            // rather than leaving it pending forever with nothing left to
            // confirm it with - same "reject" applied `declinePendingTrade`
            // uses.
            try? applyLogged(.respondToTrade(offerID: pending.offerID, accept: false), by: pending.selectedBot)
            lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: nil)
            try? GameStore.shared.save(state)
            return .resourcesNoLongerAvailable
        }
        lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: pending.selectedBot)
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
        beginEventBatch()
        guard let pending = pendingTradeConfirmation else { return }
        pendingTradeConfirmation = nil
        guard state.pendingTradeOffers.contains(where: { $0.id == pending.offerID }) else { return }
        try? applyLogged(.respondToTrade(offerID: pending.offerID, accept: false), by: pending.selectedBot)
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

    /// Bumped by `startNewGame`. A bot loop already in flight compares this
    /// against the value it started with and stops if they differ.
    ///
    /// The re-entrancy guard above stops two loops running at once, but it
    /// does not stop a loop outliving the game it belongs to. `startNewGame`
    /// replaces `state` wholesale, and a loop parked in its 600 ms sleep wakes
    /// up afterwards, re-derives the next bot from the NEW state, and starts
    /// playing a board the human has not seen yet - writing those moves into
    /// the new game's log. Cancelling by generation rather than by holding a
    /// `Task` handle keeps this correct no matter which of the four call sites
    /// spawned the loop.
    public private(set) var gameGeneration = 0

    /// Everything the engine reported during the most recent user-visible
    /// operation, stamped with a sequence number.
    ///
    /// `RulesEngine.apply` returns structured `GameEvent`s now instead of
    /// appending prose to `GameState`. Views observe this rather than
    /// substring-matching sentences: `GameView`'s roll highlight used to look
    /// for `" rolled "` in the log, so rewording one sentence would silently
    /// have broken a visual effect.
    ///
    /// ## Why a batch with a sequence, and not just the last array
    /// One operation can apply several moves without yielding - resolving a
    /// human's trade proposal applies one rejection per unwilling bot - so a
    /// value overwritten per move would show SwiftUI only the last of them.
    /// Worse, two *identical* consecutive batches compare equal and produce no
    /// `onChange` at all, so an observer would silently miss them. Events are
    /// accumulated across the whole operation and the sequence guarantees the
    /// change is always observable.
    ///
    /// This is the current operation only, not a transcript - keeping history
    /// here would reintroduce the unbounded growth that removing
    /// `GameState.log` just eliminated. `GameLogStore` holds the durable record.
    public struct EventBatch: Equatable {
        public let sequence: Int
        public let events: [GameEvent]
    }
    public private(set) var eventBatch = EventBatch(sequence: 0, events: [])

    /// Starts a new batch. Called at the top of each operation that a view
    /// would react to as one thing.
    /// Builds the session for a game: a policy per bot seat, none for the
    /// human's, so `step()` stops and hands control back when it is their turn.
    ///
    /// The policy RNG is seeded by drawing once from the position's own
    /// generator, so two sessions built from the same position get the same
    /// bot tie-breaks.
    ///
    /// It does **not** survive a save. `policyRNG` lives in `GameSession`, not
    /// in `GameState`, so nothing persists it: a resumed game restarts the
    /// tie-break sequence from draw zero rather than continuing where it left
    /// off. That is invisible in play - the bots are equally good either way -
    /// but it means a saved game is not replayable move-for-move, and the fix
    /// is to move the policy seed into `GameState` alongside `rng`.
    private static func makeSession(state: GameState, humanSeat: PlayerID) -> GameSession {
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players where player.id != humanSeat {
            let index = personalityIndex(for: player.id, humanSeat: humanSeat)
            let entry = botRoster[index]
            policies[player.id] = HeuristicPolicy(personality: entry.preset, id: "heuristic-\(entry.name)")
        }
        var seedSource = state.rng
        return GameSession(state: state, policies: policies, policySeed: seedSource.next())
    }

    private func beginEventBatch() {
        eventBatch = EventBatch(sequence: eventBatch.sequence + 1, events: [])
    }

    /// True when a save file was present at launch but could not be decoded.
    /// Surfaced by `ContentView` so a lost game is reported rather than
    /// silently replaced by a new one.
    public private(set) var saveWasUnreadable = false

    public func runBotTurnIfNeeded() async {
        guard !isProcessingBotTurns else { return }
        isProcessingBotTurns = true
        defer { isProcessingBotTurns = false }

        let generation = gameGeneration

        // The loop is now only pacing and persistence. Choosing the move,
        // deciding whose turn it is and the runaway-action backstop all live
        // in `GameSession`, which a headless harness runs too - so what is
        // measured offline is what is played here.
        while case .seat = session.nextActor() {
            // Pacing, not thinking: the bots decide instantly and this is the
            // only reason a turn is watchable. Configured in `pacing.yml`.
            try? await Task.sleep(for: .seconds(PacingSettingsStore.current.secondsPerBotAction))
            // The game may have been restarted while this loop slept.
            guard generation == gameGeneration else { return }

            guard let (seat, move) = session.decideNext() else { break }
            await waitForFairAcceptWindow(before: move)
            guard generation == gameGeneration else { return }
            beginEventBatch()
            // Captured before the move lands: `recordAppliedMove` opens the
            // game log on the first move, and the `start` line has to describe
            // the position the move list is relative to. `applyLogged` has
            // always done this; this path did not, so any game whose first move
            // was a bot's - three in four, with Randomize Seat on - wrote a log
            // that no longer replayed.
            let stateBeforeMove = state
            let step: GameSession.Step
            do {
                step = try session.commit(seat: seat, move: move)
            } catch {
                // A policy chose a move the rules reject: the two disagree,
                // which is a bug rather than a position to recover from. It was
                // previously a bare `try?`, so the loop simply stopped and the
                // game sat frozen on a bot's turn with nothing said. Note also
                // that `decideNext()` has already advanced `policyRNG`, so a
                // replay of this seed diverges from here regardless.
                assertionFailure("bot \(seat.index) played an illegal \(move): \(error)")
                break
            }
            recordAppliedMove(step, stateBeforeMove: stateBeforeMove)
            try? GameStore.shared.save(state)
        }
    }

    /// Mirrors `applyLogged`'s bookkeeping for a move the session chose.
    ///
    /// `applyLogged` exists for moves decided out here; a bot's move is
    /// applied inside the session, so the logging, stats and trade-offer
    /// housekeeping it would have done has to happen on this side instead.
    private func recordAppliedMove(_ step: GameSession.Step, stateBeforeMove: GameState) {
        let gameLogID = currentGameLogID ?? {
            let id = GameLogStore.shared.startNewGame(initialState: stateBeforeMove, roster: seatRoster())
            currentGameLogID = id
            return id
        }()
        GameLogStore.shared.appendMove(gameID: gameLogID, player: step.actor, move: step.move)
        eventBatch = EventBatch(sequence: eventBatch.sequence, events: eventBatch.events + step.events)

        if case .proposeTrade(let offer) = step.move { offerProposedAt[offer.id] = Date() }
        let stillPending = Set(state.pendingTradeOffers.map(\.id))
        offerProposedAt = offerProposedAt.filter { stillPending.contains($0.key) }

        if case .gameOver(let winner) = state.phase, currentGameLogID != nil {
            GameLogStore.shared.finalizeGame(gameID: gameLogID, winner: winner)
            GameStatsStore.shared.recordGameEnd(
                won: winner == humanPlayer,
                finalVP: min(state.victoryPoints(for: humanPlayer), 10),
                duration: currentGameDuration
            )
            currentGameLogID = nil
        }
    }

    /// Holds off applying `move` if it's a bot accepting someone *else's*
    /// still-open trade offer, until a randomized 2-4s have passed since
    /// that offer was first proposed (see `offerProposedAt`'s doc) - real
    /// Catan only lets you act on your own turn, and without this, a bot
    /// whose turn happens to fall right after the proposal could snap up an
    /// offer the human's card is still showing, with none of the human's
    /// read-and-decide time. A no-op for every other move (declines,
    /// proposals, builds, etc. all go through immediately).
    private func waitForFairAcceptWindow(before move: GameMove) async {
        guard case .respondToTrade(let offerID, true) = move,
              let proposedAt = offerProposedAt[offerID]
        else { return }
        let targetDelay = Double.random(in: 2...4)
        let elapsed = Date().timeIntervalSince(proposedAt)
        guard elapsed < targetDelay else { return }
        try? await Task.sleep(for: .seconds(targetDelay - elapsed))
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

    /// Ranked by seat order *among the 3 bot seats* (not raw seat index) -
    /// with "Randomize Seat" on, the human can occupy any of the 4 seats,
    /// and this keeps the same balanced/aggressive/cautious mix regardless
    /// of which one, rather than that mix silently shrinking to 2 bots
    /// whenever the human isn't sitting in seat 0.
    private func personality(for player: PlayerID) -> BotPersonality {
        Self.botRoster[personalityIndex(for: player)].preset
    }

    /// The same assignment, as a name for the game log. Both read the one
    /// table below so a seat's recorded personality cannot drift from the one
    /// it is actually played with.
    private func personalityName(for player: PlayerID) -> String {
        Self.botRoster[personalityIndex(for: player)].name
    }

    /// Bot seats take these in order, so the same balanced/aggressive/cautious
    /// mix is dealt regardless of which seat the human ended up in.
    private static let botRoster: [(name: String, preset: BotPersonality)] = [
        ("balanced", .balanced),
        ("aggressive", .aggressive),
        ("cautious", .cautious),
    ]

    private func personalityIndex(for player: PlayerID) -> Int {
        Self.personalityIndex(for: player, humanSeat: humanPlayer)
    }

    /// Bot seats take the roster in order, so the same balanced/aggressive/
    /// cautious mix is dealt regardless of which seat the human ended up in.
    private static func personalityIndex(for player: PlayerID, humanSeat: PlayerID) -> Int {
        let botSeatsInOrder = (0...3).filter { $0 != humanSeat.index }
        guard let seat = botSeatsInOrder.firstIndex(of: player.index) else { return 0 }
        return min(seat, botRoster.count - 1)
    }
}
