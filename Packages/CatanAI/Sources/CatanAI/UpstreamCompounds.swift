import CatanEngine

/// An invocation-local staging area: subdecisions change only this copy. The
/// session receives one complete member of its original legal action list.
/// Swift requires both Road Building roads and complete Knight resolution even
/// when upstream would already have declared victory between those choices.
struct UpstreamCompounds {
    private typealias Action = UpstreamCodec.Action
    private typealias TurnPhase = UpstreamCodec.TurnPhase
    let observation: GameObservation
    let layout: UpstreamBoardLayout
    let scorer: UpstreamActionScorer

    func resolve(root: Int, candidates: [GameMove]) throws -> GameMove {
        if root == UpstreamActions.roadBuilding { return try roads(candidates) }
        if root == UpstreamActions.knight { return try robber(candidates, knight: true) }
        if Action.robberTiles.contains(root) { return try robber(candidates, knight: false) }
        guard let first = candidates.first else { throw UpstreamActionScorer.ScoringError.incompleteCompound }
        // For Year of Plenty prefer canonical upstream resource order. When a
        // caller offers only the reverse ordering, return that exact legal move.
        if Action.yearOfPlenty.contains(root) {
            return candidates.first {
                guard case .playYearOfPlenty(let a, let b) = $0 else { return false }
                return UpstreamActions.resourceIndex(a) <= UpstreamActions.resourceIndex(b)
            } ?? first
        }
        return first
    }

    private func roads(_ candidates: [GameMove]) throws -> GameMove {
        var state = observation.state
        try consume(.roadBuilding, state: &state)
        var context = UpstreamDecisionContext(state: state, seat: observation.seat)
        context.turnPhase = TurnPhase.roadBuilding
        context.roadsToPlace = 2
        let firstIDs = candidates.compactMap { roadID($0, second: false) }
        let firstID = try scorer.choose(firstIDs, state: state, seat: observation.seat, context: context)
        let remaining = candidates.filter { roadID($0, second: false) == firstID }
        let edge = layout.edges[firstID - Action.roadOffset]
        state.players[observation.seat.index].roads.insert(edge)
        state.longestRoadPlayer = LongestRoad.compute(for: state)
        context.roadsToPlace = 1
        let secondID = try scorer.choose(remaining.compactMap { roadID($0, second: true) },
                                         state: state, seat: observation.seat, context: context)
        guard let move = remaining.first(where: { roadID($0, second: true) == secondID }) else {
            throw UpstreamActionScorer.ScoringError.incompleteCompound
        }
        return move
    }

    private func roadID(_ move: GameMove, second: Bool) -> Int? {
        guard case .playRoadBuilding(let a, let b) = move else { return nil }
        return UpstreamActions.road(second ? b : a, layout: layout)
    }

    private func robber(_ candidates: [GameMove], knight: Bool) throws -> GameMove {
        var state = observation.state
        if knight {
            try consume(.knight, state: &state)
            state.players[observation.seat.index].playedKnights += 1
            updateLargestArmy(state: &state)
        }
        var context = UpstreamDecisionContext(state: state, seat: observation.seat)
        context.turnPhase = TurnPhase.movingRobber
        let tileID = try scorer.choose(candidates.compactMap { robberTileID($0) },
                                       state: state, seat: observation.seat, context: context)
        let remaining = candidates.filter { robberTileID($0) == tileID }
        state.board.robberTile = layout.tiles[tileID - Action.robberTiles.lowerBound]
        context.turnPhase = TurnPhase.choosingVictim
        let victimID = try scorer.choose(remaining.compactMap { robberVictimID($0) },
                                         state: state, seat: observation.seat, context: context)
        guard let move = remaining.first(where: { robberVictimID($0) == victimID }) else {
            throw UpstreamActionScorer.ScoringError.incompleteCompound
        }
        return move
    }

    private func robberTileID(_ move: GameMove) -> Int? {
        switch move {
        case .playKnight(let tile, _), .moveRobber(let tile, _):
            return UpstreamActions.robber(tile, layout: layout)
        default: return nil
        }
    }

    private func robberVictimID(_ move: GameMove) -> Int? {
        switch move {
        case .playKnight(_, let victim), .moveRobber(_, let victim):
            return UpstreamActions.victim(victim, seat: observation.seat, playerCount: observation.state.players.count)
        default: return nil
        }
    }

    /// Deplete a private hand one card at a time, but keep the quota fixed to
    /// the original hand. Prefix filtering also honours a caller-narrowed mask.
    func discard() throws -> GameMove {
        var state = observation.state
        var context = UpstreamDecisionContext(state: state, seat: observation.seat)
        var candidates = observation.legalMoves.compactMap { move -> [Resource: Int]? in
            guard case .discard(let bundle) = move else { return nil }
            return bundle
        }
        guard let quota = candidates.first?.values.reduce(0, +), quota > 0,
              candidates.allSatisfy({ $0.values.reduce(0, +) == quota }) else {
            throw UpstreamActionScorer.ScoringError.incompleteCompound
        }
        context.discardsRemaining = quota
        var chosen: [Resource: Int] = [:]
        while context.discardsRemaining > 0 {
            let allowed = UpstreamActions.resources.enumerated().compactMap { index, resource in
                candidates.contains { $0[resource, default: 0] > chosen[resource, default: 0] } ? Action.discardOffset + index : nil
            }
            let id = try scorer.choose(allowed, state: state, seat: observation.seat, context: context)
            let resource = UpstreamActions.resources[id - Action.discardOffset]
            chosen[resource, default: 0] += 1
            state.players[observation.seat.index].resources[resource, default: 0] -= 1
            state.bank[resource, default: 0] += 1
            context.discardsRemaining -= 1
            candidates = candidates.filter { $0[resource, default: 0] >= chosen[resource, default: 0] }
        }
        return try matchingDiscard(chosen)
    }

    private func matchingDiscard(_ chosen: [Resource: Int]) throws -> GameMove {
        guard let move = observation.legalMoves.first(where: {
            guard case .discard(let bundle) = $0 else { return false }
            return UpstreamActions.resources.allSatisfy { bundle[$0, default: 0] == chosen[$0, default: 0] }
        }) else { throw UpstreamActionScorer.ScoringError.incompleteCompound }
        return move
    }

    private func consume(_ card: DevCardType, state: inout GameState) throws {
        guard let index = state.players[observation.seat.index].devCards.firstIndex(of: card) else {
            throw UpstreamActionScorer.ScoringError.incompleteCompound
        }
        state.players[observation.seat.index].devCards.remove(at: index)
        state.devCardPlayedThisTurn = observation.seat
    }

    private func updateLargestArmy(state: inout GameState) {
        let count = state.players[observation.seat.index].playedKnights
        let holderCount = state.largestArmyPlayer.map { state.players[$0.index].playedKnights } ?? 0
        // At a reachable position a new knight can only retain the incumbent
        // or make this actor the unique leader, so no unrelated seat is changed.
        if count >= 3 && count > holderCount { state.largestArmyPlayer = observation.seat }
    }
}
