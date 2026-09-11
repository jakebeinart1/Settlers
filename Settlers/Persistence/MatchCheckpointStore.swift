import Foundation
import CatanEngine

/// A `validateHistory()`-only comparison, deliberately narrower than
/// `GameState`'s own synthesized `==`.
///
/// `validateHistory()` replays a match's recorded moves through the CURRENT
/// `RulesEngine.apply` and compares the result against the persisted `state`
/// snapshot. That snapshot was captured incrementally, move by move, by
/// WHATEVER version of the engine was running at the time it was saved. For
/// any save whose history includes a `.respondToTrade(_, false)` recorded
/// before `Trading.respond` started appending to
/// `GameState.declinedTradeOffersThisTurn`, replaying that same history under
/// the current engine legitimately populates the field for the current turn,
/// while the persisted snapshot - written by the old code, which never
/// touched it - has it empty. `replay == state` would then fail for a save
/// that is, in every rule/RNG/win-condition sense that matters, perfectly
/// valid, and `validateHistory()` would mark the whole document blocked. This
/// is the incident `CLAUDE.md` already documents happening once
/// (`tradesAcceptedThisTurn`) and warns against repeating - reached here via
/// the app-target replay validator, which no package-level test can see.
///
/// The fix is not to loosen `GameState.Equatable` itself - other code
/// (determinism tests among them) may depend on its current strictness, and
/// this is the only call site with a reason to differ. Every field `==`
/// checks is checked here too, in the same list order as the struct
/// declaration, EXCEPT `declinedTradeOffersThisTurn`: turn-scoped AI
/// bookkeeping with no bearing on move legality, win conditions, or the RNG
/// position - unlike, say, `rng` or `board`, which `validateHistory`'s own
/// doc comment calls out by name as exactly what exact equality here needs to
/// keep certifying. Add a case here, not to `GameState.==`, for the next
/// field that turns out to have the same shape (turn-scoped, save-invisible
/// bookkeeping recorded only from the moment a feature shipped).
extension GameState {
    func matchesForReplayValidationExcludingDeclinedTradeHistory(_ other: GameState) -> Bool {
        schemaVersion == other.schemaVersion
            && mode == other.mode
            && victoryPointTarget == other.victoryPointTarget
            && rng == other.rng
            && board == other.board
            && players == other.players
            && phase == other.phase
            && bank == other.bank
            && devCardDeck == other.devCardDeck
            && lastDiceRoll == other.lastDiceRoll
            && longestRoadPlayer == other.longestRoadPlayer
            && largestArmyPlayer == other.largestArmyPlayer
            && pendingTradeOffers == other.pendingTradeOffers
            && robberMoverIndex == other.robberMoverIndex
            && devCardsBoughtThisTurn == other.devCardsBoughtThisTurn
            && devCardPlayedThisTurn == other.devCardPlayedThisTurn
            && tradesAcceptedThisTurn == other.tradesAcceptedThisTurn
        // declinedTradeOffersThisTurn deliberately excluded - see the doc
        // comment above.
    }
}

/// One match's state and its replay source travel in the same atomic write.
/// App identity stays outside GameState because it is not a game rule.
struct MatchCheckpoint: Codable, Equatable, Sendable {
    struct RecordedMove: Codable, Equatable, Sendable {
        let actor: PlayerID
        let move: GameMove
        let timestamp: Date
        /// The rules behavior under which this move was originally accepted.
        /// Missing means version 1 because checkpoints shipped before this
        /// field existed; every new move writes the current version explicitly.
        let rulesVersion: Int

        init(
            actor: PlayerID,
            move: GameMove,
            timestamp: Date,
            rulesVersion: Int = RulesEngine.currentRulesVersion
        ) {
            self.actor = actor
            self.move = move
            self.timestamp = timestamp
            self.rulesVersion = rulesVersion
        }

        private enum CodingKeys: String, CodingKey {
            case actor, move, timestamp, rulesVersion
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            actor = try values.decode(PlayerID.self, forKey: .actor)
            move = try values.decode(GameMove.self, forKey: .move)
            timestamp = try values.decode(Date.self, forKey: .timestamp)
            rulesVersion = try values.decodeIfPresent(Int.self, forKey: .rulesVersion)
                ?? RulesEngine.oldestSupportedRulesVersion
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(actor, forKey: .actor)
            try values.encode(move, forKey: .move)
            try values.encode(timestamp, forKey: .timestamp)
            try values.encode(rulesVersion, forKey: .rulesVersion)
        }
    }

