/// Setup-phase-specific legal move generation and application: players
/// alternate through indices 0-3 (forward pass) then 3-0 (backward/snake
/// pass), each placing one settlement then one adjacent road per turn.
enum SetupPhase {
    static func legalMoves(for state: GameState) -> [GameMove] {
        guard let playerIndex = currentPlayerIndex(state.phase) else { return [] }
        let player = state.players[playerIndex]

        if let pendingVertex = unroadedSettlement(of: player, board: state.board) {
            return state.board.edgesTouching(pendingVertex).map { .placeInitialRoad($0) }
        } else {
            return legalSettlementVertices(state: state).map { .placeInitialSettlement($0) }
        }
    }

    static func apply(_ move: GameMove, by player: PlayerID, to state: inout GameState) throws -> [GameEvent] {
        guard let playerIndex = currentPlayerIndex(state.phase) else {
            throw MoveError.wrongPhase
        }
        guard player.index == playerIndex else {
            throw MoveError.notYourTurn
        }

        switch move {
        case .placeInitialSettlement(let vertex):
            guard unroadedSettlement(of: state.players[playerIndex], board: state.board) == nil else {
                throw MoveError.wrongPhase
            }
            guard legalSettlementVertices(state: state).contains(vertex) else {
                throw MoveError.illegalPlacement
            }
            state.players[playerIndex].settlements.insert(vertex)

            let isBackwardPass: Bool
            if case .setupBackward = state.phase { isBackwardPass = true } else { isBackwardPass = false }
            if isBackwardPass {
                grantInitialResources(for: vertex, playerIndex: playerIndex, state: &state)
            }
            return [.placedInitialSettlement(player)]

        case .placeInitialRoad(let edge):
            guard let pendingVertex = unroadedSettlement(of: state.players[playerIndex], board: state.board) else {
                throw MoveError.wrongPhase
            }
            guard state.board.edgesTouching(pendingVertex).contains(edge) else {
                throw MoveError.illegalPlacement
            }
            state.players[playerIndex].roads.insert(edge)
            advancePhase(state: &state, justCompletedIndex: playerIndex)
            return [.placedInitialRoad(player)]

        default:
            throw MoveError.wrongPhase
        }
    }

    // MARK: - Helpers

    private static func currentPlayerIndex(_ phase: GamePhase) -> Int? {
        switch phase {
        case .setupForward(let index), .setupBackward(let index):
            return index
        default:
            return nil
        }
    }

    /// The player's most recently placed settlement that has no road of
    /// theirs touching it yet - i.e. the settlement placed earlier this
    /// sub-turn that still needs its accompanying road. Each setup turn
    /// places a settlement then immediately its road, so at most one such
    /// settlement exists at a time.
    ///
    /// Sorted before `.first`: `settlements` is a `Set`, so picking "the
    /// first" match is picking whichever one Swift's per-process hash order
    /// happened to yield. Only one match is reachable during setup - the
    /// distance rule guarantees it - so this is not a live bug, but it is the
    /// same shape as several that were, and it sits on the setup path where a
    /// divergence would desynchronise an entire seeded game from move one.
    private static func unroadedSettlement(of player: Player, board: Board) -> VertexID? {
        player.settlements.sorted().first { vertex in
            !board.edgesTouching(vertex).contains { player.roads.contains($0) }
        }
    }

    /// On-board, unoccupied vertices at least 2 edges away from every
    /// existing settlement/city (the standard distance rule).
    private static func legalSettlementVertices(state: GameState) -> [VertexID] {
        let occupied = Set(state.players.flatMap { $0.settlements.union($0.cities) })
        var tooClose = Set<VertexID>()
        for vertex in occupied {
            tooClose.formUnion(state.board.adjacentVertices(of: vertex))
        }
        // Sorted for the same reason as `Board.edgesTouching`: this feeds
        // `legalMoves` directly, and `onBoardVertices` is a `Set`.
        return state.board.onBoardVertices
            .filter { !occupied.contains($0) && !tooClose.contains($0) }
            .sorted()
    }

    /// Grants resources from every tile adjacent to `vertex` to the given
    /// player - only ever called for the second (backward-pass) settlement,
    /// per standard setup rules.
    private static func grantInitialResources(for vertex: VertexID, playerIndex: Int, state: inout GameState) {
        for coordinate in state.board.neighborTiles(of: vertex) {
            guard let tile = state.board.tiles.first(where: { $0.coordinate == coordinate }) else { continue }
            guard case .resource(let resource) = tile.kind else { continue }
            state.players[playerIndex].resources[resource, default: 0] += 1
            if let bankAmount = state.bank[resource], bankAmount > 0 {
                state.bank[resource] = bankAmount - 1
            }
        }
    }

    private static func advancePhase(state: inout GameState, justCompletedIndex: Int) {
        switch state.phase {
        case .setupForward:
            if justCompletedIndex < 3 {
                state.phase = .setupForward(playerIndex: justCompletedIndex + 1)
            } else {
                state.phase = .setupBackward(playerIndex: 3)
            }
        case .setupBackward:
            if justCompletedIndex > 0 {
                state.phase = .setupBackward(playerIndex: justCompletedIndex - 1)
            } else {
                state.phase = .rollDice(playerIndex: 0)
            }
        default:
            break
        }
    }
}
