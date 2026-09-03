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
    let gameStore: GameStore
    let civilizationStore: CivilizationAssignmentStore
    let matchSetupStore: MatchSetupStore
    let humanSeatStore: HumanSeatStore
    private let gameLogStore: GameLogStore
    private let gameStatsStore: GameStatsStore

    /// A recoverable persistence problem that the app must present to the
    /// player. Gameplay stays in memory, but the UI never claims it is safely
    /// resumable when a write failed.
    public internal(set) var persistenceErrorMessage: String?
    public private(set) var gameLogWarning: String?
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
    /// Every seat a person is playing, one to four of them.
    ///
    /// A `Set`, because membership is the question almost every caller asks -
    /// "is this seat a bot?" A count could not express "humans in seats 0 and
    /// 2", and a `[SeatKind]` array would reintroduce the bare index that
    /// `PlayerID` exists to hide.
    public private(set) var humanSeats: Set<PlayerID>

    /// The realized bot identity at each non-human chair.
    ///
    /// Stored directly instead of recomputing from seat order so policy,
    /// dialogue and logging all read the same assignment. The civilization
    /// assignment is durable, so these profiles reconstruct identically after
    /// relaunch without adding another persistence file.
    public private(set) var opponentProfiles: [PlayerID: OpponentProfile]

    /// Human seats in a stable order.
    ///
    /// Sorted, always. `Set` iteration order is seeded per process in Swift, so
    /// anything derived from it that reaches a decision differs between
    /// launches - this repo has been bitten by that four separate times.
    public var sortedHumanSeats: [PlayerID] { humanSeats.sorted() }

    /// Which human is holding the phone right now, in a hot-seat game.
    ///
    /// `nil` until a seat is claimed, which is what makes relaunch correct
    /// without a second flag: a force-quit hot-seat game has nobody at the
    /// device, so the handoff cover is shown before any hand is drawn.
    public private(set) var seatAtDevice: PlayerID?

    /// The seat whose hand is on screen and whose taps are being applied.
    ///
    /// Kept as a computed property with the old name deliberately. Of its
    /// call sites, most ask "who is acting right now" rather than "which seats
    /// are people" - the trade popup's hand, the discard popup, the move that
    /// `apply` records - and for those the answer is unchanged. With one human
    /// seat and nobody claimed, this is byte-identical to the old stored
    /// property, so the single-human path did not move.
    ///
    /// Force-unwrapped through `first!` because a game with no human seat is
    /// not a game this app can present: `MatchSetup.validationProblem` refuses
    /// to start one, and failing loudly here beats inventing seat 0.
    public var humanPlayer: PlayerID {
        if let seatAtDevice, humanSeats.contains(seatAtDevice) { return seatAtDevice }
        guard let first = sortedHumanSeats.first else {
            preconditionFailure("a game must have at least one human seat")
        }
        return first
    }

    /// Whether any seat is played by a bot.
    ///
    /// An all-human table is a supported configuration (spec A1.4), and in one
    /// the player-trade path has nobody to answer it: `resolveHumanProposedTrade`
    /// iterates an empty bot set, so the proposal is answered by nobody, leaves
    /// an offer in `pendingTradeOffers` that no seat can see - `openIncomingOffer`
    /// excludes offers a human proposed - and reports "No one accepted that
    /// trade." over an empty list. The trade UI asks this rather than offering
    /// a button that cannot work.
    public var hasBotSeats: Bool { humanSeats.count < state.players.count }

    /// True when the phone has to change hands before play continues.
    ///
    /// Derived rather than fired as an event at each transition. An event
    /// needs a firing site everywhere control can pass to a person - end turn,
    /// a discard resolving, the bot loop finishing, a resumed save, a restart -
    /// and the bug is always the site nobody remembered. `GameView` already
    /// carries scars from exactly that: `GamePhase.awaitingSeatIndex` exists
    /// because six hand-written copies of "is it my turn" disagreed.
    public var needsHandoff: Bool {
        guard humanSeats.count > 1 else { return false }
        // No human is owed a turn - a bot is thinking, or the game is over.
        // Cover anyway if nobody has claimed the phone. That is reachable on
        // the ordinary path, not only at game start: saves are written after
        // every bot move, so a force quit mid-bot-turn resumes here, and
        // without this no cover appeared while `humanPlayer` fell back to the
        // lowest human seat and drew that player's full hand to whoever picked
        // the phone up.
        guard let owed = seatOwedATurn else { return seatAtDevice == nil }
        return owed != seatAtDevice
    }

    /// The human the game is waiting on, if it is waiting on one.
    ///
    /// `.discarding` is handled separately because `GamePhase.awaitingSeatIndex`
    /// answers `nil` for it - correctly, since the phase is genuinely
    /// multi-seat and no single chair owns it. Reading only `awaitingSeatIndex`
    /// deadlocked a hot-seat game outright: after a 7, the player holding the
    /// phone discarded, the other human stayed in `pending`, and because
    /// `awaitingSeatIndex` was `nil` no handoff cover appeared and
    /// `humanPlayer` never moved - so the discard sheet (which is gated on
    /// `humanPlayer` being pending) went away, while `GameSession.nextActor()`
    /// sat on `.awaitingExternalSeat` for a seat with no way to act.
    public var seatOwedATurn: PlayerID? {
        if case .discarding(let pending) = state.phase {
            // Sorted: `pending` is a `Set` and Swift seeds hash order per
            // process, so `.first` on it would pick a different seat between
            // launches. The holder of the phone goes first when they owe one,
            // so nobody is asked to pass a phone they still have to use.
            let owing = pending.sorted().filter { humanSeats.contains($0) }
            if let seatAtDevice, owing.contains(seatAtDevice) { return seatAtDevice }
            return owing.first
        }
        guard let owed = state.phase.awaitingSeatIndex.map({ PlayerID(index: $0) }),
              humanSeats.contains(owed) else { return nil }
        return owed
    }

    /// Hands the device to whoever the game is waiting on.
    public func claimDeviceForSeatOwedATurn() {
        guard let owed = seatOwedATurn else { return }
        seatAtDevice = owed
    }

    public typealias TradeOutcome = TradeOutcomeState
    public private(set) var lastTradeOutcome: TradeOutcome?

    public typealias PendingTradeConfirmation = PendingTradeConfirmationState
    public private(set) var pendingTradeConfirmation: PendingTradeConfirmation?

    /// The durable log for this game, restored across process relaunches.
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

    public init(
        gameStore: GameStore = .shared,
        civilizationStore: CivilizationAssignmentStore = .shared,
        matchSetupStore: MatchSetupStore = .shared,
        gameLogStore: GameLogStore = .shared,
        gameStatsStore: GameStatsStore = .shared
    ) {
        self.gameStore = gameStore
        self.civilizationStore = civilizationStore
        self.matchSetupStore = matchSetupStore
        let humanSeatStore = HumanSeatStore(defaults: matchSetupStore.defaults)
        self.humanSeatStore = humanSeatStore
        self.gameLogStore = gameLogStore
        self.gameStatsStore = gameStatsStore
        persistenceErrorMessage = nil
        gameLogWarning = nil
        let activeMatchResult = matchSetupStore.loadActiveMatch()
        let initialState: GameState
        let seat: PlayerID
        let assignment: [Civilization]
        var saveWasUnreadable = false
        var resumedSavedGame = false
        switch gameStore.load() {
        case .loaded(let saved):
            resumedSavedGame = true
            initialState = saved
            // A resumed game keeps whichever seat/civilizations it was
            // dealt, read back from disk rather than re-randomized - falls
            // back to seat 0 / a fresh civilization draw if either file is
            // missing/corrupt (e.g. a save from before these existed) so
            // the game still has *some* consistent lineup instead of the
            // bare defaults.
            seat = humanSeatStore.load()
            assignment = Self.restoredCivilizations(
                for: saved, humanSeat: seat,
                civilizationStore: civilizationStore, matchSetupStore: matchSetupStore
            )
        case .unreadable:
            // A save exists but will not decode. Start a fresh game so the app
            // still launches, but say so rather than pretending there was
            // never a game - and leave the file alone so it can be recovered.
            saveWasUnreadable = true
            initialState = GameSetup.newGame(board: BoardGenerator.standard())
            seat = PlayerID(index: 0)
            assignment = Array(Civilization.allCases.prefix(initialState.players.count))
        case .none:
            initialState = GameSetup.newGame(board: BoardGenerator.standard())
            seat = PlayerID(index: 0)
            assignment = Array(Civilization.allCases.prefix(initialState.players.count))
        }
        CivilizationAssignment.current = assignment
        CivilizationAssignment.humanSeat = seat
        // Hot-seat composition, if the game being resumed recorded one.
        // `HumanSeatStore` holds a single seat and cannot express "people in
        // seats 0 and 2", so on its own it turned every human seat but the
        // lowest into a bot on the next launch, and lost their names.
        let roster = Self.restoredRoster(for: initialState, fallback: seat, store: matchSetupStore)
        CivilizationAssignment.humanNames = roster.names
        // `@Observable` requires every stored property assigned before
        // `self` (including `self.state`) can be read - `GameLogStore`
        // reads `initialState` (the local), never `self.state`, to stay
        // fully assign-before-read through this initializer.
        let profiles = Self.opponentProfiles(
            for: initialState, humanSeats: roster.seats,
            civilizations: assignment,
            realizedSeats: activeMatchResult.value?.seats,
            preserveLegacySeatOrder: true
        )
        session = Self.makeSession(state: initialState, opponentProfiles: profiles)
        humanSeats = roster.seats
        opponentProfiles = profiles
        // Nobody is holding a force-quit phone, so a hot-seat game resumes
        // behind the handoff cover rather than showing whoever's hand happens
        // to be up. A solo game has nobody to pass to and claims immediately.
        seatAtDevice = roster.seats.count == 1 ? roster.seats.first : nil
        do {
            currentGameLogID = resumedSavedGame ? try gameLogStore.activeGameID() : nil
            if !resumedSavedGame { try gameLogStore.abandonActiveGame() }
        } catch {
            currentGameLogID = nil
            gameLogWarning = error.localizedDescription
        }
        self.saveWasUnreadable = saveWasUnreadable
        activeSince = Date()
        if resumedSavedGame, activeMatchResult == .unreadable {
            persistenceErrorMessage = "The game was restored, but its saved player setup could not be read."
        }
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
        // Per-game bookkeeping, including the negotiation state that used to
        // survive a restart: a confirmation banner left open before Restart
        // carried into the new game, where confirming it failed against an
        // offer that no longer existed. Shared with `startNewGame(setup:)` so
        // the two entry points cannot drift over what a new game clears.
        resetPerGameState()

        humanSeats = [randomizeSeat ? PlayerID(index: Int.random(in: 0...3)) : PlayerID(index: 0)]
        seatAtDevice = sortedHumanSeats.first
        CivilizationAssignment.humanNames = [:]
        // This entry point builds a one-human game, so any hot-seat roster from
        // the previous match must not outlive it - a resumed game reading a
        // stale roster would seat people who are no longer playing. Cleared
        // rather than rewritten: with no record, `restoredRoster` falls back to
        // `HumanSeatStore`'s single seat, which is exactly what this builds.
        matchSetupStore.clearActiveMatch()
        CivilizationAssignment.humanSeat = humanPlayer
        humanSeatStore.save(humanPlayer)

        let assignment = Self.drawAssignment(from: CivilizationSettingsStore.shared.load(), humanSeat: humanPlayer)
        CivilizationAssignment.current = assignment
        opponentProfiles = Self.opponentProfiles(
            for: fresh, humanSeats: humanSeats, civilizations: assignment
        )
        session = Self.makeSession(state: fresh, opponentProfiles: opponentProfiles)
        persistLegacyMatch(assignment: assignment)
    }

    /// Starts a game from a full `MatchSetup` - the New Game screen's output.
    ///
    /// The older two-flag entry point above remains for the paths that have
    /// not moved yet; it builds the same thing with one human and stored
    /// preferences.
    public func startNewGame(setup: MatchSetup) {
        startNewGame(setup: setup, configuredAs: setup)
    }

    private func startNewGame(setup: MatchSetup, configuredAs prefill: MatchSetup) {
        precondition(setup.isStartable, "refusing to start an invalid match: \(setup.validationProblem ?? "")")
        let match = Self.prepareMatch(from: setup)
        guard persist(match, configuredAs: prefill) else { return }
        resetPerGameState()
        install(match)
    }

    struct PreparedMatch {
        let chairs: [MatchSetup.Seat]
        let state: GameState
        let humanSeats: Set<PlayerID>
        let humanNames: [PlayerID: String]
        let civilizations: [Civilization]
        let opponentProfiles: [PlayerID: OpponentProfile]
    }

    private static func prepareMatch(from setup: MatchSetup) -> PreparedMatch {
        let chairs = orderedChairs(from: setup)
        let state = makeInitialState(for: setup, playerCount: chairs.count)
        let roster = humanRoster(in: chairs)
        let pool = CivilizationSettingsStore.shared.load().eligibleRandomCivilizations
        let civilizations = resolveRandomCivilizations(
            configured: chairs.map(\.civilization), eligiblePool: pool)
        let profiles = opponentProfiles(
            for: state, humanSeats: roster.seats, civilizations: civilizations,
            realizedSeats: chairs
        )
        return PreparedMatch(chairs: chairs,
                             state: state,
                             humanSeats: roster.seats,
                             humanNames: roster.names,
                             civilizations: civilizations,
                             opponentProfiles: profiles)
    }

    /// Shuffles configured players as units so names and civilizations stay
    /// attached to their owners while only chair order changes.
    private static func orderedChairs(from setup: MatchSetup) -> [MatchSetup.Seat] {
        guard setup.randomizeSeatOrder else { return setup.seats }
        return setup.seats.shuffled()
    }

    private static func makeInitialState(for setup: MatchSetup, playerCount: Int) -> GameState {
        let board = setup.randomizedBoard
            ? BoardGenerator.randomized(seed: UInt64.random(in: .min ... .max))
            : BoardGenerator.standard()
        return GameSetup.newGame(board: board,
                                 seed: UInt64.random(in: .min ... .max),
                                 playerCount: playerCount,
                                 victoryPointTarget: setup.victoryPointTarget)
    }

    private static func humanRoster(
        in chairs: [MatchSetup.Seat]
    ) -> (seats: Set<PlayerID>, names: [PlayerID: String]) {
        var seats: Set<PlayerID> = []
        var names: [PlayerID: String] = [:]
        for (chair, configured) in chairs.enumerated() {
            let id = PlayerID(index: chair)
            if configured.isHuman {
                seats.insert(id)
                names[id] = configured.name.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return (seats, names)
    }

    private func install(_ match: PreparedMatch) {
        humanSeats = match.humanSeats
        seatAtDevice = match.humanSeats.count == 1 ? match.humanSeats.first : nil
        opponentProfiles = match.opponentProfiles
        session = Self.makeSession(state: match.state, opponentProfiles: match.opponentProfiles)

        CivilizationAssignment.humanSeat = humanPlayer
        CivilizationAssignment.humanNames = match.humanNames
        CivilizationAssignment.current = match.civilizations
    }

    private func persistLegacyMatch(assignment: [Civilization]) {
        do {
            try civilizationStore.save(assignment)
            try gameStore.save(state)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "The game is running, but it could not be saved for later."
        }
    }

    private func persistCurrentState() {
        do {
            try gameStore.save(state)
            persistenceErrorMessage = nil
        } catch {
            persistenceErrorMessage = "Your move was made, but the game could not be saved for later."
        }
    }

    #if DEBUG
    /// QA-only: writes the current in-memory state to disk immediately.
    /// `replaceStateForTesting` (which every QA fixture, e.g.
    /// `qaSeedIncomingTrade`, goes through) does not persist on its own, so
    /// a UI test that needs a seeded fixture to survive a real process
    /// relaunch has to force it explicitly.
    func qaPersistCurrentState() { persistCurrentState() }
    #endif

    public func dismissPersistenceError() {
        persistenceErrorMessage = nil
    }

    public func clearCompletedMatch() -> Bool {
        do {
            try gameStore.clear()
            try civilizationStore.clear()
            matchSetupStore.clearActiveMatch()
            persistenceErrorMessage = nil
            return true
        } catch {
            persistenceErrorMessage = "The finished game could not be cleared. Please try again."
            return false
        }
    }

    /// The configured seats renumbered into the chairs they were dealt, with
    /// every civilization now decided - the record a resumed game reads.
    static func realisedMatch(chairs: [MatchSetup.Seat],
                              civilizations: [Civilization],
                              opponentProfiles: [PlayerID: OpponentProfile],
                              from setup: MatchSetup) -> MatchSetup {
        MatchSetup(
            seats: chairs.enumerated().map { chair, configured in
                MatchSetup.Seat(index: chair,
                                isHuman: configured.isHuman,
                                name: configured.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                civilization: civilizations[chair],
                                opponentProfile: opponentProfiles[PlayerID(index: chair)])
            },
            victoryPointTarget: setup.victoryPointTarget,
            randomizedBoard: setup.randomizedBoard,
            randomizeSeatOrder: setup.randomizeSeatOrder
        )
    }

    /// Restarts the match the player configured, rather than a fixed default.
    ///
    /// The In-Game Settings screen's Restart used to call the two-flag entry
    /// point, which always builds a four-seat, ten-point, one-human game - so a
    /// three-player hot-seat game played to eight came back as something else
    /// entirely, silently. The stored prefill is the player's own layout and is
    /// the right thing to replay; the flags are only reached when there is no
    /// stored setup at all (a save from before this screen existed).
    public func restartCurrentMatch(fallbackRandomizedBoard: Bool, fallbackRandomizeSeat: Bool) {
        guard case .loaded(let previous) = matchSetupStore.load(), previous.isStartable else {
            startNewGame(randomizedBoard: fallbackRandomizedBoard, randomizeSeat: fallbackRandomizeSeat)
            return
        }
        // Restart means replay this table, not draw different opponents. The
        // active record contains the resolved Random civilizations and actual
        // shuffled chairs; the prefill remains what the New Game screen should
        // show next time.
        if case .loaded(var active) = matchSetupStore.loadActiveMatch(), active.isStartable {
            active.randomizeSeatOrder = false
            startNewGame(setup: active, configuredAs: previous)
        } else {
            startNewGame(setup: previous)
        }
    }

    /// Who is playing the game being resumed, and what they are called.
    ///
    /// Read from `MatchSetupStore.loadActiveMatch()`, which records the chairs
    /// as they were actually dealt. The record is checked against the state on
    /// disk before it is trusted - a stored roster whose seat count disagrees
    /// with the saved game belongs to a different match, and following it would
    /// name seats that do not exist. In that case, and for a game started
    /// before the record existed, this falls back to the single seat
    /// `HumanSeatStore` holds, which is exactly the old behaviour.
    private static func restoredRoster(
        for state: GameState,
        fallback: PlayerID,
        store: MatchSetupStore
    ) -> (seats: Set<PlayerID>, names: [PlayerID: String]) {
        guard case .loaded(let active) = store.loadActiveMatch(),
              active.seats.count == state.players.count,
              !active.humanSeats.isEmpty
        else { return ([fallback], [:]) }

        var seats: Set<PlayerID> = []
        var names: [PlayerID: String] = [:]
        for chair in active.humanSeats {
            let id = PlayerID(index: chair.index)
            seats.insert(id)
            if !chair.name.isEmpty { names[id] = chair.name }
        }
        // A solo seat's name is KEPT. Discarding it here threw away the name
        // the player typed on the New Game screen on every relaunch, so the
        // game silently reverted to the App Settings preference - the prefill
        // becoming the running value, which X1.2 forbids, in the most common
        // configuration of all. The loop above already skips empty names, so a
        // player who typed nothing still falls through to
        // `PlayerNameStore`/"You" exactly as before.
        return (seats, names)
    }

    /// Records the finished game against lifetime statistics - **solo games
    /// only**.
    ///
    /// A hot-seat game must not touch them, and not merely because "your win
    /// rate" is ill-defined when four people share a phone. `apply` applies
    /// every move as the seat holding the device, so the winner of a hot-seat
    /// game IS the phone's owner by construction: recording them would drive a
    /// shared device to a permanent 100% win rate, resettable only by wiping
    /// every statistic. Spec C4.4.
    ///
    /// The victory-point cap follows the game's own target rather than a
    /// hardcoded ten. The winning move can push a player past the threshold in
    /// one jump - a knight that simultaneously claims Largest Army - which is
    /// legal and not worth recording as a bigger score, but in a twelve-point
    /// game the threshold is twelve, and capping at ten filed every Epic win
    /// as a ten.
    var shouldRecordLifetimeStatistics: Bool { humanSeats.count == 1 }

    private func recordGameEndIfSolo(winner: PlayerID) {
        guard shouldRecordLifetimeStatistics else { return }
        gameStatsStore.recordGameEnd(
            won: winner == humanPlayer,
            finalVP: min(state.victoryPoints(for: humanPlayer), state.victoryPointTarget),
            duration: currentGameDuration
        )
    }

    /// The bookkeeping every new game clears, whichever entry point started it.
    private func resetPerGameState() {
        currentGameLogID = nil
        recordLogOperation { try gameLogStore.abandonActiveGame() }
        gameGeneration &+= 1
        pendingTradeConfirmation = nil
        lastTradeOutcome = nil
        eventBatch = EventBatch(sequence: eventBatch.sequence + 1, events: [])
        offerProposedAt = [:]
        accumulatedActiveDuration = 0
        activeSince = Date()
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
        let gameLogID = openGameLogIfNeeded(initialState: stateBeforeMove)

        eventBatch = EventBatch(
            sequence: eventBatch.sequence,
            events: eventBatch.events + (try session.applyExternal(move, by: player).events))
        recordLogOperation {
            if let gameLogID { try gameLogStore.appendMove(gameID: gameLogID, player: player, move: move) }
        }

        if case .proposeTrade(let offer) = move {
            offerProposedAt[offer.id] = Date()
        }
        let stillPending = Set(state.pendingTradeOffers.map(\.id))
        offerProposedAt = offerProposedAt.filter { stillPending.contains($0.key) }

        if !wasGameOver, case .gameOver(let winner) = state.phase {
            recordLogOperation {
                if let gameLogID { try gameLogStore.finalizeGame(gameID: gameLogID, winner: winner) }
            }
            recordGameEndIfSolo(winner: winner)
            currentGameLogID = nil
        }
    }

    private func openGameLogIfNeeded(initialState: GameState) -> UUID? {
        if let currentGameLogID { return currentGameLogID }
        do {
            let id = try gameLogStore.startNewGame(initialState: initialState, roster: seatRoster())
            currentGameLogID = id
            return id
        } catch {
            gameLogWarning = error.localizedDescription
            return nil
        }
    }

    private func recordLogOperation(_ operation: () throws -> Void) {
        do { try operation() } catch { gameLogWarning = error.localizedDescription }
    }

    public func dismissGameLogWarning() { gameLogWarning = nil }

    /// Who is sitting in each seat this game, for the log's `start` line.
    ///
    /// Both halves are otherwise unrecoverable from the log: the human's seat
    /// lives in a single `UserDefaults` integer that the next new game
    /// overwrites, and a bot's personality is derived from seat order relative
    /// to that seat rather than stored anywhere.
    private func seatRoster() -> GameLogStore.SeatRoster {
        var personalities: [Int: String] = [:]
        var profiles: [Int: String] = [:]
        var profileNames: [Int: String] = [:]
        var civilizations: [Int: String] = [:]
        for player in state.players {
            let index = player.id.index
            civilizations[index] = Civilization.forSeat(index).displayName
            guard !humanSeats.contains(player.id) else { continue }
            profiles[index] = opponentProfile(for: player.id)?.id
            profileNames[index] = opponentProfile(for: player.id)?.name
            personalities[index] = personalityName(for: player.id)
        }
        return GameLogStore.SeatRoster(
            humanSeats: humanSeats,
            humanNames: Dictionary(uniqueKeysWithValues: CivilizationAssignment.humanNames.map {
                ($0.key.index, $0.value)
            }),
            botProfiles: profiles,
            botProfileNames: profileNames,
            botPersonalities: personalities,
            civilizations: civilizations
        )
    }

    /// Resolves every Random chair strictly inside the selected pool.
    ///
    /// Exhaustion is a violated settings invariant, not permission to use a
    /// civilization the player excluded. Failing here exposes corrupt input;
    /// silently widening the pool made the Surface C control untruthful.
    static func resolveRandomCivilizations(
        configured: [Civilization?],
        eligiblePool: Set<Civilization>
    ) -> [Civilization] {
        var taken = Set(configured.compactMap { $0 })
        precondition(taken.count == configured.compactMap { $0 }.count,
                     "configured seats must have distinct civilizations")

        return configured.map { chosen in
            guard let chosen else {
                let available = eligiblePool
                    .filter { !taken.contains($0) }
                    .sorted { $0.rawValue < $1.rawValue }
                precondition(!available.isEmpty,
                             "Random civilization pool cannot fill every configured seat")
                let drawn = available.randomElement()!
                taken.insert(drawn)
                return drawn
            }
            return chosen
        }
    }

    /// `humanSeat` gets the preference; every other seat draws from the exact
    /// eligible pool after excluding that assignment.
    static func drawAssignment(from settings: CivilizationSettings, humanSeat: PlayerID) -> [Civilization] {
        var configured = [Civilization?](repeating: nil, count: GameSetup.standardPlayerCount)
        configured[humanSeat.index] = settings.yourCivilization
        return resolveRandomCivilizations(
            configured: configured,
            eligiblePool: settings.eligibleRandomCivilizations)
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
        // A bot negotiation belongs to the turn that started it. Left standing
        // across `endTurn`, the next player's Trade screen opened on the
        // previous player's banner - which REPLACES the builder, so they could
        // not compose a trade until they declined somebody else's offer, which
        // then failed with `.offerNoLongerAvailable` because `RulesEngine`
        // drops pending offers at `endTurn` anyway.
        if case .endTurn = move {
            pendingTradeConfirmation = nil
            lastTradeOutcome = nil
        }
        try applyLogged(move, by: humanPlayer)
        if case .proposeTrade(let offer) = move, offer.from == humanPlayer {
            resolveHumanProposedTrade(offer)
        }
        persistCurrentState()
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
    /// Replaces the whole position and the human's seat, for tests.
    ///
    /// `#if DEBUG` alongside the QA hooks because it exists for the same
    /// reason: it puts the model into a state that would otherwise take a
    /// played-out game to reach. Tests use it to construct exact trade
    /// positions - a bot offer the human can afford, one they cannot, one the
    /// proposer can no longer honour - which is how `openIncomingOffer` is
    /// pinned in both directions.
    func replaceStateForTesting(_ newState: GameState, humanSeat: PlayerID) {
        replaceStateForTesting(newState, humanSeats: [humanSeat])
    }

    /// Multi-seat overload, for hot-seat tests.
    func replaceStateForTesting(_ newState: GameState, humanSeats seats: Set<PlayerID>) {
        precondition(!seats.isEmpty, "a game must have at least one human seat")
        humanSeats = seats
        seatAtDevice = seats.sorted().first
        // Do not read the process-global assignment here. Swift Testing runs
        // test functions concurrently, and another fixture may be exercising
        // a three-seat table while this one installs four seats. The old
        // helper did not need the mapping; profiles do, so give tests their
        // own deterministic complete assignment.
        let civilizations = Array(Civilization.allCases.prefix(newState.players.count))
        CivilizationAssignment.current = civilizations
        opponentProfiles = Self.opponentProfiles(
            for: newState, humanSeats: seats, civilizations: civilizations
        )
        session = Self.makeSession(state: newState, opponentProfiles: opponentProfiles)
    }

    /// Drops the device claim, reproducing a relaunch where nobody is holding
    /// the phone yet. Tests only.
    func qaClearSeatAtDeviceForTesting() { seatAtDevice = nil }

    /// Turns the loaded game into a two-human hot-seat game, for
    /// screenshotting `HandoffCoverView` (see `QALaunchFlag.twoHumans`).
    ///
    /// Seats 0 and 1 become people and nobody is at the device, which is
    /// exactly the state a relaunched hot-seat game is in - so the cover shows
    /// before any hand is drawn.
    func qaMakeHotSeat() {
        let seats: Set<PlayerID> = [PlayerID(index: 0), PlayerID(index: 1)]
        humanSeats = seats
        seatAtDevice = nil
        CivilizationAssignment.humanNames = [
            PlayerID(index: 0): "Alex",
            PlayerID(index: 1): "Sam",
        ]
        opponentProfiles = Self.opponentProfiles(
            for: state, humanSeats: seats, civilizations: CivilizationAssignment.current
        )
        session = Self.makeSession(state: state, opponentProfiles: opponentProfiles)
    }

    /// Forces `state.phase` straight to a human win, for screenshotting
    /// `EndGameView` (see `QALaunchFlag.showEndGame`) without playing a game
    /// out to 10 VP. Deliberately records no log entry and no stats.
    func qaForceHumanWin() {
        var forced = session.state
        forced.phase = .gameOver(winner: humanPlayer)
        session.replace(state: forced)
    }

    /// Plays through production session, log, stats, and save bookkeeping without UI delays.
    func qaPlayToEnd() {
        for seat in humanSeats {
            session.policies[seat] = HeuristicPolicy(personality: .balanced, id: "qa-human")
        }
        for _ in 0..<10_000 {
            if case .gameOver = state.phase { return }
            do {
                guard let (seat, move) = session.decideNext() else {
                    preconditionFailure("QA complete match stopped before game over")
                }
                try applyPolicyMove(move, by: seat)
            } catch {
                preconditionFailure("QA complete match failed: \(error)")
            }
        }
        preconditionFailure("QA complete match exceeded 10,000 moves")
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
        let bots = state.players.map(\.id).filter { !humanSeats.contains($0) }
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
        for bot in state.players.map(\.id) where !humanSeats.contains(bot) {
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
            persistCurrentState()
            return .resourcesNoLongerAvailable
        }
        lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: pending.selectedBot)
        persistCurrentState()
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
        persistCurrentState()
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
    /// `state`: one captures the acting bot, sleeps
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
    /// `session.nextActor()` fresh every iteration, so it naturally picks up
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

    public typealias EventBatch = GameEventBatch
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
    /// Seats every realized opponent profile with its configured policy.
    ///
    /// `GameSession` drives a seat only if it has a policy; a seat without one
    /// returns `.awaitingExternalSeat` and the loop stops for it. That is
    /// already how the single human works, so one to four humans needs no
    /// engine change - only that this hands out policies by set membership
    /// rather than by inequality with one seat.
    private static func makeSession(
        state: GameState,
        opponentProfiles: [PlayerID: OpponentProfile]
    ) -> GameSession {
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players {
            guard let profile = opponentProfiles[player.id] else { continue }
            policies[player.id] = HeuristicPolicy(
                personality: profile.strategicPersonality,
                id: "heuristic-\(profile.strategy.rawValue)"
            )
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

    /// True while `InGameSettingsView` is on screen. The bot loop stops on it
    /// for the same reason it stops on `openIncomingOffer`: a surface the
    /// player is reading must not have the game move underneath it (spec
    /// B3.4). Without this, opening the settings mid-bot-turn left the bots
    /// playing on behind the screen, and the player came back to a position
    /// they had not seen reached.
    ///
    /// Written by `GameView`, which mirrors its own presentation state here.
    public var isSettingsSurfaceOpen = false

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
            if openIncomingOffer != nil { return }

            // Same `return`-don't-park reasoning as the offer check above:
            // parking here would hold `isProcessingBotTurns` for as long as
            // the settings screen stayed open, and the restart already exists
            // - `GameView` kicks `runBotTurnIfNeeded()` again on dismissal.
            if isSettingsSurfaceOpen { return }

            // Pacing, not thinking: the bots decide instantly and this is the
            // only reason a turn is watchable.
            //
            // Read from the singleton on every iteration rather than captured
            // once before the loop: that is the whole of B1.2 - a speed the
            // player changes mid-turn has to reach the very next action, not
            // the next game.
            try? await Task.sleep(for: .seconds(PacingPreferences.shared.aiTurnSpeed.secondsPerBotAction))
            // The game may have been restarted while this loop slept.
            guard generation == gameGeneration else { return }

            guard let (seat, move) = session.decideNext() else { break }
            await waitForFairAcceptWindow(before: move)
            guard generation == gameGeneration else { return }
            do {
                try applyPolicyMove(move, by: seat)
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
        }
    }

    /// One policy move plus the production bookkeeping shared by paced and QA loops.
    private func applyPolicyMove(_ move: GameMove, by seat: PlayerID) throws {
        beginEventBatch()
        let stateBeforeMove = state
        let step = try session.commit(seat: seat, move: move)
        recordAppliedMove(step, stateBeforeMove: stateBeforeMove)
        persistCurrentState()
    }

    /// Mirrors `applyLogged`'s bookkeeping for a move the session chose.
    ///
    /// `applyLogged` exists for moves decided out here; a bot's move is
    /// applied inside the session, so the logging, stats and trade-offer
    /// housekeeping it would have done has to happen on this side instead.
    private func recordAppliedMove(_ step: GameSession.Step, stateBeforeMove: GameState) {
        let gameLogID = openGameLogIfNeeded(initialState: stateBeforeMove)
        recordLogOperation {
            if let gameLogID { try gameLogStore.appendMove(gameID: gameLogID, player: step.actor, move: step.move) }
        }
        eventBatch = EventBatch(sequence: eventBatch.sequence, events: eventBatch.events + step.events)

        if case .proposeTrade(let offer) = step.move { offerProposedAt[offer.id] = Date() }
        let stillPending = Set(state.pendingTradeOffers.map(\.id))
        offerProposedAt = offerProposedAt.filter { stillPending.contains($0.key) }

        if case .gameOver(let winner) = state.phase, currentGameLogID != nil {
            recordLogOperation {
                if let gameLogID { try gameLogStore.finalizeGame(gameID: gameLogID, winner: winner) }
            }
            recordGameEndIfSolo(winner: winner)
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

    /// A bot-proposed offer the human could accept right now, if there is one.
    ///
    /// Derived from `state` rather than mirrored from the view, because the bot
    /// loop has to gate on it and the loop cannot see the view's state. Same
    /// engine predicate the card itself uses, so the two cannot disagree about
    /// whether an offer is live.
    var openIncomingOffer: TradeOffer? {
        state.pendingTradeOffers.first {
            !humanSeats.contains($0.from)
                && Trading.bothSidesCanHonour($0, responder: humanPlayer, state: state)
        }
    }

}
