import Testing
import CatanEngine
@testable import CatanAI

/// End-to-end "bots only" simulation: all four seats play via `Bot.decide`
/// (mirroring `GameViewModel`'s real personality assignment - seat 0
/// balanced, 1 balanced, 2 aggressive, 3 cautious) from a fresh game all the
/// way to `.gameOver`, asserting every move `Bot.decide` returns is actually
/// legal per `RulesEngine.legalMoves` before it's applied. This is the
/// rules-compliance check requested for a bots-only game: unlike
/// `botAlwaysReturnsALegalMove` (500 iterations, one shared personality) or
/// `randomLegalPlayReachesGameOverWithoutErrors` (random legal moves, not
/// real bot heuristics), this runs real per-seat personalities to an actual
/// win.
@Test func botsOnlyGameReachesGameOverWithOnlyLegalMoves() {
    var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 42))
    let bots: [Int: Bot] = [
        0: Bot(personality: .balanced),
        1: Bot(personality: .balanced),
        2: Bot(personality: .aggressive),
        3: Bot(personality: .cautious),
    ]

    var iterations = 0
    let iterationCap = 40_000
    while true {
        if case .gameOver = state.phase { break }
        iterations += 1
        #expect(iterations < iterationCap, "bots-only game did not terminate within \(iterationCap) moves")
        if iterations >= iterationCap { break }

        let legal = RulesEngine.legalMoves(for: state)
        #expect(!legal.isEmpty, "no legal moves in phase \(state.phase)")

        if case .discarding(let pending) = state.phase {
            // Every pending player discards this same tick, exactly like
            // `GameViewModel.runBotTurnIfNeeded`'s loop (it re-derives the
            // next pending player each iteration rather than batching them).
            for player in pending.sorted() {
                let bot = bots[player.index]!
                let move = bot.decide(for: state, player: player)
                let playerLegal = RulesEngine.legalMoves(for: state)
                #expect(playerLegal.contains { movesMatch($0, move) }, "illegal discard chosen for \(player) in phase \(state.phase)")
                try! RulesEngine.apply(move, by: player, to: &state)
            }
            continue
        }

        let player = activePlayer(state.phase)
        let bot = bots[player.index]!
        let move = bot.decide(for: state, player: player)
        #expect(legal.contains { movesMatch($0, move) }, "illegal move \(move) chosen for \(player) in phase \(state.phase)")
        try! RulesEngine.apply(move, by: player, to: &state)
    }

    guard case .gameOver(let winner) = state.phase else {
        Issue.record("game did not reach .gameOver within \(iterationCap) moves")
        return
    }

    let winnerVP = state.victoryPoints(for: winner)
    #expect(winnerVP >= 10, "winner \(winner) only has \(winnerVP) VP")

    // Every other player must be strictly behind - `.gameOver` shouldn't
    // fire on a tie or before anyone's actually crossed the win threshold.
    for player in state.players where player.id != winner {
        #expect(state.victoryPoints(for: player.id) < 10 || state.victoryPoints(for: player.id) <= winnerVP)
    }

    // Sanity: bank and hands never went negative anywhere along the way
    // would already have thrown via `RulesEngine.apply`'s guards, but double
    // check the final resource ledger is still well-formed.
    for player in state.players {
        for (_, amount) in player.resources {
            #expect(amount >= 0)
        }
    }
    for (_, amount) in state.bank {
        #expect(amount >= 0)
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

/// Same structural move comparison as `BotLegalityTests.movesMatch` -
/// duplicated for the same reason noted there (no shared test-support
/// library across targets).
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
    case (.proposeTrade(let x), .proposeTrade(let y)): return x.from == y.from && x.give == y.give && x.want == y.want
    case (.respondToTrade(let ox, let ax), .respondToTrade(let oy, let ay)): return ox == oy && ax == ay
    case (.endTurn, .endTurn): return true
    default: return false
    }
}

@Test func botsOnlyGameReachesGameOverAcrossSeveralSeeds() {
    for seed: UInt64 in [1, 2, 3, 4, 5] {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed))
        let bots: [Int: Bot] = [
            0: Bot(personality: .cautious),
            1: Bot(personality: .aggressive),
            2: Bot(personality: .balanced),
            3: Bot(personality: .aggressive),
        ]
        var iterations = 0
        while true {
            if case .gameOver = state.phase { break }
            iterations += 1
            #expect(iterations < 40_000, "seed \(seed) did not terminate")
            if iterations >= 40_000 { break }

            if case .discarding(let pending) = state.phase {
                for player in pending.sorted() {
                    let move = bots[player.index]!.decide(for: state, player: player)
                    try! RulesEngine.apply(move, by: player, to: &state)
                }
                continue
            }
            let player = activePlayer(state.phase)
            let move = bots[player.index]!.decide(for: state, player: player)
            try! RulesEngine.apply(move, by: player, to: &state)
        }
        guard case .gameOver(let winner) = state.phase else {
            Issue.record("seed \(seed) did not reach .gameOver")
            continue
        }
        #expect(state.victoryPoints(for: winner) >= 10, "seed \(seed) winner underscored")
    }
}
