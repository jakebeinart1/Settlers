import CatanAI
import CatanEngine

extension GameViewModel {
    /// Match-authoritative presentation identity for a seat. Bot names and
    /// civilizations come from the same realized profile snapshot, so tuning
    /// today's catalog cannot create a hybrid identity in a resumed game.
    public func playerIdentity(for player: PlayerID) -> PlayerIdentity {
        precondition(state.players.contains { $0.id == player },
                     "Only occupied seats have player identities")
        return playerRoster.identity(for: player)
    }

    /// Compatibility convenience for text-only call sites.
    public func playerLabel(for player: PlayerID) -> String {
        playerIdentity(for: player).displayName
    }

    /// Restores the one civilization assignment matching the save on disk.
    ///
    /// The realized active-match record is the canonical fallback because it
    /// already contains Random choices and shuffled chairs. Previously a
    /// missing or mismatched sidecar redrew the table even though this exact
    /// assignment was still available, changing colors, names, voices and now
    /// strategic profiles during resume.
    static func restoredCivilizations(
        for state: GameState,
        humanSeat: PlayerID,
        civilizationStore: CivilizationAssignmentStore,
        matchSetupStore: MatchSetupStore
    ) -> [Civilization] {
        if case .loaded(let active) = matchSetupStore.loadActiveMatch(),
           active.seats.count == state.players.count {
            // A persisted bot profile is the complete opponent snapshot. If
            // an older or partially-written record disagrees with the seat's
            // civilization field, keep the profile's identity, color, voice
            // and strategy together rather than silently assembling a hybrid.
            let realized = active.seats.compactMap { seat in
                seat.isHuman ? seat.civilization : seat.opponentProfile?.civilization ?? seat.civilization
            }
            if realized.count == state.players.count { return realized }
        }
        if let saved = civilizationStore.load(), saved.count == state.players.count {
            return saved
        }
        return Array(
            drawAssignment(from: CivilizationSettingsStore.shared.load(), humanSeat: humanSeat)
                .prefix(state.players.count)
        )
    }

    /// The realized opponent occupying `player`, if that chair is a bot.
    public func opponentProfile(for player: PlayerID) -> OpponentProfile? {
        opponentProfiles[player]
    }

    func personality(for player: PlayerID) -> BotPersonality {
        guard let profile = opponentProfile(for: player) else {
            preconditionFailure("Human seat \(player.index) has no bot personality")
        }
        return profile.strategicPersonality
    }

    /// The same assignment, as a name for the game log. Both read the one
    /// table below so a seat's recorded personality cannot drift from the one
    /// it is actually played with.
    func personalityName(for player: PlayerID) -> String {
        guard let profile = opponentProfile(for: player) else {
            preconditionFailure("Human seat \(player.index) has no bot personality")
        }
        return profile.strategy.rawValue
    }

    static func opponentProfiles(
        for state: GameState,
        humanSeats: Set<PlayerID>,
        civilizations: [Civilization],
        realizedSeats: [MatchSetup.Seat]? = nil,
        preserveLegacySeatOrder: Bool = false
    ) -> [PlayerID: OpponentProfile] {
        precondition(civilizations.count >= state.players.count,
                     "Every occupied chair needs a civilization")
        return Dictionary(uniqueKeysWithValues: state.players.compactMap { player in
            guard !humanSeats.contains(player.id) else { return nil }
            let civilization = civilizations[player.id.index]
            let snapshot = realizedSeats.flatMap { seats -> OpponentProfile? in
                guard seats.indices.contains(player.id.index) else { return nil }
                return seats[player.id.index].opponentProfile
            }
            if let snapshot {
                precondition(snapshot.civilization == civilization,
                             "Restored civilization must agree with its opponent profile")
                return (player.id, snapshot)
            }
            if preserveLegacySeatOrder, realizedSeats != nil {
                let strategy = legacyStrategy(for: player.id, humanSeats: humanSeats, state: state)
                return (player.id, OpponentProfile(
                    id: "legacy-\(civilization.rawValue)-\(strategy.rawValue)",
                    name: civilization.generalName,
                    civilization: civilization,
                    strategy: strategy
                ))
            }
            return (player.id, OpponentProfile.forCivilization(civilization))
        })
    }

    /// Compatibility rule for matches created before profiles were persisted.
    /// This is the one place the old ordinal-bot assignment is preserved; new
    /// matches never use it.
    private static func legacyStrategy(
        for player: PlayerID,
        humanSeats: Set<PlayerID>,
        state: GameState
    ) -> OpponentStrategy {
        let bots = state.players.map(\.id).filter { !humanSeats.contains($0) }
        let rank = bots.firstIndex(of: player) ?? 0
        return [OpponentStrategy.balanced, .aggressive, .cautious][min(rank, 2)]
    }
}
