import Testing
import CatanEngine
@testable import CatanAI

private func conquestMainTurn(seed: UInt64 = 1) -> GameState {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed, variant: .conquest)
    // Finish setup the way bots would, so buildings exist.
    var session = GameSession(state: state, policies: Dictionary(uniqueKeysWithValues:
        state.players.map { ($0.id, HeuristicPolicy(personality: .balanced, id: "balanced") as any Policy) }), policySeed: seed)
    while case .setupForward = session.state.phase { _ = try? session.step() }
    while case .setupBackward = session.state.phase { _ = try? session.step() }
    state = session.state
    state.phase = .mainTurn(playerIndex: 0)
    return state
}

@Test func aBotTakesAHexWhenItHoldsEnoughToWinIt() {
    var state = conquestMainTurn()
    state.armyHands[state.players[0].id] = [9]
    let legal = RulesEngine.legalMoves(for: state)
    let move = ConquestHeuristics.chooseDeploy(state: state, player: state.players[0].id, legal: legal)
    guard case .deployArmy(let hex, let strengths)? = move else {
        Issue.record("expected a deploy, got \(String(describing: move))"); return
    }
    let after = Conquest.outcome(of: strengths.reduce(0, +), against: state.garrisons[hex], by: state.players[0].id)
    #expect(after?.owner == state.players[0].id)
}

@Test func aBotDoesNotThrowCardsAtAHexItCannotTake() {
    var state = conquestMainTurn()
    state.armyHands[state.players[0].id] = [1]
    for (hex, _) in state.garrisons { state.garrisons[hex] = Garrison(owner: nil, strength: 5) }
    let legal = RulesEngine.legalMoves(for: state)
    #expect(ConquestHeuristics.chooseDeploy(state: state, player: state.players[0].id, legal: legal) == nil)
}

@Test func aStandardGameNeverAsksForArmyMoves() {
    var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
    state.phase = .mainTurn(playerIndex: 0)
    #expect(!ConquestHeuristics.shouldBuyArmyCard(state: state, player: state.players[0].id))
}

@Test func seededConquestGamesFinishWithOnlyLegalMoves() throws {
    for seed: UInt64 in 1...3 {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed, variant: .conquest)
        var session = GameSession(state: state, policies: Dictionary(uniqueKeysWithValues:
            state.players.map { ($0.id, HeuristicPolicy(personality: .balanced, id: "balanced") as any Policy) }), policySeed: seed)
        var armyMoves = 0
        for _ in 0..<6_000 {
            guard let step = try session.step() else { break }
            if case .deployArmy = step.move { armyMoves += 1 }
        }
        #expect({ if case .gameOver = session.state.phase { true } else { false } }(), "seed \(seed) did not finish")
        #expect(armyMoves > 0, "seed \(seed): bots never deployed")
    }
}

@Test func aBoldBotBuysAnArmyCardBeforeBuildingAndAnIdleOneDoesNot() {
    var state = conquestMainTurn()
    state.armyHands = [:]
    state.players[0].resources = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]
    let seat = state.players[0].id
    var rng = RandomSource(seed: 1)
    let bold = Bot(personality: .balanced, armyBuying: .bold).decide(for: state, player: seat, rng: &rng)
    let idle = Bot(personality: .balanced).decide(for: state, player: seat, rng: &rng)
    #expect(bold == .buyArmyCard)
    #expect(idle != .buyArmyCard, "idle bot should build first, got \(idle)")
}

@Test func aTargetedBotBuysOnlyWhenOneMoreCardWouldTakeAGoodHex() throws {
    var state = conquestMainTurn()
    let seat = state.players[0].id
    for hex in state.garrisons.keys { state.garrisons[hex] = Garrison(owner: nil, strength: 5) }
    let goodReachable = state.board.tiles.contains {
        ($0.numberToken.map(DiceOdds.pips) ?? 0) >= 4 && Conquest.canDeploy(to: $0.coordinate, by: seat, in: state)
    }
    try #require(goodReachable, "seed must give seat 0 a building on a 5, 6, 8 or 9")
    state.players[0].resources = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1, .ore: 1]
    let bot = Bot(personality: .balanced, armyBuying: .targeted)
    var rng = RandomSource(seed: 1)

    state.armyHands = [:]
    #expect(bot.decide(for: state, player: seat, rng: &rng) != .buyArmyCard, "0 + ~4 cannot beat 5")
    state.armyHands = [seat: [2]]
    #expect(bot.decide(for: state, player: seat, rng: &rng) == .buyArmyCard, "2 + ~4 beats 5")
}

@Test func silencingTheLeaderIsWorthMoreThanSilencingAnyoneElse() throws {
    var state = conquestMainTurn()
    let me = state.players[0].id
    let hex = try #require(state.board.tiles.first {
        $0.numberToken != nil && Conquest.canDeploy(to: $0.coordinate, by: me, in: state)
    }).coordinate
    let rivalCorner = try #require(HexGeometry.corners(of: hex).first { corner in
        !state.players.contains { $0.settlements.contains(corner) || $0.cities.contains(corner) }
    })
    state.players[1].settlements.insert(rivalCorner)
    let far = state.board.onBoardVertices.sorted().suffix(8)
    // Seat 2 leads, so silencing seat 1 is ordinary denial...
    state.players[2].cities.formUnion(far.suffix(4))
    let asEqual = ConquestHeuristics.hexValue(hex, for: me, in: state)
    // ...then seat 1 pulls ahead of everyone.
    state.players[2].cities.subtract(far.suffix(4))
    state.players[1].cities.formUnion(far.prefix(4))
    let asLeader = ConquestHeuristics.hexValue(hex, for: me, in: state)
    #expect(asLeader > asEqual)
}
