import CatanEngine

/// A baseline bot that always plays through `RulesEngine.legalMoves` -
/// exactly the same entrypoint a human-driven UI uses - so it can never
/// fabricate an illegal move. Placement and build choices lean on
/// `PlacementHeuristics`/`BuildPlanner`; other move categories (trading,
/// dev-card play, robber targeting beyond a simple safe default) are left to
/// Task 10.
public struct Bot: Sendable {
    public let personality: BotPersonality

    public init(personality: BotPersonality) {
        self.personality = personality
    }

    /// Always returns a member of `RulesEngine.legalMoves(for: state)`.
    public func decide(for state: GameState, player: PlayerID) -> GameMove {
        let legal = RulesEngine.legalMoves(for: state)

        switch state.phase {
        case .setupForward, .setupBackward:
            return decideSetupPlacement(legal: legal, state: state)

        case .rollDice:
            return .rollDice

        case .mainTurn:
            return BuildPlanner.chooseBuild(for: state, player: player, personality: personality) ?? .endTurn

        case .discarding:
            return decideDiscard(legal: legal, state: state, player: player)

        case .movingRobber:
            return decideRobber(legal: legal, state: state, player: player)

        case .gameOver:
            // `decide` is never expected to be called in this phase - fall
            // back to whatever `legalMoves` offers (typically nothing).
            return legal.first ?? .endTurn
        }
    }

    // MARK: - Setup placement

    private func decideSetupPlacement(legal: [GameMove], state: GameState) -> GameMove {
        guard !legal.isEmpty else { return .endTurn }

        if case .placeInitialSettlement = legal[0] {
            var best = legal[0]
            var bestScore = -Double.infinity
            for move in legal {
                guard case .placeInitialSettlement(let vertex) = move else { continue }
                let score = PlacementHeuristics.score(vertex: vertex, board: state.board)
                if score > bestScore {
                    bestScore = score
                    best = move
                }
            }
            return best
        }

        // Otherwise every legal move is `.placeInitialRoad` - point it
        // toward whichever endpoint has the better future settlement value.
        var best = legal[0]
        var bestScore = -Double.infinity
        for move in legal {
            guard case .placeInitialRoad(let edge) = move else { continue }
            let (a, b) = state.board.vertices(of: edge)
            let score = max(
                PlacementHeuristics.score(vertex: a, board: state.board),
                PlacementHeuristics.score(vertex: b, board: state.board)
            )
            if score > bestScore {
                bestScore = score
                best = move
            }
        }
        return best
    }

    // MARK: - Discarding

    private func decideDiscard(legal: [GameMove], state: GameState, player: PlayerID) -> GameMove {
        guard let me = state.players.first(where: { $0.id == player }) else {
            return legal.first ?? .endTurn
        }
        let requiredCount = Robber.discardCount(for: me)

        // `legalMoves(for:)` in `.discarding` is the union of every pending
        // player's legal combinations, so first narrow to ones that are
        // actually affordable for and sized for this player.
        let mine = legal.filter { move in
            guard case .discard(let discarded) = move else { return false }
            guard discarded.values.reduce(0, +) == requiredCount else { return false }
            return discarded.allSatisfy { resource, amount in (me.resources[resource] ?? 0) >= amount }
        }
        guard !mine.isEmpty else { return legal.first ?? .endTurn }

        // Prefer discarding from whichever resources this player holds the
        // most of, keeping their remaining hand as diverse as possible.
        func redundancy(_ discarded: [Resource: Int]) -> Int {
            discarded.reduce(0) { partial, entry in
                let (resource, amount) = entry
                return partial + amount * (me.resources[resource] ?? 0)
            }
        }

        return mine.max { a, b in
            guard case .discard(let da) = a, case .discard(let db) = b else { return false }
            return redundancy(da) < redundancy(db)
        } ?? mine[0]
    }

    // MARK: - Robber

    private func decideRobber(legal: [GameMove], state: GameState, player: PlayerID) -> GameMove {
        guard !legal.isEmpty else { return .endTurn }
        guard let me = state.players.first(where: { $0.id == player }) else { return legal[0] }

        // Value of parking the robber on `tile`: opponent building weight
        // there, heavily penalized if it would also sit on our own.
        func tileScore(_ tile: HexCoordinate) -> Int {
            let vertices = state.board.onBoardVertices.filter { $0.touchingTiles.contains(tile) }
            var opponentValue = 0
            var touchesOwn = false
            for vertex in vertices {
                for other in state.players where other.id != player {
                    if other.cities.contains(vertex) { opponentValue += 2 }
                    else if other.settlements.contains(vertex) { opponentValue += 1 }
                }
                if me.settlements.contains(vertex) || me.cities.contains(vertex) { touchesOwn = true }
            }
            return touchesOwn ? opponentValue - 100 : opponentValue
        }

        var bestTile: HexCoordinate?
        var bestTileScore = Int.min
        for move in legal {
            guard case .moveRobber(let tile, _) = move else { continue }
            let score = tileScore(tile)
            if score > bestTileScore {
                bestTileScore = score
                bestTile = tile
            }
        }
        guard let bestTile else { return legal[0] }

        let candidates = legal.filter { move in
            guard case .moveRobber(let tile, _) = move else { return false }
            return tile == bestTile
        }

        // Among moves on the chosen tile, steal from whichever eligible
        // victim holds the most resources; fall back to the no-steal option.
        func resourceCount(_ victim: PlayerID?) -> Int {
            guard let victim, let owner = state.players.first(where: { $0.id == victim }) else { return -1 }
            return owner.resources.values.reduce(0, +)
        }

        return candidates.max { a, b in
            guard case .moveRobber(_, let va) = a, case .moveRobber(_, let vb) = b else { return false }
            return resourceCount(va) < resourceCount(vb)
        } ?? candidates[0]
    }
}
