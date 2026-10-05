import Foundation
import Testing
@testable import CatanEngine

private struct DiceFairnessPolicy: Policy {
    let id = "fairness-roll"
    let draws: Int

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        for _ in 0..<draws { _ = rng.next() }
        return .rollDice
    }
}

/// Exact snapshot comparisons detect actor weighting, rerolls and policy RNG
/// leakage. They do not rely on a sample happening to fit a statistical bound.
@Suite struct DiceFairnessTests {
    @Test(arguments: EngineFairnessCase.all)
    func diceMatchTwoUnweightedDrawsRegardlessOfSeatOrHand(fixture: EngineFairnessCase) throws {
        for seed: UInt64 in [0, 1, 7, 42, 999, .max] {
            var state = fixture.state(beforeRoll: true)
            state.rng = RandomSource(seed: seed)
            var expectedRNG = state.rng
            let dice = (0..<2).map { _ in Int.random(in: 1...6, using: &expectedRNG) }
            let expectedTotal = dice.reduce(0, +)
            let events = try RulesEngine.apply(.rollDice, by: fixture.actor, to: &state)
            #expect(events == [.rolled(fixture.actor, total: expectedTotal)])
            #expect(state.lastDiceRoll == expectedTotal)
            #expect(state.rng == expectedRNG, "no reroll or extra outcome draw is allowed")

            var rich = fixture.state(beforeRoll: true)
            rich.players[fixture.seat].resources = [.ore: 19, .grain: 19]
            rich.players[fixture.seat].playedKnights = 5
            rich.rng = RandomSource(seed: seed)
            let richEvents = try RulesEngine.apply(.rollDice, by: fixture.actor, to: &rich)
            #expect(richEvents == events, "hand size and army status cannot select a better roll")
            #expect(rich.rng == state.rng)
        }
    }

    @Test(arguments: EngineFairnessCase.all)
    func humanAndBotsWithDifferentPolicyDrawCountsGetIdenticalDice(fixture: EngineFairnessCase) throws {
        let state = fixture.state(beforeRoll: true)
        var human = GameSession(state: state, policies: [:], policySeed: 11)
        let external = try human.applyExternal(.rollDice, by: fixture.actor)
        for draws in [0, 1, 100] {
            var bot = GameSession(state: state, policies: [fixture.actor: DiceFairnessPolicy(draws: draws)],
                                  policySeed: UInt64(draws + 1))
            let next = try bot.step()
            let automated = try #require(next)
            #expect(automated.events == external.events)
            #expect(bot.state == human.state, "controller choice and policy randomness cannot change production")
        }
    }

    @Test(arguments: EngineFairnessCase.all)
    func choosingAMoveDoesNotAdvanceEngineDiceAndResumePreservesThem(fixture: EngineFairnessCase) throws {
        let state = fixture.state(beforeRoll: true)
        let policies: [PlayerID: any Policy] = [fixture.actor: DiceFairnessPolicy(draws: 100)]
        var session = GameSession(state: state, policies: policies, policySeed: 9)
        let decision = session.decideNext()
        #expect(decision?.move == .rollDice)
        #expect(session.state == state)
        let data = try JSONEncoder().encode(session.checkpoint)
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: data)
        var resumed = try GameSession(checkpoint: checkpoint, policies: policies)
        let original = try session.commit(seat: fixture.actor, move: .rollDice)
        let restored = try resumed.commit(seat: fixture.actor, move: .rollDice)
        #expect(original.events == restored.events)
        #expect(session.state == resumed.state)
    }

    @Test(arguments: EngineFairnessCase.all)
    func anUnauthorizedRollCannotAdvanceTheRandomSequence(fixture: EngineFairnessCase) throws {
        var state = fixture.state(beforeRoll: true)
        let before = state
        #expect(throws: MoveError.notYourTurn) {
            try RulesEngine.apply(.rollDice, by: fixture.victim, to: &state)
        }
        #expect(state == before)
    }
}
