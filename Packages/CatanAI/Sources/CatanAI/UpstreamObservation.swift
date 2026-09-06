import CatanEngine

/// Private sequential choices override context without committing a partial move.
/// Numeric phases are the frozen upstream v1 enum values, not Empires enum order.
public struct UpstreamDecisionContext: Sendable {
    private typealias GamePhase = UpstreamCodec.GamePhase
    private typealias TurnPhase = UpstreamCodec.TurnPhase
    public var gamePhase: Int
    public var turnPhase: Int
    public var turnOwner: PlayerID
    public var hasRolled: Bool
    public var roadsToPlace = 0
    public var discardsRemaining = 0

    public init(state: GameState, seat: PlayerID) {
        turnOwner = PlayerID(index: state.phase.awaitingSeatIndex ?? seat.index)
        hasRolled = false
        // Upstream advances setup_player_idx but leaves current_player at 0
        // throughout setup. This feature is not the actor whose mask we score.
        switch state.phase {
        case .setupForward:
            gamePhase = GamePhase.setupForward; turnPhase = TurnPhase.rollDice; turnOwner = PlayerID(index: 0)
        case .setupBackward:
            gamePhase = GamePhase.setupBackward; turnPhase = TurnPhase.rollDice; turnOwner = PlayerID(index: 0)
        case .rollDice:
            gamePhase = GamePhase.playing
            turnPhase = state.devCardPlayedThisTurn == nil ? TurnPhase.beforeRoll : TurnPhase.rollDice
        case .mainTurn: gamePhase = GamePhase.playing; turnPhase = TurnPhase.mainTurn; hasRolled = true
        case .discarding:
            gamePhase = GamePhase.playing; turnPhase = TurnPhase.discarding; hasRolled = true
            turnOwner = PlayerID(index: state.robberMoverIndex ?? seat.index)
            discardsRemaining = state.players[seat.index].resources.values.reduce(0, +) / 2
        case .movingRobber: gamePhase = GamePhase.playing; turnPhase = TurnPhase.movingRobber; hasRolled = true
        case .gameOver: gamePhase = GamePhase.finished; turnPhase = TurnPhase.mainTurn; hasRolled = true
        }
    }
}

/// Semantic port of Eli6th catan-env obs.rs v1 (MIT; see bundled attribution).
/// It deliberately does not modify StateEncoding's existing 5,182-slot contract.
/// Perfect information matches the trained checkpoint and the app's existing
/// policy access. Unsupported trade negotiation is handled by a named fallback,
/// never compressed into the upstream single-offer representation.
public enum UpstreamObservation {
    public static let count = 1_350
    public static let resources = UpstreamCodec.resources
    public static let cards: [DevCardType] = [.knight, .victoryPoint, .roadBuilding, .yearOfPlenty, .monopoly]
    public enum EncodingError: Error { case unknownTurnHistory, invalidSeat, invalidContext }

    public static func encode(state: GameState, seat: PlayerID,
                              context supplied: UpstreamDecisionContext? = nil) throws -> [Float] {
        guard state.players.indices.contains(seat.index), state.players[seat.index].id == seat else {
            throw EncodingError.invalidSeat
        }
        guard let turn = state.completedTurnCount else { throw EncodingError.unknownTurnHistory }
        let context = supplied ?? UpstreamDecisionContext(state: state, seat: seat)
        guard UpstreamCodec.GamePhase.validRange.contains(context.gamePhase),
              UpstreamCodec.TurnPhase.validRange.contains(context.turnPhase),
              state.players.indices.contains(context.turnOwner.index) else { throw EncodingError.invalidContext }
        let layout = try UpstreamBoardLayout(board: state.board)
        var out = [Float](repeating: 0, count: count)
        encodeBoard(state, seat: seat, layout: layout, out: &out)
        encodePlayers(state, seat: seat, owner: context.turnOwner, out: &out)
        encodePrivate(state, seat: seat, out: &out)
        for (index, resource) in resources.enumerated() { out[1_309 + index] = Float(state.bank[resource, default: 0]) / 19 }
        encodeContext(state, turn: turn, context: context, out: &out)
        return out
    }

    private static func relative(_ owner: PlayerID, seat: PlayerID, state: GameState) -> Int {
        (owner.index + state.players.count - seat.index) % state.players.count
    }

