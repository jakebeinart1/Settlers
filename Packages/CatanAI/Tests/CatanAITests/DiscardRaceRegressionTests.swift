import Testing
import CatanEngine
@testable import CatanAI

/// Regression coverage for the `Bot.decideDiscard` `preconditionFailure`
/// crash fixed by `Settlers/ViewModels/GameViewModel.swift`'s
/// `isProcessingBotTurns` reentrancy guard (see that property's doc comment
/// for the full mechanism). `GameViewModel` itself lives in the Settlers
/// app target, which this package can't import, so `MockViewModel` below
/// reproduces its exact concurrency shape instead: an `apply(_:by:)` that
/// mutates shared state and spawns a fresh `Task` to drive bot turns, and a
/// `runBotTurnIfNeeded()` bot loop that captures the acting player, awaits a
/// delay, then decides and applies for that same player - the same
/// capture-then-await-then-act shape that let two loop invocations
/// interleave against one `.discarding` phase and hand `Bot.decide` a
/// player no longer pending, crashing at `Bot.swift:115`.
///
/// This test races many concurrent human `.discard`/`.rollDice`/`.endTurn`
/// submissions and redundant `runBotTurnIfNeeded()` kicks (mirroring
/// `ContentView`'s separate Resume call site) against the bot loop, across
/// many random boards, and asserts the whole run completes without
/// trapping. Deleting or disabling `isProcessingBotTurns`'s guard
/// reproduces the exact crash (`Bot.swift:115: Fatal error: no legal
/// discard combination found for ...`), confirmed by temporarily commenting
/// out the guard while developing this test.
@MainActor
final class MockViewModel {
    private(set) var state: GameState
    let humanPlayer = PlayerID(index: 0)
    private var isProcessingBotTurns = false

    init(state: GameState) {
        self.state = state
    }

    func apply(_ move: GameMove, by player: PlayerID) {
        try? RulesEngine.apply(move, by: player, to: &state)
        Task { await self.runBotTurnIfNeeded() }
    }

    func runBotTurnIfNeeded() async {
        guard !isProcessingBotTurns else { return }
        isProcessingBotTurns = true
        defer { isProcessingBotTurns = false }

        var currentBot: PlayerID?
        var actionsForCurrentBot = 0
        let cap = 25

        while let botPlayer = nextBotPlayer() {
            try? await Task.sleep(nanoseconds: UInt64.random(in: 0...2_000_000))

            if botPlayer == currentBot {
                actionsForCurrentBot += 1
            } else {
                currentBot = botPlayer
                actionsForCurrentBot = 1
            }

            let move: GameMove
            if actionsForCurrentBot > cap, case .mainTurn = state.phase {
                move = .endTurn
            } else {
                let bot = Bot(personality: .balanced)
                move = bot.decide(for: state, player: botPlayer)
            }
            try? RulesEngine.apply(move, by: botPlayer, to: &state)
        }
    }

    private func nextBotPlayer() -> PlayerID? {
        switch state.phase {
        case .setupForward(let i), .setupBackward(let i), .rollDice(let i), .mainTurn(let i), .movingRobber(let i):
            let p = PlayerID(index: i)
            return p == humanPlayer ? nil : p
        case .discarding(let pending):
            return pending.first { $0 != humanPlayer }
        case .gameOver:
            return nil
        }
    }
}

@MainActor
@Test func concurrentHumanAndBotDiscardTurnsNeverCrash() async {
    for seed in 0..<60 {
        var rng = DiscardRaceSeededGenerator(seed: UInt64(seed))
        let board = BoardGenerator.randomized(seed: UInt64(seed))
        var initial = GameSetup.newGame(board: board, rng: &rng)

        // Fast-forward through setup directly via the engine (not through
        // the mock loop) so each iteration reaches real dice-rolling/
        // discarding turns quickly.
        while true {
            if case .mainTurn = initial.phase { break }
            if case .gameOver = initial.phase { break }
            let moves = RulesEngine.legalMoves(for: initial)
            guard !moves.isEmpty else { break }
            if case .discarding(let pending) = initial.phase {
                let p = pending.sorted().first!
                let hand = initial.players[p.index].resources
                let count = Robber.discardCount(for: initial.players[p.index])
                let candidate = moves.first(where: { move in
                    guard case .discard(let d) = move else { return false }
                    guard d.values.reduce(0, +) == count else { return false }
                    return d.allSatisfy { (hand[$0] ?? 0) >= $1 }
                }) ?? moves[0]
                try! RulesEngine.apply(candidate, by: p, to: &initial)
                continue
            }
            let player = activePlayer(initial.phase)
            let candidate = moves.randomElement(using: &rng)!
            try! RulesEngine.apply(candidate, by: player, to: &initial)
        }

        let vm = MockViewModel(state: initial)

        // Concurrent "human" submitting their own discard/roll/end-turn
        // moves whenever legal, racing the bot loop's in-flight sleeps.
        var tasks: [Task<Void, Never>] = []
        tasks.append(Task { @MainActor in
            for _ in 0..<150 {
                if case .gameOver = vm.state.phase { break }
                if case .discarding(let pending) = vm.state.phase, pending.contains(vm.humanPlayer) {
                    let hand = vm.state.players[0].resources
                    let count = Robber.discardCount(for: vm.state.players[0])
                    vm.apply(.discard(greedyDiscard(hand: hand, count: count)), by: vm.humanPlayer)
                } else if case .rollDice(let i) = vm.state.phase, i == 0 {
                    vm.apply(.rollDice, by: vm.humanPlayer)
                } else if case .mainTurn(let i) = vm.state.phase, i == 0 {
                    vm.apply(.endTurn, by: vm.humanPlayer)
                }
                try? await Task.sleep(nanoseconds: UInt64.random(in: 0...1_500_000))
            }
        })
        // Redundant concurrent kicks of the bot loop, like ContentView's
        // separate Resume call site racing GameViewModel.apply's own kick.
        for _ in 0..<6 {
            tasks.append(Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64.random(in: 0...3_000_000))
                await vm.runBotTurnIfNeeded()
            })
        }
        for t in tasks { await t.value }

        // Drain any remaining bot work so state settles before the next seed.
        for _ in 0..<20 {
            await vm.runBotTurnIfNeeded()
            if case .gameOver = vm.state.phase { break }
        }
    }
}

private func greedyDiscard(hand: [Resource: Int], count: Int) -> [Resource: Int] {
    var remaining = count
    var result: [Resource: Int] = [:]
    for resource in Resource.allCases {
        guard remaining > 0 else { break }
        let take = min(remaining, hand[resource] ?? 0)
        if take > 0 { result[resource] = take }
        remaining -= take
    }
    return result
}

private func activePlayer(_ phase: GamePhase) -> PlayerID {
    switch phase {
    case .setupForward(let i), .setupBackward(let i), .rollDice(let i), .mainTurn(let i), .movingRobber(let i):
        return PlayerID(index: i)
    case .discarding(let pending): return pending.first!
    case .gameOver: fatalError("game over")
    }
}

/// Deterministic RNG so this test is reproducible (matches the pattern used
/// by `FullGameSimulationTests.SeededGenerator`).
private struct DiscardRaceSeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return state
    }
}
