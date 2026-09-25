import Foundation
import Observation
import CatanEngine
import CatanAI

/// Drives a local match through candidate sessions. The checkpoint document is
/// the durable authority; state and events are published only after its commit.
@MainActor
@Observable
public final class GameViewModel {
    enum GameLogWarningState: Equatable {
        case export(String)
        case other(String)

        var message: String {
            switch self {
            case .export(let message), .other(let message): message
            }
        }
    }

    let gameStore: GameStore
    let civilizationStore: CivilizationAssignmentStore
    let matchSetupStore: MatchSetupStore
    let humanSeatStore: HumanSeatStore
    let gameLogStore: GameLogStore
    let gameStatsStore: GameStatsStore
    let ghostStore: GhostStore
    let ratingStore: RatingStore
    /// Rating and ghost training for the game that just ended; a test awaits it.
    var lastFinishedMatchWork: Task<Void, Never>?
    let checkpointStore: MatchCheckpointStore
    var checkpointDocument: MatchCheckpointDocument?
    var persistenceBlocked = false

    public var statistics: GameStats { checkpointDocument?.statistics ?? GameStats() }
    public var requiresSaveReplacementConfirmation: Bool { savedGameAvailability != .absent }

    /// The archive id of the match currently loaded, which is the match id
    /// itself - `GameLogStore.export` names the recording after the
    /// checkpoint. Non-nil right through the end-game screen, because the
    /// finished match stays active until `clearCompletedMatch()`; that is what
    /// lets "View Replay" there open the game the player has just finished
    /// without hunting for it in the archive.
    public var currentGameLogID: UUID? { checkpointDocument?.activeMatch?.id }

    /// Failed writes leave the prior committed board visible and stop bots.
    /// Dismissing an alert does not license further unsaved policy moves.
    public internal(set) var persistenceErrorMessage: String?
    var gameLogWarningState: GameLogWarningState?
    public internal(set) var gameLogWarning: String? {
        get { gameLogWarningState?.message }
        set { gameLogWarningState = newValue.map(GameLogWarningState.other) }
    }
    public internal(set) var savedGameAvailability: SavedGameAvailability = .absent
    public internal(set) var newGameSetupLoadResult: MatchSetupStore.LoadResult
    /// The one loop. Bots are decided by policies inside this session, and
    /// the human's own moves go through `applyExternal`, so the app and any
    /// headless harness advance the game through identical code. They used to
    /// be two loops: this one had sleeps, a re-entrancy guard, an action cap
    /// and its own trade resolution, none of which a harness ever executed -
    /// so the bots being measured were not the bots being played.
    ///
    /// Pacing stays out here. `GameSession` has no notion of elapsed time.
    var session: GameSession

    public var state: GameState { session.state }
    /// Match-scoped visual and controller identity, derived from the same
    /// realized setup that is stored in the durable checkpoint.
    var playerRoster: PlayerRoster

    /// Every seat a person is playing, one to four of them.
    ///
    /// A `Set`, because membership is the question almost every caller asks -
    /// "is this seat a bot?" A count could not express "humans in seats 0 and
    /// 2", and a `[SeatKind]` array would reintroduce the bare index that
    /// `PlayerID` exists to hide.
    public var humanSeats: Set<PlayerID> { playerRoster.humanSeats }

    /// The realized bot identity at each non-human chair.
    ///
    /// Stored directly instead of recomputing from seat order so policy,
    /// dialogue and logging all read the same assignment. The civilization
    /// assignment is durable, so these profiles reconstruct identically after
    /// relaunch from the checkpoint's realized setup.
    public var opponentProfiles: [PlayerID: OpponentProfile] { playerRoster.opponentProfiles }

    /// Which human is holding the phone right now, in a hot-seat game.
    ///
    /// `nil` until a seat is claimed, which is what makes relaunch correct
    /// without a second flag: a force-quit hot-seat game has nobody at the
    /// device, so the handoff cover is shown before any hand is drawn.
    public internal(set) var seatAtDevice: PlayerID?

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
        // Pass-and-play is gone (Jake, 2026-09-25), but an old save with
        // several human seats still resumes: whoever the game is waiting on
        // acts, with no hand-off cover. With one human this is that human.
        if let owed = seatOwedATurn { return owed }
        if let seatAtDevice, humanSeats.contains(seatAtDevice) { return seatAtDevice }
        guard let first = sortedHumanSeats.first else {
            preconditionFailure("a game must have at least one human seat")
        }
        return first
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
        // Private acknowledgements outrank ordinary turn routing. A winning
        // Victory Point or third Knight can end the game immediately; after a
        // cold hot-seat resume there is otherwise no phase-owned seat left to
        // tell the cover who may safely read the result.
        if let owner = pendingDevCardReveal?.owner, humanSeats.contains(owner) { return owner }
        if let owner = pendingDevCardResolution?.owner, humanSeats.contains(owner) { return owner }
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