    private static func encodeBoard(_ state: GameState, seat: PlayerID,
                                    layout: UpstreamBoardLayout, out: inout [Float]) {
        let tileMap = Dictionary(uniqueKeysWithValues: state.board.tiles.map { ($0.coordinate, $0) })
        for (index, coordinate) in layout.tiles.enumerated() {
            guard let tile = tileMap[coordinate] else { preconditionFailure("layout tile absent") }
            let resource: Int
            switch tile.kind {
            case .desert: resource = 5
            case .resource(let kind): resource = resources.firstIndex(of: kind)!
            }
            out[index * 8 + resource] = 1
            if let number = tile.numberToken { out[index * 8 + 6] = Float(6 - abs(7 - number)) / 36 * 7.2 }
            out[index * 8 + 7] = coordinate == state.board.robberTile ? 1 : 0
        }
        encodeVertices(state, seat: seat, layout: layout, out: &out)
        for (index, edge) in layout.edges.enumerated() {
            if let owner = state.players.first(where: { $0.roads.contains(edge) }) {
                out[908 + index * 4 + relative(owner.id, seat: seat, state: state)] = 1
            }
        }
    }

    private static func encodeVertices(_ state: GameState, seat: PlayerID,
                                       layout: UpstreamBoardLayout, out: inout [Float]) {
        for (index, vertex) in layout.vertices.enumerated() {
            let base = 152 + index * 14
            for player in state.players {
                let slot = base + relative(player.id, seat: seat, state: state) * 2
                if player.settlements.contains(vertex) { out[slot] = 1 }
                if player.cities.contains(vertex) { out[slot + 1] = 1 }
            }
            if let port = state.board.ports.first(where: { $0.vertexA == vertex || $0.vertexB == vertex }) {
                out[base + 8 + portIndex(port.kind)] = 1
            }
        }
    }

    private static func portIndex(_ kind: PortKind) -> Int {
        switch kind {
        case .generic: return 0
        case .resource(let resource): return resources.firstIndex(of: resource)! + 1
        }
    }

    private static func encodePlayers(_ state: GameState, seat: PlayerID, owner: PlayerID, out: inout [Float]) {
        for player in state.players {
            let base = 1_196 + relative(player.id, seat: seat, state: state) * 17
            out[base] = Float(player.resources.values.reduce(0, +)) / 19
            out[base + 1] = Float(player.devCards.count) / 25
            out[base + 2] = Float(player.playedKnights) / 14
            out[base + 3] = Float(state.publicVictoryPoints(for: player.id)) / Float(state.victoryPointTarget)
            out[base + 4] = Float(5 - player.settlements.count) / 5
            out[base + 5] = Float(4 - player.cities.count) / 4
            out[base + 6] = Float(15 - player.roads.count) / 15
            // Upstream caches the raw count below five: it is sufficient for
            // awarding Longest Road, and is what these weights saw in training.
            // Keep that feature convention here, never in Empires' rules.
            let roadCount = player.roads.count
            let upstreamLength = roadCount < 5 ? roadCount : LongestRoad.length(for: player, in: state)
            out[base + 7] = Float(upstreamLength) / 15
            out[base + 8] = state.longestRoadPlayer == player.id ? 1 : 0
            out[base + 9] = state.largestArmyPlayer == player.id ? 1 : 0
            let buildings = player.settlements.union(player.cities)
            for port in state.board.ports where buildings.contains(port.vertexA) || buildings.contains(port.vertexB) {
                out[base + 10 + portIndex(port.kind)] = 1
            }
            out[base + 16] = player.id == owner ? 1 : 0
        }
    }

    private static func encodePrivate(_ state: GameState, seat: PlayerID, out: inout [Float]) {
        for player in state.players {
            let relative = relative(player.id, seat: seat, state: state)
            let base = relative == 0 ? 1_264 : 1_279 + (relative - 1) * 10
            for index in 0..<5 {
                out[base + index] = Float(player.resources[resources[index], default: 0]) / 19
                out[base + 5 + index] = Float(player.devCards.filter { $0 == cards[index] }.count) / 5
                if relative == 0 {
                    out[base + 10 + index] = Float(state.devCardsBoughtThisTurn[seat, default: []].filter { $0 == cards[index] }.count) / 2
                }
            }
        }
    }

    private static func encodeContext(_ state: GameState, turn: Int, context: UpstreamDecisionContext, out: inout [Float]) {
        let base = 1_314
        out[base + context.gamePhase] = 1
        if context.gamePhase == UpstreamCodec.GamePhase.playing { out[base + 4 + context.turnPhase] = 1 }
        out[base + 13] = Float(state.lastDiceRoll ?? 0) / 12
        out[base + 14] = context.hasRolled ? 1 : 0
        out[base + 15] = Float(turn) / 1_000
        out[base + 16] = Float(state.victoryPointTarget) / 10
        out[base + 17] = Float(context.roadsToPlace) / 2
        out[base + 18] = Float(max(0, 3 - state.tradesProposedThisTurn)) / 3
        out[base + 19] = Float(context.discardsRemaining) / 10
    }
}
