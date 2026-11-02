import Foundation
import CatanAI
import CatanEngine

/// Ghosts in chairs.
///
/// A ghost chair is an ordinary AI chair whose opponent profile is
/// `ghost-<id>` and carries the ghost's name. That is the whole integration:
/// the HUD, the end screen and the game log already name an AI chair by its
/// profile, so "Jake's Ghost" appears everywhere without a new copy of
/// seat naming (CLAUDE.md, "Seat 0 is the human": pass the seat, don't copy
/// the rule), and a resumed game finds its ghost from the profile alone.
extension GameViewModel {

    static let ghostProfilePrefix = OpponentProfile.ghostProfilePrefix

    /// The ghost behind a profile, if it is a ghost's.
    static func ghostID(of profile: OpponentProfile) -> String? {
        profile.ghostID
    }

    /// Profiles for the chairs a ghost sits in: the chair's own drawn
    /// civilization, so a ghost never collides with a civilization already
    /// taken, and the ghost's name. A ghost the store lacks gets no profile
    /// here; `MatchSetup.newGameProblem` refuses that table before it starts.
    static func ghostOpponentProfiles(chairs: [MatchSetup.Seat], civilizations: [Civilization],
                                      store: GhostStore) -> [PlayerID: OpponentProfile] {
        var profiles: [PlayerID: OpponentProfile] = [:]
        for (chair, seat) in chairs.enumerated() where !seat.isHuman {
            guard let id = seat.ghostID, let ghost = store.ghost(id: id) else { continue }
            profiles[PlayerID(index: chair)] = OpponentProfile(
                id: ghostProfilePrefix + ghost.id, name: ghost.name,
                civilization: civilizations[chair], strategy: .balanced
            )
        }
        return profiles
    }

    /// A ghost's chair gets its `GhostPolicy`; any other AI chair its tier.
    /// A ghost that is gone gets Expert here only so this stays total: resume
    /// refuses that save first (`missingGhostProblem`), because the checkpoint
    /// records each chair's policy and `GameSession` rejects a substitute.
    static func policy(for profile: OpponentProfile, difficulty: BotDifficulty, ghosts: GhostStore,
                       expertRevision: ExpertRevision = .legacy) -> any Policy {
        guard let id = ghostID(of: profile) else {
            return difficulty.policy(for: profile, expertRevision: expertRevision)
        }
        guard let ghost = ghosts.ghost(id: id) else { return EvaluationPolicy() }
        return ghost.policy(id: profile.id)
    }

    /// Why a saved game cannot resume because a ghost in it is gone, naming
    /// the seat, or `nil`. The save itself is kept untouched.
    func missingGhostProblem(in profiles: [PlayerID: OpponentProfile]) -> String? {
        let missing = profiles.keys.sorted().first { seat in
            guard let profile = profiles[seat], let id = Self.ghostID(of: profile) else { return false }
            return ghostStore.ghost(id: id) == nil
        }
        guard let seat = missing, let name = profiles[seat]?.name else { return nil }
        return "Seat \(seat.index + 1)'s ghost (\(name)) is no longer on this phone, so this game cannot continue. "
            + "Your saved game has been kept."
    }

    /// A finished game: rate every seat, then teach the human's ghost.
    ///
    /// Ordinary AI games rate in their own mode/tier pool. The historic ghost
    /// ladder and training remain Classic/Standard only. Full replay evidence
    /// is queued before derived stats so offline archive pruning cannot lose
    /// a completed match; a resumed completion is idempotent by match ID.
    func recordFinishedMatch(_ match: MatchCheckpoint) -> Task<Void, Never>? {
        guard case .gameOver = match.state.phase else { return nil }
        let setup = match.setup
        // A match with no moves is a QA forced win, not a game (final review).
        guard !match.moves.isEmpty, let shared = sharedRatedMatch(match, abandoned: false),
              let human = setup.humanSeats.first else { return nil }
        let me = playerDirectory.resolvedID(match.playerID ?? playerDirectory.me)
        let game = LoggedGame(id: match.id.uuidString, initialState: match.initialState,
                              humanSeats: [PlayerID(index: human.index)],
                              events: match.moves.map {
                                  LoggedMove(player: $0.actor, move: $0.move, isHumanDecision: $0.isHumanDecision)
                              })
        do {
            try persistRatingMatch(shared)
        } catch {
            gameLogWarning = "This game's rating or stats could not be saved: \(error.localizedDescription)"
        }
        guard setup.mode == .classic, setup.variant == .standard else {
            return Task { await LiveSync.shared?.sync() }
        }
        #if DEBUG
        // -qaPlayToEnd plays the human's seat with a bot; it must not teach
        // anyone's ghost.
        if QALaunchFlag.playToEnd.isSet { return nil }
        #endif
        let trainer = makeGhostTrainer(ghostStore)
        let matchID = match.id
        return Task.detached(priority: .background) {
            // The game goes up at once; a second pass after training sends
            // the ghost that learned from it.
            await LiveSync.shared?.sync()
            await GhostTrainingQueue.shared.learn(trainer, match: matchID, game: game,
                                                  human: PlayerID(index: human.index), personID: me, personName: human.name)
            await LiveSync.shared?.sync()
        }
    }