    public typealias TradeOutcome = TradeOutcomeState
    public private(set) var lastTradeOutcome: TradeOutcome?

    public typealias PendingTradeConfirmation = PendingTradeConfirmationState
    public private(set) var pendingTradeConfirmation: PendingTradeConfirmation?

    /// Exact purchase result for the person holding the device. This is set
    /// from `GameSession.Step.privateEvents` only after checkpoint commit.
    public internal(set) var pendingDevCardReveal: DevCardReveal?
    /// A human card's exact committed outcome, retained until acknowledged.
    public internal(set) var pendingDevCardResolution: DevCardResolution?

    /// Uncommitted mandatory-discard choices and whether their editor is in
    /// inspect-only mode. These stay out of `GameState`, but belong to this
    /// match coordinator rather than a disposable popup.
    var discardDraft = DiscardDraft()
    public internal(set) var isDiscardEditorMinimized = false

    /// Owns uncommitted board choices beside the durable session so write
    /// failures retain them and hot-seat handoffs can clear them centrally.
    var boardDecisionCoordinator = BoardDecisionCoordinator()

    /// Foreground time banked so far this game (from previous active spans,
    /// each ended by `appWillResignActive`), plus `activeSince` (when the
    /// current active span began, `nil` while backgrounded) - together these
    /// track actual time spent *playing*, for `GameStatsStore`'s "average
    /// game time" stat, rather than wall-clock time since the game started,
    /// which would also count time the app spent backgrounded/locked.
    var accumulatedActiveDuration: TimeInterval = 0
    var activeSince: Date?
    private var appIsActive = true

    /// The full elapsed foreground time this game, as of right now.
    var currentGameDuration: TimeInterval {
        accumulatedActiveDuration + (activeSince.map { max(0, Date().timeIntervalSince($0)) } ?? 0)
    }

    /// Resumes the active-time clock - called from `ContentView` on
    /// `scenePhase` becoming `.active`. A no-op if already active (e.g. the
    /// very first call after a game starts, when nothing has resigned
    /// active yet to clear `activeSince`).
    public func appDidBecomeActive() {
        appIsActive = true
        guard activeSince == nil, checkpointDocument?.activeMatch != nil else { return }
        if case .gameOver = state.phase { return }
        activeSince = Date()
    }

    /// Banks the current active span - called from `ContentView` on
    /// `scenePhase` becoming `.inactive`/`.background`, so that time doesn't
    /// silently keep counting while the app isn't actually on screen.
    public func appWillResignActive() {
        appIsActive = false
        guard let activeSince else { return }
        accumulatedActiveDuration += max(0, Date().timeIntervalSince(activeSince))
        self.activeSince = nil
        guard let document = checkpointDocument else { return }
        do { try commitDocument(document.recordingElapsedTime(accumulatedActiveDuration)) } catch {
            persistenceErrorMessage = error.localizedDescription
        }
        // Turn-boundary archiving (`exportCommittedRecordings(after:in:)`)
        // leaves a game abandoned mid-turn behind; this is the flush for it.
        exportCommittedRecordings()
    }

    public convenience init(
        gameStore: GameStore = .shared,
        civilizationStore: CivilizationAssignmentStore = .shared,
        matchSetupStore: MatchSetupStore = .shared,
        gameLogStore: GameLogStore = .shared,
        gameStatsStore: GameStatsStore = .shared,
        ghostStore: GhostStore = .shared,
        ratingStore: RatingStore = .shared
    ) {
        self.init(checkpointStore: MatchCheckpointStore(fileURL: gameStore.fileURL
            .deletingLastPathComponent().appendingPathComponent("match_checkpoint.json")),
                  gameStore: gameStore, civilizationStore: civilizationStore,
                  matchSetupStore: matchSetupStore, gameLogStore: gameLogStore, gameStatsStore: gameStatsStore,
                  ghostStore: ghostStore, ratingStore: ratingStore)
    }

