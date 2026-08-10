import Testing
import CatanEngine
@testable import CatanAI

@Test func botAlwaysReturnsALegalMove() {
    var state = GameSetup.newGame(board: BoardGenerator.standard())
    let bot = Bot(personality: .balanced)
    let rng = SeededGenerator(seed: 99)
    _ = rng
    for _ in 0..<500 {
        if case .gameOver = state.phase { break }
        let player = activePlayer(state.phase)
        let legal = RulesEngine.legalMoves(for: state)
        let chosen = bot.decide(for: state, player: player)
        #expect(legal.contains(where: { movesMatch($0, chosen) }))
        try! RulesEngine.apply(chosen, by: player, to: &state)
    }
}

// activePlayer/SeededGenerator duplicated here from CatanEngineTests (small, test-only, acceptable duplication
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
    case (.proposeTrade(let x), .proposeTrade(let y)): return x.id == y.id && x.from == y.from && x.give == y.give && x.want == y.want
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

/// Deterministic RNG so this test is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
