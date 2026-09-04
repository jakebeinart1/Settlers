import CatanEngine

extension GameViewModel {
    /// Consume the same validated record used by launch checks, not a second
    /// read that could disagree. Only a genuinely absent legacy roster falls
    /// back to the old single-human preference; damaged metadata never does.
    static func restoredRoster(from activeMatch: MatchSetupStore.LoadResult,
                               fallback: PlayerID) -> (seats: Set<PlayerID>, names: [PlayerID: String]) {
        guard case .loaded(let active) = activeMatch else { return ([fallback], [:]) }
        var seats: Set<PlayerID> = []
        var names: [PlayerID: String] = [:]
        for chair in active.humanSeats {
            let id = PlayerID(index: chair.index)
            seats.insert(id)
            if !chair.name.isEmpty { names[id] = chair.name }
        }
        // Keep even a solo human's saved name; app preferences are a prefill,
        // not permission to rename a running match during restoration.
        return (seats, names)
    }

    /// Validate before any label/profile restoration indexes into a saved chair.
    /// Missing legacy metadata is migratable; present-but-invalid metadata is
    /// not permission to replace people with bots or redraw their identities.
    static func recoveryProblem(for result: GameStore.LoadResult,
                                activeMatch: MatchSetupStore.LoadResult,
                                legacySeat: PlayerID) -> String? {
        switch result {
        case .none: return nil
        case .unreadable:
            return "Your saved game could not be read. It has not been changed."
        case .loaded(let state):
            if let problem = savedStateProblem(state) { return problem }
            switch activeMatch {
            case .unreadable:
                return "Your saved player setup could not be read. The game and setup have not been changed."
            case .none:
                return state.players.indices.contains(legacySeat.index) ? nil
                    : "The saved human seat is outside this table. The original files have not been changed."
            case .loaded(let setup):
                return savedRosterProblem(setup, state: state)
            }
        }
    }

    private static func savedStateProblem(_ state: GameState) -> String? {
        guard state.schemaVersion <= GameState.currentSchemaVersion,
              GameSetup.supportedPlayerCounts.contains(state.players.count),
              state.players.map({ $0.id.index }).elementsEqual(state.players.indices) else {
            return "This saved game has an unsupported version or player layout. It has not been changed."
        }
        let occupied = Set(state.players.map(\.id))
        let validPhase: Bool
        switch state.phase {
        case .discarding(let pending): validPhase = !pending.isEmpty && pending.isSubset(of: occupied)
        case .gameOver(let winner): validPhase = occupied.contains(winner)
        default: validPhase = state.phase.awaitingSeatIndex.map(state.players.indices.contains) == true
        }
        return validPhase ? nil : "The saved turn refers to an invalid seat. The game has not been changed."
    }

    private static func savedRosterProblem(_ setup: MatchSetup, state: GameState) -> String? {
        let civilizations = setup.seats.compactMap { seat in
            seat.isHuman ? seat.civilization : seat.opponentProfile?.civilization ?? seat.civilization
        }
        // Legacy active-match sidecars predate opponent-profile snapshots;
        // migration fills those profiles before writing a checkpoint. Do not
        // require a fully realized identity roster at this earlier boundary.
        guard setup.isValidMatch,
              setup.seats.count == state.players.count,
              setup.victoryPointTarget == state.victoryPointTarget,
              civilizations.count == state.players.count,
              Set(civilizations).count == civilizations.count else {
            return "The saved player setup does not match this game. The original files have not been changed."
        }
        return nil
    }
}