    init(checkpointStore: MatchCheckpointStore, gameStore: GameStore,
         civilizationStore: CivilizationAssignmentStore, matchSetupStore: MatchSetupStore,
         gameLogStore: GameLogStore, gameStatsStore: GameStatsStore, ghostStore: GhostStore = .shared,
         ratingStore: RatingStore = .shared) {
        self.checkpointStore = checkpointStore
        self.gameStore = gameStore
        self.civilizationStore = civilizationStore
        self.matchSetupStore = matchSetupStore
        let humanSeatStore = HumanSeatStore(defaults: matchSetupStore.defaults)
        self.humanSeatStore = humanSeatStore
        self.gameLogStore = gameLogStore
        self.gameStatsStore = gameStatsStore
        self.ghostStore = ghostStore
        self.ratingStore = ratingStore
        newGameSetupLoadResult = matchSetupStore.load()
        persistenceErrorMessage = nil
        gameLogWarningState = nil
        let initialState = GameSetup.newGame(board: BoardGenerator.standard())
        let seat = PlayerID(index: 0)
        let assignment = Array(Civilization.allCases.prefix(initialState.players.count))
        CivilizationAssignment.current = assignment
        CivilizationAssignment.humanSeat = seat
        // Hot-seat composition, if the game being resumed recorded one.
        // `HumanSeatStore` holds a single seat and cannot express "people in
        // seats 0 and 2", so on its own it turned every human seat but the
        // lowest into a bot on the next launch, and lost their names.
        let preferredName = PlayerNameStore.shared.load()
        let humanNames = [seat: preferredName.isEmpty ? "You" : preferredName]
        CivilizationAssignment.humanNames = humanNames
        // `@Observable` requires every stored property assigned before
        // `self` (including `self.state`) can be read - `GameLogStore`
        // reads `initialState` (the local), never `self.state`, to stay
        // fully assign-before-read through this initializer.
        let profiles = Self.opponentProfiles(
            for: initialState, humanSeats: [seat],
            civilizations: assignment
        )
        // The placeholder table built before a saved match is restored.
        // Whatever is restored replaces this session along with its own
        // difficulty, so this one only has to be a legal table.
        session = Self.makeSession(
            state: initialState, opponentProfiles: profiles, difficulty: .default, ghosts: ghostStore
        )
        playerRoster = PlayerRoster(
            playerIDs: initialState.players.map(\.id), humanSeats: [seat],
            humanNames: humanNames, civilizations: assignment,
            opponentProfiles: profiles
        )
        // Nobody is holding a force-quit phone, so a hot-seat game resumes
        // behind the handoff cover rather than showing whoever's hand happens
        // to be up. A solo game has nobody to pass to and claims immediately.
        seatAtDevice = seat
        self.saveWasUnreadable = false
        loadCheckpointAuthority()
    }

    /// Starts a fresh game, discarding whatever `state` currently holds.
    /// `randomizeSeat` picks a random seat (0-3) for the human instead of
    /// always seat 0 - covers both draft order and regular turn order,
    /// since both are driven by the same seat rotation in this engine.
    public func startNewGame(randomizedBoard: Bool, randomizeSeat: Bool) {
        let settings = CivilizationSettingsStore.shared.load()
        var setup = MatchSetup.default(preferredName: PlayerNameStore.shared.load().isEmpty
            ? "You" : PlayerNameStore.shared.load(), preferredCivilization: settings.yourCivilization)
        setup.randomizedBoard = randomizedBoard
        setup.randomizeSeatOrder = randomizeSeat
        startNewGame(setup: setup)
    }

    /// Starts a game from a full `MatchSetup` - the New Game screen's output.
    ///
    /// The two-flag compatibility entry point constructs a setup and enters
    /// this same checkpoint transaction.
    public func startNewGame(setup: MatchSetup) {
        startNewGame(setup: setup, configuredAs: setup)
    }

