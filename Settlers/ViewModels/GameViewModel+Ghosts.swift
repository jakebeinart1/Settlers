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

    static let ghostProfilePrefix = "ghost-"

    /// The ghost behind a profile, if it is a ghost's.
    static func ghostID(of profile: OpponentProfile) -> String? {
        profile.id.hasPrefix(ghostProfilePrefix) ? String(profile.id.dropFirst(ghostProfilePrefix.count)) : nil
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
    static func policy(for profile: OpponentProfile, difficulty: BotDifficulty, ghosts: GhostStore) -> any Policy {
        guard let id = ghostID(of: profile) else { return difficulty.policy(for: profile) }
        guard let ghost = ghosts.ghost(id: id) else { return EvaluationPolicy() }
        return GhostPolicy(person: ghost.person, lambda: ghost.lambda, id: profile.id)
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
    /// Only Classic standard games with exactly one human are rated or taught,
    /// the same scope ghosts play in, so the ladder compares like with like.
    /// Rating is idempotent by match id, so calling this again for the same
    /// match (a resume after a crash) is safe. Training runs in the background
    /// and never blocks the end screen; a failure leaves the ghost as it was.
    func recordFinishedMatch(_ match: MatchCheckpoint) -> Task<Void, Never>? {
        guard case .gameOver(let winner) = match.state.phase else { return nil }
        let setup = match.setup
        guard setup.mode == .classic, setup.variant == .standard, setup.humanSeats.count == 1,
              let human = setup.humanSeats.first else { return nil }
        do {
            try ratingStore.record(match: match.id, seats: setup.seats.map { Self.ratedEntity(for: $0, in: setup) },
                                   winner: winner.index)
        } catch {
            gameLogWarning = "This game's rating could not be saved: \(error.localizedDescription)"
        }
        let game = LoggedGame(id: match.id.uuidString, initialState: match.initialState,
                              humanSeats: [PlayerID(index: human.index)],
                              events: match.moves.map { LoggedMove(player: $0.actor, move: $0.move) })
        let trainer = GhostTrainer(store: ghostStore)
        let matchID = match.id
        return Task.detached(priority: .background) {
            _ = try? trainer.learn(match: matchID, game: game, human: PlayerID(index: human.index), personName: human.name)
        }
    }

    /// Who sat in a chair, for the ladder: the person by name, a ghost by id,
    /// any other AI as its tier.
    static func ratedEntity(for seat: MatchSetup.Seat, in setup: MatchSetup) -> RatedEntity {
        if seat.isHuman { return .person(seat.name) }
        if let profile = seat.opponentProfile, let id = ghostID(of: profile) { return .ghost(id) }
        return setup.difficulty == .expert ? .expert : .classic
    }
}