    /// The rated game a new game is about to replace unfinished, in shared
    /// form, or `nil`. All ordinary AI pools plus the historic Classic ghost
    /// ladder. Kept even with no moves made, since a restart on seeing the
    /// board is a restart too. See `LiveSync.recordAbandoned`.
    func abandonedRatedMatch() -> SharedMatch? {
        guard let match = checkpointDocument?.activeMatch else { return nil }
        if case .gameOver = match.state.phase { return nil }
        return sharedRatedMatch(match, abandoned: true)
    }

    /// Who sat in a chair, for the ladder: the person is this phone's player
    /// (`me`) whatever name they typed, a ghost by id, any other AI as its
    /// tier. Only one-human games are rated, so the human is always `me`.
    static func ratedEntity(for seat: MatchSetup.Seat, in setup: MatchSetup, me: String) -> RatedEntity {
        if seat.isHuman { return .person(me) }
        if let profile = seat.opponentProfile, let id = ghostID(of: profile) { return .ghost(id) }
        return setup.difficulty == .expert ? .expert : .classic
    }

    /// Once per phone, at launch: games and the ghost filed under typed names
    /// before 2026-09-29 move to this phone's player id, and ratings follow.
    func migrateLegacyPlayerNames() {
        do {
            let refiled = try playerDirectory.migrateLegacyNames(seatStats: seatStatsStore, ghosts: ghostStore,
                                                               logs: gameLogStore)
            let recovered = try recoverCompletedRatingRecords()
            if refiled || recovered { try ratingStore.rebuild(from: seatStatsStore.all()) }
        } catch {
            gameLogWarning = "Your game ratings could not be restored: \(error.localizedDescription)"
        }
    }

    /// At launch, teaches any rated game whose training was cut off.
    func startGhostCatchUp() {
        let logs = gameLogStore
        let me = playerDirectory.me
        let rated = Set(seatStatsStore.all().filter { record in
            record.seats.contains { $0.personID == me }
                && (record.ratingPool == nil || (record.ratingPool?.mode == .classic && record.ratingPool?.variant == .standard))
        }.map(\.match))
        guard !rated.isEmpty else { return }
        let trainer = GhostTrainer(store: ghostStore)
        Task.detached(priority: .background) {
            let games = Self.catchUpGames(logs: logs, rated: rated, me: me)
            _ = await GhostTrainingQueue.shared.catchUp(trainer, games: games, ratedMatches: rated)
        }
    }

    // ponytail: reads every rated game's log at each launch; a small
    // "taught" index is the upgrade once rated games run into the thousands.
    nonisolated static func catchUpGames(logs: GameLogStore, rated: Set<UUID>, me: String) -> [CatchUpGame] {
        let summaries = (try? logs.summaries()) ?? []
        return summaries.filter { rated.contains($0.gameID) && $0.isComplete && $0.humanSeats.count == 1 }
            .compactMap { summary in
                guard let detail = try? logs.detail(for: summary), detail.initialState.mode == .classic,
                      detail.initialState.variant == .standard, let human = summary.humanSeats.first,
                      let name = detail.roster.humanNames[human.index] else { return nil }
                let game = LoggedGame(id: summary.gameID.uuidString, initialState: detail.initialState, humanSeats: [human],
                                      events: detail.events.map {
                                          LoggedMove(player: $0.player, move: $0.move, isHumanDecision: $0.isHumanDecision)
                                      })
                return CatchUpGame(match: summary.gameID, game: game, human: human, personID: me, personName: name)
            }
    }
}