    func startNewGame(setup: MatchSetup, configuredAs prefill: MatchSetup) {
        // `isValidMatch`, not `isStartable`: the two differ by what the New Game
        // *screen* currently offers, and narrowing that (four seats, one target
        // per mode) left legitimate matches - a restarted legacy Epic save, a
        // test fixture - dying on an assertion instead of playing.
        // `MatchSetup.matchProblem` documents that line; the screen still checks
        // `isStartable` before calling.
        precondition(setup.isValidMatch, "refusing to start an incoherent match: \(setup.matchProblem ?? "")")
        let match = Self.prepareMatch(from: setup)
        let profiles = match.opponentProfiles.merging(
            Self.ghostOpponentProfiles(chairs: match.chairs, civilizations: match.civilizations, store: ghostStore)
        ) { _, ghost in ghost }
        do {
            let realized = Self.realisedMatch(chairs: match.chairs, civilizations: match.civilizations,
                                             opponentProfiles: profiles, from: setup)
            let candidate = Self.makeSession(
                state: match.state, opponentProfiles: profiles,
                difficulty: setup.difficulty, ghosts: ghostStore
            )
            try replaceActiveMatch(state: match.state, setup: realized, session: candidate)
            resetPerGameState()
            try installCheckpointMatch()
            do {
                try matchSetupStore.save(prefill)
                newGameSetupLoadResult = .loaded(prefill)
            } catch {
                gameLogWarning = "The next-game preferences could not be saved: \(error.localizedDescription)"
            }
            exportCommittedRecordings()
        } catch {
            persistenceErrorMessage = "The new game could not be saved. Your previous game was not replaced: \(error.localizedDescription)"
        }
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
        let shape = Ruleset.forMode(setup.mode).board
        let board = setup.randomizedBoard
            ? BoardGenerator.randomized(seed: UInt64.random(in: .min ... .max), shape: shape)
            : BoardGenerator.standard(shape)
        return GameSetup.newGame(board: board, seed: UInt64.random(in: .min ... .max), playerCount: playerCount,
                                 victoryPointTarget: setup.victoryPointTarget, mode: setup.mode, variant: setup.variant)
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

    public func dismissPersistenceError() {
        persistenceErrorMessage = nil
    }

    public func clearCompletedMatch() -> Bool {
        guard savedGameAvailability.recoveryMessage == nil,
              case .gameOver = state.phase, let document = checkpointDocument else { return false }
        do {
            try commitDocument(document.replacingActiveMatch(with: nil))
            resetPerGameState()
            activeSince = nil
            savedGameAvailability = .absent
            exportCommittedRecordings()
            return true
        } catch {
            persistenceErrorMessage = "The finished game could not be cleared. Please try again."
            return false
        }
    }

    /// The configured seats renumbered into the chairs they were dealt, with
    /// every civilization now decided - the record a resumed game reads.
    /// ## Copy the setup and replace the seats; never rebuild it field by field
    /// This listed `mode`, `victoryPointTarget`, `randomizedBoard` and
    /// `randomizeSeatOrder` by hand, so the realized record silently lost any
    /// field added to `MatchSetup` afterwards. `difficulty` was the first, and
    /// the failure was not a missing setting - it was **"the new game could
    /// not be saved"** on every Expert match. The session was built with
    /// `EvaluationPolicy`, the realized setup was written claiming Classic,
    /// and `installCheckpointMatch` restores through `makePolicies` to check
    /// its own work: the policy IDs disagreed and `GameSession.init(checkpoint:)`
    /// threw `incompatibleCheckpoint`.
    ///
    /// Copying makes the next added field correct without anyone remembering
    /// this. Only the seats are realized here; nothing else about the match
    /// changes when chairs are dealt.
    static func realisedMatch(chairs: [MatchSetup.Seat],
                              civilizations: [Civilization],
                              opponentProfiles: [PlayerID: OpponentProfile],
                              from setup: MatchSetup) -> MatchSetup {
        var realized = setup
        realized.seats = chairs.enumerated().map { chair, configured in
            MatchSetup.Seat(index: chair,
                            isHuman: configured.isHuman,
                            name: configured.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            civilization: civilizations[chair],
                            opponentProfile: opponentProfiles[PlayerID(index: chair)],
                            ghostID: configured.ghostID)
        }
        return realized
    }

    /// Restart the realized table, keeping the configured next-game prefill
    /// separate. No roster or identity is read from legacy sidecar authority.
    public func restartCurrentMatch(fallbackRandomizedBoard: Bool, fallbackRandomizeSeat: Bool) {
        guard var active = checkpointDocument?.activeMatch?.setup else {
            startNewGame(randomizedBoard: fallbackRandomizedBoard, randomizeSeat: fallbackRandomizeSeat)
            return
        }
        active.randomizeSeatOrder = false
        // A legacy checkpoint may remain resumable even after its exact rules
        // combination stops being offered for new matches. Restart creates a
        // new match, so normalize it through today's New Game contract instead
        // of trapping on `isStartable` or recreating an unwinnable table.
        active.normalizeNewGameOptions()
        var prefill = matchSetupStore.load().value ?? active
        prefill.normalizeNewGameOptions()
        startNewGame(setup: active, configuredAs: prefill)
    }

    /// Personal totals belong only to solo games; durable completion accounting
    /// lives in MatchCheckpointDocument, not in the log exporter or this view.
    var shouldRecordLifetimeStatistics: Bool { humanSeats.count == 1 }

    /// The bookkeeping every new game clears, whichever entry point started it.
    private func resetPerGameState() {
        gameGeneration &+= 1
        resetDiscardPresentation()
        boardDecisionCoordinator.clear()
        pendingTradeConfirmation = nil
        pendingDevCardReveal = nil
        pendingDevCardResolution = nil
        lastTradeOutcome = nil
        eventBatch = EventBatch(sequence: eventBatch.sequence + 1, events: [])
        accumulatedActiveDuration = 0
        activeSince = Date()
    }

    /// Human and automatic trade responses use the same candidate-session
    /// commit as policy moves. Neither events nor UI state escape before disk.
    private func applyLogged(_ move: GameMove, by player: PlayerID) throws {
        if let message = savedGameAvailability.recoveryMessage { throw SavedGameRecoveryError.blocked(message) }
        var candidate = session
        let step = try candidate.applyExternal(move, by: player)
        try commitStep(step, candidate: candidate)
    }

    private func commitStep(_ step: GameSession.Step, candidate: GameSession) throws {
        guard let document = checkpointDocument, document.activeMatch != nil else {
            throw SavedGameRecoveryError.blocked("Start a game before making a move.")
        }
        let next: MatchCheckpointDocument
        do {
            next = try document.recording(step, session: candidate.checkpoint,
                                           elapsedSeconds: currentGameDuration)
            try commitDocument(next)
        } catch let failure as MatchPersistenceFailure {
            throw failure
        } catch {
            throw reportPersistenceFailure(error)
        }
        session = candidate
        reconcileBoardDecision()
        pendingEvents += step.events
        eventBatch = EventBatch(sequence: eventBatch.sequence + 1, events: pendingEvents)
        pendingDevCardReveal = next.pendingDevCardReveal
        pendingDevCardResolution = next.pendingDevCardResolution
        if case .gameOver = state.phase {
            accumulatedActiveDuration = next.activeMatch?.elapsedSeconds ?? currentGameDuration
            activeSince = nil
            if let finished = next.activeMatch { lastFinishedMatchWork = recordFinishedMatch(finished) }
        }
        exportCommittedRecordings(after: step.move, in: next)
    }

    public func dismissGameLogWarning() { gameLogWarningState = nil }

    /// Dismisses only the private presentation; the bought card is already in
    /// the durable game checkpoint and is intentionally untouched.
    @discardableResult
    public func dismissDevCardReveal() -> Bool {
        guard let document = checkpointDocument else { return false }
        do {
            try commitDocument(document.dismissingDevCardReveal())
            pendingDevCardReveal = nil
            return true
        } catch {
            _ = reportPersistenceFailure(error)
            return false
        }
    }

    /// Acknowledges only the presentation receipt. The card's rule effects
    /// are already committed and remain untouched.
    @discardableResult
    public func dismissDevCardResolution() -> Bool {
        guard let document = checkpointDocument else { return false }
        do {
            try commitDocument(document.dismissingDevCardResolution())
            pendingDevCardResolution = nil
            return true
        } catch {
            _ = reportPersistenceFailure(error)
            return false
        }
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

    /// Commit the human's move before publishing it or starting any bots.
    /// Engine rejection and durable-write failure are distinct caller errors.
    public func apply(_ move: GameMove) throws {
        try commitHumanMove(move)
        if case .discard = move { resetDiscardPresentation() }
        Task { await runBotTurnIfNeeded() }
    }

    /// The synchronous half of `apply`. Keeping scheduling outside this method
    /// gives deterministic QA one bot runner to await instead of racing the
    /// production fire-and-forget task against a second call to the loop.
    private func commitHumanMove(_ move: GameMove) throws {
        if let message = savedGameAvailability.recoveryMessage {
            throw SavedGameRecoveryError.blocked(message)
        }
        guard pendingDevCardReveal == nil, pendingDevCardResolution == nil else {
            throw MoveError.other("Review the development card before continuing.")
        }
        beginEventBatch()
        // A bot negotiation belongs to the turn that started it. Left standing
        // across `endTurn`, the next player's Trade screen opened on the
        // previous player's banner - which REPLACES the builder, so they could
        // not compose a trade until they declined somebody else's offer, which
        // then failed with `.offerNoLongerAvailable` because `RulesEngine`
        // drops pending offers at `endTurn` anyway.
        try applyLogged(move, by: humanPlayer)
        if case .endTurn = move {
            pendingTradeConfirmation = nil
            lastTradeOutcome = nil
        }
        if case .proposeTrade(let offer) = move, offer.from == humanPlayer {
            try resolveHumanProposedTrade(offer)
        }
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
        seatAtDevice = seats.sorted().first
        // Do not read the process-global assignment here. Swift Testing runs
        // test functions concurrently, and another fixture may be exercising
        // a three-seat table while this one installs four seats. The old
        // helper did not need the mapping; profiles do, so give tests their
        // own deterministic complete assignment.
        let civilizations = Array(Civilization.allCases.prefix(newState.players.count))
        CivilizationAssignment.current = civilizations
        let profiles = Self.opponentProfiles(
            for: newState, humanSeats: seats, civilizations: civilizations
        )
        let names = Dictionary(uniqueKeysWithValues: seats.map {
            ($0, "Player \($0.index + 1)")
        })
        playerRoster = PlayerRoster(
            playerIDs: newState.players.map(\.id), humanSeats: seats,
            humanNames: names, civilizations: civilizations,
            opponentProfiles: profiles
        )
        CivilizationAssignment.humanNames = names
        session = Self.makeSession(
            state: newState, opponentProfiles: profiles, difficulty: .default, ghosts: ghostStore
        )
        resetDiscardPresentation()
        persistTestingPosition()
        reconcileBoardDecision()
    }

    /// Forces `state.phase` straight to a human win, for screenshotting
    /// `EndGameView` (see `QALaunchFlag.showEndGame`) without playing a game
    /// out to 10 VP. Deliberately records no log entry and no stats.
    func qaForceHumanWin() {
        var forced = session.state
        forced.phase = .gameOver(winner: humanPlayer)
        session.replace(state: forced)
        persistTestingPosition()
    }

    /// Plays through production session, log, stats, and save bookkeeping without UI delays.
    func qaPlayToEnd() {
        var humanRNG = RandomSource(seed: 12345)
        for _ in 0..<10_000 {
            if case .gameOver = state.phase { return }
            do {
                var candidate = session
                let step: GameSession.Step
                if case .awaitingExternalSeat(let seat) = candidate.nextActor() {
                    let observation = GameObservation(seat: seat, state: state,
                        legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
                    let move = HeuristicPolicy(personality: .balanced, id: "qa-human").decide(observation, rng: &humanRNG)
                    step = try candidate.applyExternal(move, by: seat)
                } else {
                    guard let (seat, move) = candidate.decideNext() else {
                        preconditionFailure("QA complete match stopped before game over")
                    }
                    step = try candidate.commit(seat: seat, move: move)
                }
                beginEventBatch()
                try commitStep(step, candidate: candidate)
                // This fixture owns every chair and has no person available to
                // tap the private acknowledgement surfaces. Explicitly model
                // those taps so receipts are cleared through the same durable
                // APIs as production, rather than silently overwriting them.
                if pendingDevCardReveal != nil, !dismissDevCardReveal() {
                    preconditionFailure("QA complete match could not acknowledge a card purchase")
                }
                if pendingDevCardResolution != nil, !dismissDevCardResolution() {
                    preconditionFailure("QA complete match could not acknowledge a card result")
                }
            } catch {
                preconditionFailure("QA complete match failed: \(error)")
            }
        }
        preconditionFailure("QA complete match exceeded 10,000 moves")
    }

    /// QA positions are explicit new replay baselines, never unrecorded edits
    /// to a production history. Real bot policy identities stay unchanged.
    private func persistTestingPosition() {
        let chairs = state.players.map { player in
            let identity = playerIdentity(for: player.id)
            return MatchSetup.Seat(index: player.id.index, isHuman: humanSeats.contains(player.id),
                name: humanSeats.contains(player.id) ? identity.displayName : "",
                civilization: identity.civilization,
                opponentProfile: opponentProfiles[player.id])
        }
        let setup = MatchSetup(seats: chairs, mode: state.mode, victoryPointTarget: state.victoryPointTarget,
                               randomizedBoard: false, randomizeSeatOrder: false)
        do {
            try replaceActiveMatch(state: state, setup: setup, session: session)
            accumulatedActiveDuration = 0
            activeSince = Date()
            savedGameAvailability = .playable
            saveWasUnreadable = false
        } catch { preconditionFailure("Could not persist QA position: \(error)") }
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
        let empire = playerIdentity(for: bot).civilization.tradeMessagesEmpire
        return TradeMessages.response(offer: TradeOffer(id: offerID, from: bot, give: [:], want: [:]), empire: empire, accepted: accepted)
    }

    private func resolveHumanProposedTrade(_ offer: TradeOffer) throws {
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
            let accepts = policyAcceptsHumanTrade(offer, responder: bot)
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
                try applyLogged(.respondToTrade(offerID: offer.id, accept: false), by: anyBot)
            }
            lastTradeOutcome = TradeOutcome(decisions: decisions, acceptedBy: nil)
        }
    }

    /// The pending offer is authoritative; presentation can be reconstructed
    /// without sampling policies or touching the board on a cold resume.
    func restorePendingNegotiation() {
        pendingTradeConfirmation = nil
        lastTradeOutcome = nil
        // Winning can leave an offer in the checkpoint, but policies cannot act after a win.
        if case .gameOver = state.phase { return }
        guard let offer = state.pendingTradeOffers.first(where: { $0.from == humanPlayer }) else { return }
        let decisions = state.players.map(\.id).filter { !humanSeats.contains($0) }.map { bot in
            let accepts = Trading.bothSidesCanHonour(offer, responder: bot, state: state)
                && policyAcceptsHumanTrade(offer, responder: bot)
            return (bot: bot, accepted: accepts, message: tradeResponseMessage(for: bot, offerID: offer.id, accepted: accepts))
        }
        if let bot = decisions.first(where: \.accepted)?.bot {
            pendingTradeConfirmation = PendingTradeConfirmation(offerID: offer.id, selectedBot: bot, decisions: decisions)
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
        case persistenceFailed
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
        guard state.pendingTradeOffers.contains(where: { $0.id == pending.offerID }) else {
            pendingTradeConfirmation = nil
            lastTradeOutcome = nil
            return .offerNoLongerAvailable
        }
        do {
            try applyLogged(.respondToTrade(offerID: pending.offerID, accept: true), by: pending.selectedBot)
        } catch is MatchPersistenceFailure {
            return .persistenceFailed
        } catch {
            // Withdraw the now-stuck offer on the willing bot's behalf
            // rather than leaving it pending forever with nothing left to
            // confirm it with - same "reject" applied `declinePendingTrade`
            // uses.
            do {
                try applyLogged(.respondToTrade(offerID: pending.offerID, accept: false), by: pending.selectedBot)
            } catch {
                return .persistenceFailed
            }
            pendingTradeConfirmation = nil
            lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: nil)
            return .resourcesNoLongerAvailable
        }
        pendingTradeConfirmation = nil
        lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: pending.selectedBot)
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
        guard state.pendingTradeOffers.contains(where: { $0.id == pending.offerID }) else {
            pendingTradeConfirmation = nil
            return
        }
        do {
            try applyLogged(.respondToTrade(offerID: pending.offerID, accept: false), by: pending.selectedBot)
            pendingTradeConfirmation = nil
            lastTradeOutcome = TradeOutcome(decisions: pending.decisions, acceptedBy: nil)
        } catch {
            persistenceErrorMessage = error.localizedDescription
        }
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

    /// When the last bot action was shown - the deadline
    /// `waitForNextBotAction` paces against. Cleared whenever the bot loop
    /// stops, so the first action after any pause still waits in full.
    var lastBotActionAt: Date?

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
    private var pendingEvents: [GameEvent] = []

    private func beginEventBatch() {
        pendingEvents = []
    }

    /// Compatibility signal for the launch alert: either game data or its
    /// player setup failed restoration. Recovery status holds the explanation.
    public internal(set) var saveWasUnreadable = false

    /// True while a blocking reading/decision surface is on screen. The bot
    /// loop stops for settings and the development-card hand so the board,
    /// bank and card status cannot change underneath what the player is
    /// reading. Private receipts have their own durable gates as well.
    ///
    /// Written by `GameView`, which mirrors its own presentation state here.
    public var isBlockingSurfaceOpen = false

    public func runBotTurnIfNeeded() async {
        guard savedGameAvailability.canResume, appIsActive, !persistenceBlocked, !isProcessingBotTurns else { return }
        isProcessingBotTurns = true
        let generation = gameGeneration
        defer {
            isProcessingBotTurns = false
            lastBotActionAt = nil
            if generation != gameGeneration, savedGameAvailability.canResume, !persistenceBlocked {
                Task { await runBotTurnIfNeeded() }
            }
        }

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
            if openIncomingOffer != nil || pendingDevCardReveal != nil
                || pendingDevCardResolution != nil { return }

            // Same `return`-don't-park reasoning as the offer check above:
            // parking here would hold `isProcessingBotTurns` for as long as
            // the surface stayed open, and `GameView` restarts the loop when
            // the final blocking surface closes.
            if isBlockingSurfaceOpen { return }

            // Pacing, not thinking: the bots decide instantly and this is the
            // only reason a turn is watchable. See `waitForNextBotAction`.
            await waitForNextBotAction()
            // The game may have been restarted while this loop slept.
            guard generation == gameGeneration, appIsActive, !Task.isCancelled,
                  !isBlockingSurfaceOpen, openIncomingOffer == nil,
                  pendingDevCardReveal == nil, pendingDevCardResolution == nil else { return }

            let revision = checkpointDocument?.revision
            var candidate = session
            guard let (seat, move) = candidate.decideNext() else { break }
            guard generation == gameGeneration, appIsActive, !Task.isCancelled, !persistenceBlocked,
                  !isBlockingSurfaceOpen, openIncomingOffer == nil,
                  pendingDevCardReveal == nil, pendingDevCardResolution == nil else { return }
            guard revision == checkpointDocument?.revision else { continue }
            do {
                let step = try candidate.commit(seat: seat, move: move)
                beginEventBatch()
                try commitStep(step, candidate: candidate)
                lastBotActionAt = Date()
            } catch is MatchPersistenceFailure {
                return
            } catch {
                // A policy chose a move the rules reject: the two disagree,
                // which is a bug rather than a position to recover from. It was
                // previously a bare `try?`, so the loop simply stopped and the
                // game sat frozen on a bot's turn with nothing said. The
                // rejected candidate never replaces the committed policy RNG.
                assertionFailure("bot \(seat.index) played an illegal \(move): \(error)")
                break
            }
        }
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

public extension GameViewModel {
    /// Reconcile uncertain writes without replaying the failed action blindly.
    @discardableResult
    func retryPersistence() -> Bool {
        do {
            // This is an in-process recovery, not a cold launch: the same
            // person is still holding the phone. `installCheckpointMatch()`
            // clears hot-seat claims for cold resume, so restore a valid one
            // before reconciling its uncommitted discard draft.
            let claimedSeat = seatAtDevice
            let retainedBoardDecision = boardDecisionCoordinator
            guard let document = try checkpointStore.load() else {
                throw SavedGameRecoveryError.blocked(
                    "The checkpoint is missing. The original files have not been changed."
                )
            }
            checkpointDocument = document
            try installCheckpointMatch()
            if let claimedSeat, humanSeats.contains(claimedSeat) { seatAtDevice = claimedSeat }
            boardDecisionCoordinator = retainedBoardDecision
            reconcileBoardDecision()
            gameGeneration &+= 1
            eventBatch = EventBatch(sequence: eventBatch.sequence + 1, events: [])
            prepareDiscardPresentation()
            persistenceErrorMessage = nil
            return true
        } catch {
            _ = reportPersistenceFailure(error)
            return false
        }
    }

    /// Human seats in a stable order.
    ///
    /// Sorted, always. `Set` iteration order is seeded per process in Swift, so
    /// anything derived from it that reaches a decision differs between
    /// launches - this repo has been bitten by that four separate times.
    var sortedHumanSeats: [PlayerID] { humanSeats.sorted() }

    /// Whether any seat is played by a bot.
    ///
    /// An all-human table is a supported configuration (spec A1.4), and in one
    /// the player-trade path has nobody to answer it. The trade UI asks this
    /// rather than offering a button that cannot work.
    var hasBotSeats: Bool { humanSeats.count < state.players.count }
}
