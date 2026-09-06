import CatanEngine

/// Frozen Eli6th codec v1 action IDs, separate from Empires' ActionSpace.
/// Board slots come exclusively from the shared upstream layout. A nil mapping
/// means this profile cannot represent the move; it is never an end-turn alias.
enum UpstreamActions {
    static let count = 299
    static let knight = 296
    static let roadBuilding = 297
    static let resources: [Resource] = [.grain, .wool, .lumber, .brick, .ore]

    static func root(_ move: GameMove, layout: UpstreamBoardLayout, state: GameState) -> Int? {
        switch move {
        case .placeInitialSettlement(let vertex), .buildSettlement(let vertex):
            return layout.vertices.firstIndex(of: vertex)
        case .buildCity(let vertex): return layout.vertices.firstIndex(of: vertex).map { 54 + $0 }
        case .placeInitialRoad(let edge), .buildRoad(let edge): return road(edge, layout: layout)
        case .moveRobber(let tile, _): return robber(tile, layout: layout)
        case .playKnight: return knight
        case .playRoadBuilding: return roadBuilding
        case .playMonopoly(let resource): return 208 + resourceIndex(resource)
        case .playYearOfPlenty(let first, let second):
            let low = min(resourceIndex(first), resourceIndex(second))
            let high = max(resourceIndex(first), resourceIndex(second))
            return 213 + low * (11 - low) / 2 + high - low
        case .bankTrade(let give, let get): return bankTrade(give: give, get: get, state: state)
        case .rollDice: return 294
        case .buyDevCard: return 295
        case .endTurn: return 298
        case .discard, .proposeTrade, .respondToTrade: return nil
        }
    }

    static func road(_ edge: EdgeID, layout: UpstreamBoardLayout) -> Int? {
        layout.edges.firstIndex(of: edge).map { 108 + $0 }
    }

    static func robber(_ tile: HexCoordinate, layout: UpstreamBoardLayout) -> Int? {
        layout.tiles.firstIndex(of: tile).map { 180 + $0 }
    }

    static func victim(_ victim: PlayerID?, seat: PlayerID, playerCount: Int) -> Int? {
        guard let victim else { return 202 }
        guard (0..<playerCount).contains(victim.index), victim != seat else { return nil }
        let relative = (victim.index + playerCount - seat.index) % playerCount
        return 198 + relative
    }

    static func resourceIndex(_ resource: Resource) -> Int {
        resources.firstIndex(of: resource)!
    }

    static func isPlayerTrade(_ move: GameMove) -> Bool {
        switch move {
        case .proposeTrade, .respondToTrade: return true
        default: return false
        }
    }

    static func unsupportedBeforeRoll(_ move: GameMove) -> Bool {
        switch move {
        case .playRoadBuilding, .playYearOfPlenty, .playMonopoly: return true
        default: return false
        }
    }

    private static func bankTrade(give: [Resource: Int], get: [Resource: Int], state: GameState) -> Int? {
        guard give.count == 1, get.count == 1, let offered = give.first, let received = get.first,
              received.value == 1, offered.key != received.key,
              let index = state.phase.awaitingSeatIndex else { return nil }
        let rate = Trading.bestRate(for: offered.key, player: state.players[index].id, state: state)
        guard offered.value == rate else { return nil }
        let from = resourceIndex(offered.key)
        let to = resourceIndex(received.key)
        return 228 + from * 4 + (to < from ? to : to - 1)
    }
}

/// One masked decision at a time. Duplicate IDs (compound prefixes and reversed
/// Year of Plenty pairs) are deliberately collapsed, never added together.
struct UpstreamActionScorer: Sendable {
    typealias Predictor = @Sendable ([Float]) -> (logits: [Float], value: Float)
    typealias Encoder = @Sendable (GameState, PlayerID, UpstreamDecisionContext?) throws -> [Float]

    let predict: Predictor
    let encode: Encoder

    enum ScoringError: Error { case noRepresentableAction, invalidPrediction, incompleteCompound }

    func choose(_ allowed: [Int], state: GameState, seat: PlayerID,
                context: UpstreamDecisionContext) throws -> Int {
        let ordered = Set(allowed).sorted()
        guard let first = ordered.first, ordered.allSatisfy({ (0..<UpstreamActions.count).contains($0) }) else {
            throw ScoringError.noRepresentableAction
        }
        // Upstream's environment automatically resolves singleton masks.
        if ordered.count == 1 { return first }
        let result = predict(try encode(state, seat, context))
        guard result.logits.count == UpstreamActions.count,
              ordered.allSatisfy({ result.logits[$0].isFinite }) else { throw ScoringError.invalidPrediction }
        return ordered.dropFirst().reduce(first) { best, candidate in
            result.logits[candidate] > result.logits[best] ? candidate : best
        }
    }
}