    let id: UUID
    let startedAt: Date
    let initialState: GameState
    let setup: MatchSetup
    private(set) var state: GameState
    private(set) var moves: [RecordedMove] = []
    private(set) var elapsedSeconds: TimeInterval = 0
    private(set) var sessionCheckpoint: GameSession.Checkpoint?

    init(id: UUID, initialState: GameState, setup: MatchSetup, startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.initialState = initialState
        self.state = initialState
        self.setup = setup
    }

    mutating func apply(
        _ move: GameMove,
        by actor: PlayerID,
        timestamp: Date = Date(),
        rulesVersion: Int = RulesEngine.currentRulesVersion
    ) throws {
        var candidate = state
        try RulesEngine.replay(move, by: actor, rulesVersion: rulesVersion, to: &candidate)
        state = candidate
        moves.append(RecordedMove(
            actor: actor,
            move: move,
            timestamp: timestamp,
            rulesVersion: rulesVersion
        ))
        sessionCheckpoint = nil
    }

    mutating func attachSession(_ checkpoint: GameSession.Checkpoint) throws {
        guard checkpoint.state == state else { throw MatchCheckpointStore.StoreError.inconsistentHistory }
        sessionCheckpoint = checkpoint
    }

    mutating func recordElapsedTime(_ seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds >= elapsedSeconds else {
            throw MatchCheckpointStore.StoreError.invalidDuration
        }
        elapsedSeconds = seconds
    }

