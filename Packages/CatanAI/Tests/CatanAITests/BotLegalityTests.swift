import Testing
import CatanEngine
@testable import CatanAI

@Test func botAlwaysReturnsALegalMove() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let bot = Bot(personality: .balanced)
    for _ in 0..<500 {
        if case .gameOver = state.phase { break }
        let player = activePlayer(state.phase)
        let legal = RulesEngine.legalMoves(for: state)
        let chosen = bot.decide(for: state, player: player)
        #expect(legal.contains(where: { movesMatch($0, chosen) }))
        try! RulesEngine.apply(chosen, by: player, to: &state)
    }
}

@Test func expandedSetupRoadPointsTowardTheBestOutwardEndpoint() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(.expanded), mode: .expanded)
    let player = state.players[0].id
    let bot = Bot(personality: .balanced)

    for settlement in state.board.onBoardVertices.sorted() {
        let edges = state.board.edgesTouching(settlement)
        guard edges.count > 1 else { continue }
        state.players[0].settlements = [settlement]
        state.phase = .setupForward(playerIndex: 0)
        let legal = RulesEngine.legalMoves(for: state)
        let covered = Set(state.board.neighborTiles(of: settlement).compactMap { coordinate in
            state.board.tiles.first(where: { $0.coordinate == coordinate }).flatMap { tile in
                if case .resource(let resource) = tile.kind { return resource }
                return nil
            }
        })
        let scored = edges.map { edge -> (EdgeID, Double) in
            let (a, b) = state.board.vertices(of: edge)
            let outward = a == settlement ? b : a
            return (edge, PlacementHeuristics.score(vertex: outward, board: state.board, alreadyCovered: covered))
        }
        guard let expected = scored.max(by: { $0.1 < $1.1 }),
              scored.filter({ $0.1 == expected.1 }).count == 1,
              case .placeInitialRoad(let firstEdge) = legal.first,
              firstEdge != expected.0 else { continue }

        var rng = RandomSource(seed: 1)
        let chosen = bot.decide(for: state, player: player, legalMoves: legal, rng: &rng)
        #expect(movesMatch(chosen, .placeInitialRoad(expected.0)))
        return
    }
    Issue.record("expanded fixture has no setup vertex with differentiated outward endpoints")
}

@Test func expandedDevelopmentCardFallbackHonorsPermanentBuildReserve() {
    let bot = Bot(personality: .balanced)
    let player = PlayerID(index: 0)
    let legal: [GameMove] = [.buyDevCard, .endTurn]

    var expanded = GameSetup.newGame(board: BoardGenerator.standard(.expanded), mode: .expanded)
    expanded.phase = .mainTurn(playerIndex: 0)
    expanded.players[0].settlements = [expanded.board.onBoardVertices.sorted()[0]]
    expanded.players[0].resources = [.ore: 1, .grain: 1, .wool: 1]
    var expandedRNG = RandomSource(seed: 1)
    let expandedChoice = bot.decide(for: expanded, player: player, legalMoves: legal, rng: &expandedRNG)
    #expect(movesMatch(expandedChoice, .endTurn))

    var classic = GameSetup.newGame(board: BoardGenerator.standard(), mode: .classic)
    classic.phase = .mainTurn(playerIndex: 0)
    classic.players[0].resources = [.ore: 1, .grain: 1, .wool: 1]
    var classicRNG = RandomSource(seed: 1)
    let classicChoice = bot.decide(for: classic, player: player, legalMoves: legal, rng: &classicRNG)
    #expect(movesMatch(classicChoice, .buyDevCard))
}

// activePlayer duplicated here from CatanEngineTests (small, test-only, acceptable duplication
// across package test targets since they can't share test code without a shared test-support library).

/// `GameMove` isn't `Equatable` (its cases carry `[Resource: Int]`
/// dictionaries, which are), so this does a structural case-by-case
/// comparison instead of the brief's original `"\($0)" == "\($1)"` string
/// check - two structurally-equal dictionaries built via different code
/// paths aren't guaranteed to print their keys in the same order, which made
/// the naive string comparison spuriously fail (e.g. `discard([.brick: 3,
/// .wool: 1])` printed differently depending on construction order despite
/// being the same discard).
private func movesMatch(_ a: GameMove, _ b: GameMove) -> Bool {
    switch (a, b) {
    case (.placeInitialSettlement(let x), .placeInitialSettlement(let y)): return x == y
    case (.placeInitialRoad(let x), .placeInitialRoad(let y)): return x == y
    case (.rollDice, .rollDice): return true
    case (.buildRoad(let x), .buildRoad(let y)): return x == y
    case (.buildSettlement(let x), .buildSettlement(let y)): return x == y
    case (.buildCity(let x), .buildCity(let y)): return x == y
    case (.buyDevCard, .buyDevCard): return true
    case (.playKnight(let mx, let sx), .playKnight(let my, let sy)): return mx == my && sx == sy
    case (.playRoadBuilding(let x1, let x2), .playRoadBuilding(let y1, let y2)): return x1 == y1 && x2 == y2
    case (.playYearOfPlenty(let x1, let x2), .playYearOfPlenty(let y1, let y2)): return x1 == y1 && x2 == y2
    case (.playMonopoly(let x), .playMonopoly(let y)): return x == y
    case (.moveRobber(let tx, let sx), .moveRobber(let ty, let sy)): return tx == ty && sx == sy
    case (.discard(let x), .discard(let y)): return x == y
    case (.bankTrade(let gx, let ax), .bankTrade(let gy, let ay)): return gx == gy && ax == ay
    // Deliberately ignores `id`: `RulesEngine.legalMoves` mints a fresh
    // random UUID for every `.proposeTrade` candidate on *each* call (see
    // `TradeOffer.init`'s `id: UUID = UUID()` default), so two independent
    // calls over the same `state` - one to compute `legal` above, one made
    // internally by `Bot.decide` - never share ids for the same underlying
    // offer. The id carries no meaning for legality, only `from`/`give`/
    // `want` do, so comparing it here was always a latent false-negative
    // bug, just unreachable before `Bot.decide` could return `.proposeTrade`.
    case (.proposeTrade(let x), .proposeTrade(let y)): return x.from == y.from && x.give == y.give && x.want == y.want
    case (.respondToTrade(let ox, let ax), .respondToTrade(let oy, let ay)): return ox == oy && ax == ay
    case (.endTurn, .endTurn): return true
    default: return false
    }
}

private func activePlayer(_ phase: GamePhase) -> PlayerID {
    switch phase {
    case .setupForward(let i), .setupBackward(let i), .rollDice(let i), .mainTurn(let i), .movingRobber(let i):
        return PlayerID(index: i)
    case .discarding(let pending): return pending.first!
    case .gameOver: fatalError("game over")
    }
}
