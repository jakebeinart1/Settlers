import Testing
import CatanEngine
@testable import CatanAI

/// Jake's ghost sat at 7 VP holding 25-32 cards for eight straight turns,
/// rolling and ending (TestFlight game `8B5DB719`, 2026-09-28). His rule: "stay
/// under seven... if you have 10 to 15 you should play out of that... you are
/// literally wasting cards." These pin it for Expert and for ghosts.
@Suite struct HandDisciplineTests {

    /// Seat 0 in its own main turn holding Jake's frozen hand: brick, grain,
    /// lumber and wool, no ore. Proposals are left out, as they were once the
    /// table had refused him.
    private func frozenHand(_ hand: [Resource: Int], seed: UInt64 = 81) -> (GameObservation, GameState) {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.players[0].resources = hand
        state.phase = .mainTurn(playerIndex: 0)
        let seat = state.players[0].id
        let legal = RulesEngine.legalMoves(for: state, seat: seat).filter {
            if case .proposeTrade = $0 { return false }
            return true
        }
        return (GameObservation(seat: seat, state: state, legalMoves: legal), state)
    }

    private let jakesHand: [Resource: Int] = [.brick: 5, .grain: 11, .lumber: 5, .wool: 4]

    /// A person whose habits say "end the turn, never trade, never build":
    /// far stronger than Jake's own (-1.3 bank trade, -0.7 end turn), so that
    /// only the rule can explain the ghost spending.
    private func turnEnder() -> PersonModel {
        var person = PersonModel.anchored(at: .forMode(.classic))
        for (label, value) in [("endTurn", 50.0), ("bankTrade", -50.0), ("buildRoad", -50.0),
                               ("buildSettlement", -50.0), ("buildCity", -50.0), ("buyDevCard", -50.0)] {
            person.theta[StyleFeatures.labels.firstIndex(of: label)!] = value
        }
        return person
    }

    @Test func onlyAnOwnTurnOverTheThresholdMustSpend() {
        let (_, over) = frozenHand(jakesHand)
        let seat = over.players[0].id
        #expect(HandDiscipline.mustSpend(seat, in: over))
        #expect(!HandDiscipline.mustSpend(over.players[1].id, in: over), "not another seat's turn")
        let (_, atSeven) = frozenHand([.brick: 2, .grain: 2, .lumber: 2, .wool: 1])
        #expect(!HandDiscipline.mustSpend(seat, in: atSeven), "seven is allowed")
    }

    @Test func expertSpendsDownAHoardedHand() {
        let (observation, _) = frozenHand(jakesHand)
        var rng = RandomSource(seed: 1)
        let move = EvaluationPolicy().decide(observation, rng: &rng)
        #expect(HandDiscipline.spends(move), "Expert ended a 25-card turn with \(move)")
    }

    /// The ghost from Jake's game, in miniature: its habits want to end the
    /// turn, and without the rule it does - which is what proves the rule is
    /// what makes it spend.
    @Test func aGhostSpendsDownEvenWhenItsHabitsSayEndTheTurn() {
        let (observation, _) = frozenHand(jakesHand)
        var rng = RandomSource(seed: 1)
        let unruled = GhostPolicy(person: turnEnder(), lambda: 1, handDiscipline: false).decide(observation, rng: &rng)
        #expect(unruled == .endTurn, "the control arm must reproduce the freeze, got \(unruled)")
        let ruled = GhostPolicy(person: turnEnder(), lambda: 1).decide(observation, rng: &rng)
        #expect(HandDiscipline.spends(ruled), "the ghost ended a 25-card turn with \(ruled)")
    }

    /// The rule is a floor, not a compulsion: at or under seven the same
    /// ghost may still end its turn.
    @Test func atSevenAGhostMayEndItsTurn() {
        let (observation, _) = frozenHand([.brick: 2, .grain: 2, .lumber: 2, .wool: 1])
        var rng = RandomSource(seed: 1)
        #expect(GhostPolicy(person: turnEnder(), lambda: 1).decide(observation, rng: &rng) == .endTurn)
    }

    /// Played out, a turn that starts at 25 cards ends at or under seven, or
    /// with nothing left to spend on. Every spend lowers the hand, so it ends.
    @Test func aHoardedTurnPlaysDownAndEnds() throws {
        let (_, start) = frozenHand(jakesHand)
        var state = start
        let seat = state.players[0].id
        let policy = GhostPolicy(person: turnEnder(), lambda: 1)
        var rng = RandomSource(seed: 2)
        for _ in 0..<GameSession.maxActionsPerTurn {
            let legal = RulesEngine.legalMoves(for: state, seat: seat).filter {
                if case .proposeTrade = $0 { return false }
                return true
            }
            let move = policy.decide(GameObservation(seat: seat, state: state, legalMoves: legal), rng: &rng)
            if move == .endTurn { break }
            try RulesEngine.apply(move, by: seat, to: &state)
        }
        let left = state.players[0].resources.values.reduce(0, +)
        #expect(left <= state.rules.discardThreshold, "ended the turn on \(left) cards")
    }
}