    /// The engine, not a duplicated move interpreter, validates the history,
    /// private presentation receipts, and saved RNG position in one replay.
    /// Separate receipt replays made each durable move repeat an already
    /// expensive full-history traversal and pushed complete-match tests past
    /// the native runner's execution timeout.
    ///
    /// Uses `matchesForReplayValidationExcludingDeclinedTradeHistory`, not
    /// `==`, for the reason documented on that function: a save recorded
    /// before this repo's creative-bot-trade-offers work started populating
    /// `GameState.declinedTradeOffersThisTurn` would otherwise fail replay
    /// under the new rules and get its whole document marked blocked - the
    /// exact incident class `CLAUDE.md` already warns about ("Adding one
    /// field once deleted every player's in-progress save").
    func validateHistory(
        pendingReveal: DevCardReveal? = nil,
        pendingResolution: DevCardResolution? = nil
    ) throws {
        try validateSetup()
        var replay = initialState
        var revealWasRecorded = pendingReveal == nil
        var resolutionWasRecorded = pendingResolution == nil
        for (index, entry) in moves.enumerated() {
            let drawn = entry.move == .buyDevCard ? replay.devCardDeck.first : nil
            let events = try RulesEngine.replay(
                entry.move,
                by: entry.actor,
                rulesVersion: entry.rulesVersion,
                to: &replay
            )
            let isReceiptSource = index == moves.indices.last
            if isReceiptSource, let pendingReveal, entry.actor == pendingReveal.owner,
               drawn == pendingReveal.card {
                revealWasRecorded = true
            }
            if isReceiptSource, let pendingResolution, entry.actor == pendingResolution.owner,
               events.contains(where: {
                   MatchCheckpointDocument.devCardResolution($0) == pendingResolution
               }) {
                resolutionWasRecorded = true
            }
        }
        guard revealWasRecorded, resolutionWasRecorded,
              replay.matchesForReplayValidationExcludingDeclinedTradeHistory(state) else {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
        if let sessionCheckpoint, sessionCheckpoint.state != state {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
        try sessionCheckpoint?.validate()
    }

    /// Whether this checkpoint is `previous` with zero or more moves appended:
    /// same match identity, same starting position, same roster, and an
    /// unchanged move prefix. Nothing here replays anything - it establishes
    /// that `previous`'s already-validated state is a legitimate starting
    /// point for validating only what is new.
    func isExtending(_ previous: MatchCheckpoint) -> Bool {
        id == previous.id && startedAt == previous.startedAt
            && setup == previous.setup && initialState == previous.initialState
            && moves.count >= previous.moves.count
            && moves.prefix(previous.moves.count).elementsEqual(previous.moves)
    }

    /// `validateHistory()` restricted to the moves `previous` did not have.
    ///
    /// The full replay is O(history) and ran on **every** committed move,
    /// which is what made a 25-point game slow down as it went: measured over
    /// one 770-move Expanded match, a committed move cost 36ms early and
    /// 395ms late, with three full-history replays inside it (this one, the
    /// one `load()` performed on the document it read, and `GameLogStore`'s
    /// before each export). The property being certified is inductive - if
    /// `previous` replayed to `previous.state`, and the appended moves replay
    /// from there to `state`, then the whole history replays to `state` - so
    /// the prefix does not have to be replayed again to know it still holds.
    /// It was validated when it was committed, and `isExtending` is what
    /// establishes that this is the same prefix.
    ///
    /// The full replay remains on every cold path, where it is the real
    /// check: `load()`, resume, recovery, migration and export all still
    /// re-derive the entire game from `initialState`, so a checkpoint that
    /// was corrupted on disk or written by an older engine is caught before
    /// anything is played on it.
    func validateHistory(
        succeeding previous: MatchCheckpoint,
        pendingReveal: DevCardReveal? = nil,
        pendingResolution: DevCardResolution? = nil
    ) throws {
        try validateSetup()
        var replay = previous.state
        var revealWasRecorded = pendingReveal == nil
        var resolutionWasRecorded = pendingResolution == nil
        for index in previous.moves.count..<moves.count {
            let entry = moves[index]
            let drawn = entry.move == .buyDevCard ? replay.devCardDeck.first : nil
            let events = try RulesEngine.replay(
                entry.move,
                by: entry.actor,
                rulesVersion: entry.rulesVersion,
                to: &replay
            )
            let isReceiptSource = index == moves.indices.last
            if isReceiptSource, let pendingReveal, entry.actor == pendingReveal.owner,
               drawn == pendingReveal.card {
                revealWasRecorded = true
            }
            if isReceiptSource, let pendingResolution, entry.actor == pendingResolution.owner,
               events.contains(where: {
                   MatchCheckpointDocument.devCardResolution($0) == pendingResolution
               }) {
                resolutionWasRecorded = true
            }
        }
        guard revealWasRecorded, resolutionWasRecorded,
              replay.matchesForReplayValidationExcludingDeclinedTradeHistory(state) else {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
        if let sessionCheckpoint, sessionCheckpoint.state != state {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
        try sessionCheckpoint?.validate()
    }

    /// The app roster and the engine state are one checkpoint generation.
    /// Reject disagreement rather than restoring names or rules for a
    /// different table onto an otherwise replayable board.
    private func validateSetup() throws {
        guard setup.isValidMatch,
              setup.seats.count == state.players.count,
              setup.seats.count == initialState.players.count,
              setup.mode == state.mode,
              setup.mode == initialState.mode,
              setup.victoryPointTarget == state.victoryPointTarget,
              setup.victoryPointTarget == initialState.victoryPointTarget,
              state.players.map(\.id.index).elementsEqual(setup.seats.indices),
              initialState.players.map(\.id.index).elementsEqual(setup.seats.indices) else {
            throw MatchCheckpointStore.StoreError.invalidSetup
        }
    }
}

/// Versioned production authority for match state, history, accounting, and
/// retryable exports. Loading validates the complete document before use.
struct MatchCheckpointDocument: Codable, Equatable, Sendable {
    struct Completion: Codable, Equatable, Sendable {
        let winner: PlayerID
        let humanSeat: PlayerID?
        let finalVP: Int
        let duration: TimeInterval
    }

    static let currentSchemaVersion = 1
    let schemaVersion: Int
    private(set) var revision: Int
    private(set) var activeMatch: MatchCheckpoint?
    private(set) var statistics = GameStats()
    private(set) var completions: [UUID: Completion] = [:]
    private(set) var pendingExports: [UUID: MatchCheckpoint] = [:]
    /// Buyer-private presentation receipt. Optional decoding keeps documents
    /// written before the reveal journey backward compatible.
    private(set) var pendingDevCardReveal: DevCardReveal?
    /// Acknowledgement owed after a human card resolves. Keeping it in the
    /// checkpoint prevents a successful effect from becoming invisible if the
    /// process stops between the game commit and the result card rendering.
    private(set) var pendingDevCardResolution: DevCardResolution?

    init(activeMatch: MatchCheckpoint?, revision: Int = 0) {
        self.schemaVersion = Self.currentSchemaVersion
        self.revision = revision
        self.activeMatch = activeMatch
    }

    /// A player can have historical totals without an unfinished game.
    /// Creating the new authority must preserve that baseline too.
    init(legacyStatistics: GameStats) {
        self.init(activeMatch: nil)
        statistics = legacyStatistics
    }

    /// Recovery may salvage independently valid accounting/export state from
    /// a decodable document whose active match metadata is unusable.
    init(recovering document: Self, activeMatch: MatchCheckpoint) throws {
        self.init(activeMatch: activeMatch)
        statistics = document.statistics
        completions = document.completions
        pendingExports = document.pendingExports
        try validateAuthority()
    }

    /// Legacy totals cannot reveal whether a terminal save was already counted.
    /// Preserve them exactly, and mark that save handled rather than guessing
    /// an extra increment. The migration revision is still the initial commit.
    init(migratedMatch: MatchCheckpoint, legacyStatistics: GameStats) throws {
        self.init(activeMatch: migratedMatch)
        if case .gameOver = migratedMatch.state.phase {
            try recordCompletion(duration: migratedMatch.elapsedSeconds)
        }
        statistics = legacyStatistics
        revision = 0
    }

    /// Build an unpublished candidate. The caller commits it before exposing
    /// its state; failures leave this document unchanged. A winning move and
    /// its accounting receipt belong to the same revision.
    func applying(_ move: GameMove, by actor: PlayerID, elapsedSeconds: TimeInterval) throws -> Self {
        guard var match = activeMatch, revision < Int.max else {
            throw MatchCheckpointStore.StoreError.staleRevision
        }
        try match.recordElapsedTime(elapsedSeconds)
        try match.apply(move, by: actor)
        var next = self
        next.activeMatch = match
        if case .gameOver = match.state.phase { try next.recordCompletion(duration: elapsedSeconds) }
        next.revision = revision + 1
        return next
    }

    /// Persist the actual candidate session's bookkeeping after its move.
    /// Replay verifies the step agrees with that session before either reaches
    /// disk. The caller keeps the candidate session, rather than rebuilding it.
    func recording(_ step: GameSession.Step, session: GameSession.Checkpoint,
                   elapsedSeconds: TimeInterval) throws -> Self {
        guard pendingDevCardReveal == nil, pendingDevCardResolution == nil else {
            throw MatchCheckpointStore.StoreError.pendingAcknowledgement
        }
        var next = try applying(step.move, by: step.actor, elapsedSeconds: elapsedSeconds)
        try next.activeMatch?.attachSession(session)
        if next.activeMatch?.setup.humanSeats.contains(where: { $0.index == step.actor.index }) == true {
            for case .boughtDevCard(let owner, let card) in step.privateEvents {
                next.pendingDevCardReveal = DevCardReveal(owner: owner, card: card)
            }
            if let resolution = step.events.compactMap(Self.devCardResolution).last {
                next.pendingDevCardResolution = resolution
            }
        }
        return next
    }

    func dismissingDevCardReveal() throws -> Self {
        guard pendingDevCardReveal != nil else { return self }
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        var next = self
        next.pendingDevCardReveal = nil
        next.revision += 1
        return next
    }

    func dismissingDevCardResolution() throws -> Self {
        guard pendingDevCardResolution != nil else { return self }
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        var next = self
        next.pendingDevCardResolution = nil
        next.revision += 1
        return next
    }

    /// Bank foreground duration without manufacturing a game action. Finished
    /// matches keep their frozen duration, and identical values are retry-safe.
    func recordingElapsedTime(_ seconds: TimeInterval) throws -> Self {
        guard seconds.isFinite, seconds >= 0 else { throw MatchCheckpointStore.StoreError.invalidDuration }
        guard var match = activeMatch else { return self }
        if case .gameOver = match.state.phase { return self }
        if seconds == match.elapsedSeconds { return self }
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        try match.recordElapsedTime(seconds)
        var next = self
        next.activeMatch = match
        next.revision += 1
        return next
    }

    /// Switching or clearing the table retains the displaced recording in the
    /// same atomic revision. Export failure must never make New Game lose it.
    func replacingActiveMatch(with match: MatchCheckpoint?) throws -> Self {
        guard revision < Int.max else { throw MatchCheckpointStore.StoreError.staleRevision }
        if let match {
            guard match.id != activeMatch?.id, pendingExports[match.id] == nil,
                  completions[match.id] == nil else {
                throw MatchCheckpointStore.StoreError.inconsistentHistory
            }
            try match.validateHistory()
        }
        var next = self
        if let activeMatch { next.pendingExports[activeMatch.id] = activeMatch }
        next.activeMatch = match
        next.pendingDevCardReveal = nil
        next.pendingDevCardResolution = nil
        next.revision += 1
        return next
    }

    /// Acknowledge the exact snapshot exported, never just a UUID. A stale
    /// acknowledgement must not erase a newer recording awaiting export.
    func acknowledgingExport(of match: MatchCheckpoint) throws -> Self {
        guard revision < Int.max, pendingExports[match.id] == match else {
            throw MatchCheckpointStore.StoreError.staleRevision
        }
        var next = self
        next.pendingExports[match.id] = nil
        next.revision += 1
        return next
    }

    /// Freeze one receipt and its totals in the same document as the terminal
    /// state. Repeating completion after an unacknowledged commit is a no-op.
    mutating func recordCompletion(duration: TimeInterval) throws {
        guard var match = activeMatch, case .gameOver(let winner) = match.state.phase,
              duration.isFinite, duration >= 0, revision < Int.max else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        guard completions[match.id] == nil else { return }
        let humans = match.setup.humanSeats
        let human = humans.count == 1 ? PlayerID(index: humans[0].index) : nil
        guard human.map({ match.state.players.indices.contains($0.index) }) ?? true else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        let points = human.map { min(match.state.victoryPoints(for: $0), match.state.victoryPointTarget) } ?? 0
        let updatedStatistics = try human.map {
            try addingCompletion(won: winner == $0, points: points, duration: duration)
        } ?? statistics
        try match.recordElapsedTime(duration)
        activeMatch = match
        completions[match.id] = Completion(winner: winner, humanSeat: human, finalVP: points, duration: duration)
        statistics = updatedStatistics
        revision += 1
    }

    /// Validate arithmetic before changing either totals or receipts. A damaged
    /// baseline must produce a recoverable error, not an integer trap or an
    /// infinite duration that JSON cannot persist after the game was counted.
    private func addingCompletion(won: Bool, points: Int, duration: TimeInterval) throws -> GameStats {
        let played = statistics.gamesPlayed.addingReportingOverflow(1)
        let wins = statistics.gamesWon.addingReportingOverflow(won ? 1 : 0)
        let finalVP = statistics.totalFinalVP.addingReportingOverflow(points)
        let totalDuration = statistics.totalDurationSeconds + duration
        guard !played.overflow, !wins.overflow, !finalVP.overflow,
              statistics.gamesPlayed >= 0, statistics.gamesWon >= 0,
              statistics.gamesWon <= statistics.gamesPlayed, statistics.totalFinalVP >= 0,
              statistics.totalDurationSeconds >= 0, points >= 0, totalDuration.isFinite else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        return GameStats(gamesPlayed: played.partialValue, gamesWon: wins.partialValue,
                         totalFinalVP: finalVP.partialValue, totalDurationSeconds: totalDuration)
    }

    /// Archived histories remain authoritative until exported. Validate them
    /// just like the active match; a valid active board cannot excuse a damaged
    /// recording or an archive key referring to a different match identity.
    func validateAuthority() throws {
        try validateStatistics()
        try validatePendingDevCardOwners()
        try activeMatch?.validateHistory(
            pendingReveal: pendingDevCardReveal,
            pendingResolution: pendingDevCardResolution
        )
        for id in pendingExports.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let match = pendingExports[id], match.id == id, id != activeMatch?.id else {
                throw MatchCheckpointStore.StoreError.inconsistentHistory
            }
            try match.validateHistory()
        }
        try validateCompletions()
    }

    /// `validateAuthority()` for a candidate the store is about to write over
    /// `previous`, which this store already validated.
    ///
    /// Everything cheap is still checked in full - statistics, receipt
    /// ownership, completions. What is skipped is re-deriving history that
    /// cannot have changed: the active match's unchanged move prefix (see
    /// `MatchCheckpoint.validateHistory(succeeding:)`) and archived
    /// recordings that are byte-identical to the ones validated last time.
    /// Anything that is not a clean extension of `previous` - a different
    /// match, a rewritten prefix, a changed archive, a receipt that appeared
    /// without a move to source it - falls back to the full validation rather
    /// than being trusted.
    func validateAuthority(succeeding previous: Self?) throws {
        guard let previous,
              let candidate = activeMatch, let earlier = previous.activeMatch,
              pendingExports == previous.pendingExports,
              candidate.isExtending(earlier),
              candidate.moves.count > earlier.moves.count
                  || (pendingDevCardReveal == previous.pendingDevCardReveal
                      && pendingDevCardResolution == previous.pendingDevCardResolution)
        else {
            try validateAuthority()
            return
        }
        try validateStatistics()
        try validatePendingDevCardOwners()
        try candidate.validateHistory(
            succeeding: earlier,
            pendingReveal: pendingDevCardReveal,
            pendingResolution: pendingDevCardResolution
        )
        try validateCompletions()
    }

    private func validatePendingDevCardOwners() throws {
        guard pendingDevCardReveal != nil || pendingDevCardResolution != nil else { return }
        guard let match = activeMatch else { throw MatchCheckpointStore.StoreError.inconsistentHistory }
        let humans = Set(match.setup.humanSeats.map(\.index))
        guard pendingDevCardReveal.map({ humans.contains($0.owner.index) }) ?? true,
              pendingDevCardResolution.map({ humans.contains($0.owner.index) }) ?? true else {
            throw MatchCheckpointStore.StoreError.inconsistentHistory
        }
    }

    fileprivate static func devCardResolution(_ event: GameEvent) -> DevCardResolution? {
        switch event {
        case .playedKnight(let owner, let from, let stolen):
            .knight(owner: owner, from: from, stolen: stolen)
        case .playedRoadBuilding(let owner):
            .roadBuilding(owner: owner)
        case .playedYearOfPlenty(let owner, let taken):
            .yearOfPlenty(owner: owner, taken: taken)
        case .playedMonopoly(let owner, let resource, let gained):
            .monopoly(owner: owner, resource: resource, gained: gained)
        default:
            nil
        }
    }

    private func validateStatistics() throws {
        guard revision >= 0, statistics.gamesPlayed >= 0, statistics.gamesWon >= 0,
              statistics.gamesWon <= statistics.gamesPlayed, statistics.totalFinalVP >= 0,
              statistics.totalDurationSeconds.isFinite, statistics.totalDurationSeconds >= 0 else {
            throw MatchCheckpointStore.StoreError.invalidStatistics
        }
    }

    private func validateCompletions() throws {
        let retained = retainedMatchesByID()
        for id in completions.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let completion = completions[id], completion.winner.index >= 0,
                  completion.humanSeat.map({ $0.index >= 0 }) ?? true,
                  completion.finalVP >= 0, completion.duration.isFinite, completion.duration >= 0 else {
                throw MatchCheckpointStore.StoreError.invalidCompletion
            }
            if let match = retained[id] { try validate(completion, against: match) }
        }
    }

    private func retainedMatchesByID() -> [UUID: MatchCheckpoint] {
        var retained = pendingExports
        if let activeMatch { retained[activeMatch.id] = activeMatch }
        return retained
    }

    private func validate(_ completion: Completion, against match: MatchCheckpoint) throws {
        guard case .gameOver(let winner) = match.state.phase, completion.winner == winner else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
        let humans = match.setup.humanSeats
        let expectedHuman = humans.count == 1 ? humans[0].index : nil
        let expectedPoints = expectedHuman.map {
            min(match.state.victoryPoints(for: PlayerID(index: $0)), match.state.victoryPointTarget)
        } ?? 0
        guard completion.humanSeat?.index == expectedHuman,
              completion.finalVP == expectedPoints,
              completion.duration == match.elapsedSeconds else {
            throw MatchCheckpointStore.StoreError.invalidCompletion
        }
    }
}

/// Serializes app-process commits and refuses stale revisions. Atomic replacement
/// means a process interruption leaves the prior or next document, not separate
/// generations of state and roster. This is not a power-loss durability claim.
@MainActor
struct MatchCheckpointStore {
    enum StoreError: Error, Equatable {
        case unsupportedSchema, staleRevision, inconsistentHistory, invalidSetup
        case invalidStatistics, invalidCompletion, invalidDuration, recoveryNotPreserved
        case pendingAcknowledgement
    }
    enum CommitStage: Sendable { case beforeReplace, afterReplace }

    let fileURL: URL
    private let atCommitStage: (CommitStage) throws -> Void

    /// The exact bytes this store last read or wrote, and the validated
    /// document they decode to.
    ///
    /// This is a decode cache keyed on **content**, not a shortcut around
    /// verification. `commit` needs the document currently on disk to check
    /// the revision it is replacing, and decoding plus fully validating it
    /// cost 55ms per move by move 600 of an Expanded game - repeated for
    /// every one of ~800 moves. Comparing the file's bytes against the bytes
    /// we last wrote costs a read and a memcmp, and if anything at all wrote
    /// that file in the meantime the bytes differ and the full
    /// decode-and-validate path runs exactly as before. A reference box
    /// rather than a stored property because the store is a value type held
    /// by `let`, and `commit` is not a mutating operation on the caller's
    /// copy; `@MainActor` is what makes the shared box safe.
    private final class DecodeCache {
        var data: Data?
        var document: MatchCheckpointDocument?
    }
    private let cache = DecodeCache()

    /// The hook models an interruption at the filesystem boundary, not a
    /// gameplay collaborator. Production leaves it empty; process-kill tests
    /// can terminate a child at either side of the atomic replacement.
    init(fileURL: URL, atCommitStage: @escaping (CommitStage) throws -> Void = { _ in }) {
        self.fileURL = fileURL
        self.atCommitStage = atCommitStage
    }

    func load() throws -> MatchCheckpointDocument? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        if let cached = cache.document, cache.data == data { return cached }
        let document = try JSONDecoder().decode(MatchCheckpointDocument.self, from: data)
        guard document.schemaVersion == MatchCheckpointDocument.currentSchemaVersion else {
            throw StoreError.unsupportedSchema
        }
        try document.validateAuthority()
        cache.data = data
        cache.document = document
        return document
    }

    /// Recovery-only decode. Callers must never publish this value directly;
    /// it exists so valid independent accounting can survive a bad active match.
    func decodeForRecovery() throws -> MatchCheckpointDocument? {
        let data: Data
        do { data = try Data(contentsOf: fileURL) } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile { return nil }
        let document = try JSONDecoder().decode(MatchCheckpointDocument.self, from: data)
        guard document.schemaVersion == MatchCheckpointDocument.currentSchemaVersion else {
            throw StoreError.unsupportedSchema
        }
        return document
    }

    /// Explicit recovery replacement is allowed only after an independent copy
    /// preserves the exact source bytes. Recheck at the write boundary so a
    /// stale backup cannot authorize replacing a subsequently changed save.
    func replaceAfterRecovery(_ document: MatchCheckpointDocument, preservedOriginalAt backup: URL) throws {
        guard backup.resolvingSymlinksInPath() != fileURL.resolvingSymlinksInPath(),
              document.schemaVersion == MatchCheckpointDocument.currentSchemaVersion,
              document.revision == 0 else { throw StoreError.recoveryNotPreserved }
        try document.validateAuthority()
        let original = try Data(contentsOf: fileURL)
        guard try Data(contentsOf: backup) == original else { throw StoreError.recoveryNotPreserved }
        let encoded = try JSONEncoder().encode(document)
        try atCommitStage(.beforeReplace)
        guard try Data(contentsOf: fileURL) == original,
              try Data(contentsOf: backup) == original else { throw StoreError.recoveryNotPreserved }
        try encoded.write(to: fileURL, options: .atomic)
        try atCommitStage(.afterReplace)
    }

    func commit(_ document: MatchCheckpointDocument, replacingRevision expected: Int?) throws {
        let current = try load()
        if current == document { return } // Commit succeeded before its acknowledgement was lost.
        guard current?.revision == expected,
              expected.map({ $0 >= 0 && $0 < Int.max }) ?? true,
              document.revision == (expected.map { $0 + 1 } ?? 0) else {
            throw StoreError.staleRevision
        }
        // `current` came back validated - fully if it was decoded here, or
        // by the induction in `validateHistory(succeeding:)` if it is a
        // document this store wrote. Either way its history has been checked,
        // which is what licenses validating the candidate as a delta on it.
        try document.validateAuthority(succeeding: current)
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atCommitStage(.beforeReplace)
        try data.write(to: fileURL, options: .atomic)
        try atCommitStage(.afterReplace)
        cache.data = data
        cache.document = document
    }
}
