import Testing
import CatanEngine
@testable import CatanAI

/// What the evaluation is supposed to say about a position.
///
/// Three of these pin the defects the planner shipped with. They are written
/// against the *decision* - which of two candidates the policy prefers -
/// rather than against a raw score, because a score is only ever meaningful
/// next to another score, and because that is the form a regression would
/// actually take.
@Suite struct PositionEvaluatorTests {

    private func opening(seed: UInt64) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    private func ledger(for state: GameState, seat: PlayerID) -> PublicLedger {
        var counted = PublicLedger.fromPositionAlone(state, observer: seat)
        counted.reconcileObserverHand(from: state)
        return counted
    }

    /// The term every other term is denominated against.
    @Test func aPointOnTheBoardRaisesTheStanding() {
        let state = opening(seed: 11)
        let seat = state.players[0].id
        let evaluator = PositionEvaluator(seat: seat)
        let board = BoardIndex(state: state)
        let before = evaluator.standing(
            of: seat, in: state, ledger: ledger(for: state, seat: seat), board: board
        )

        var richer = state
        let upgrade = richer.players[0].settlements.sorted()[0]
        richer.players[0].settlements.remove(upgrade)
        richer.players[0].cities.insert(upgrade)

        let after = PositionEvaluator(seat: seat).standing(
            of: seat, in: richer, ledger: ledger(for: richer, seat: seat),
            board: BoardIndex(state: richer)
        )
        #expect(after > before, "upgrading a settlement to a city must raise this seat's standing")
    }

    /// Jake's rule, as arithmetic: a point both seats gain is worth less than
    /// a point only we gain. This is the whole reason `weights.rival` exists,
    /// and a regression that dropped the term would leave the two equal.
    @Test func aPointTheLeaderAlsoGainsIsWorthLessThanAPointWeGainAlone() {
        let state = opening(seed: 12)
        let me = state.players[0].id
        let rival = state.players[1].id
        let evaluator = PositionEvaluator(seat: me)

        func upgrading(_ seats: [PlayerID]) -> GameState {
            var next = state
            for seat in seats {
                guard let index = next.players.firstIndex(where: { $0.id == seat }),
                      let vertex = next.players[index].settlements.sorted().first else { continue }
                next.players[index].settlements.remove(vertex)
                next.players[index].cities.insert(vertex)
            }
            return next
        }

        let mineOnly = upgrading([me])
        let both = upgrading([me, rival])
        let alone = evaluator.evaluate(mineOnly, ledger: ledger(for: mineOnly, seat: me))
        let shared = evaluator.evaluate(both, ledger: ledger(for: both, seat: me))

        #expect(alone > shared, "a gain the rival shares must not price the same as a gain we keep")
    }

    /// Planner defect 2, pinned: the army route must be visible to the
    /// quantity being maximised. The planner bought 0.6 development cards a
    /// game against the heuristic's 6.9 because a card carried no credit
    /// toward Largest Army at all.
    ///
    /// ## Why this is not "a card beats ending the turn"
    /// It was, and the weight sweep falsified it. With fitted weights a hand
    /// holding exactly one card's cost is often worth more kept than spent -
    /// `handCard` tripled and `discardExposure` halved, so three resources in
    /// hand out-price one unplayed card in that specific position. The bot
    /// still buys 6.8 cards a game, more than the heuristic's 5.4, so the
    /// behaviour was right and the assertion was wrong.
    ///
    /// That is the second time a test here has been written from play
    /// intuition without checking the arithmetic. What actually matters is
    /// that a card is *priced*, so that is what this asserts.
    @Test func aDevelopmentCardInHandIsWorthSomething() {
        let state = opening(seed: 13)
        let seat = state.players[0].id
        let evaluator = PositionEvaluator(seat: seat)
        let board = BoardIndex(state: state)
        let before = evaluator.standing(
            of: seat, in: state, ledger: ledger(for: state, seat: seat), board: board
        )

        var holding = state
        holding.players[0].devCards.append(.knight)
        let after = evaluator.standing(
            of: seat, in: holding, ledger: ledger(for: holding, seat: seat),
            board: BoardIndex(state: holding)
        )
        #expect(after > before, "an unplayed development card must carry credit")
    }

    /// The behavioural half, which is what the planner actually failed. One
    /// full game, counting what the policy chose to buy.
    ///
    /// The threshold is deliberately far below what it does (6.8 a game) and
    /// far above what the planner did (0.6): this is a guard against the route
    /// going invisible again, not a pin on a tuned number.
    @Test func theEvaluatorBuysDevelopmentCardsOverAGame() throws {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 41), seed: 41)
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players { policies[player.id] = EvaluationPolicy() }
        var session = GameSession(state: state, policies: policies, policySeed: 41)

        var purchases = 0
        for _ in 0..<3000 {
            guard let decision = session.decideNextDetailed() else { break }
            if case .buyDevCard = decision.move { purchases += 1 }
            _ = try session.commit(seat: decision.seat, move: decision.move)
            if case .gameOver = session.state.phase { break }
        }
        #expect(purchases >= 4, "the development-card route went invisible again (\(purchases) bought)")
    }

    /// Planner defect 1, pinned. It built 1.0 settlements a game against 2.3
    /// and stopped expanding, because its tail estimate priced the remaining
    /// points as one purchase repeated and cities always won that comparison.
    ///
    /// The opening leaves no legal settlement anywhere - both of a seat's
    /// roads run to vertices its own settlements already block under the
    /// distance rule - so this walks one road out first. That is also the
    /// position the defect actually showed up in: having to spend a road
    /// before a site opens is exactly what the planner would not do.
    @Test func anAvailableSettlementBeatsEndingTheTurn() throws {
        var state = opening(seed: 10)
        let seat = state.players[0].id
        state.players[0].resources = [.brick: 1, .lumber: 1]

        let site = try #require(
            extendOneRoad(in: &state, seat: seat),
            "seed 10 must open a settlement site after one road, or this test proves nothing"
        )
        state.players[0].resources = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1]

        let policy = EvaluationPolicy()
        let chosen = policy.best(
            among: [.endTurn, site], state: state, ledger: ledger(for: state, seat: seat)
        )
        #expect(chosen == site, "an affordable settlement must beat passing")
    }

    /// Builds the first legal road that opens a settlement site and returns
    /// the settlement move it opened.
    private func extendOneRoad(in state: inout GameState, seat: PlayerID) -> GameMove? {
        let roads = RulesEngine.legalMoves(for: state, seat: seat).filter {
            if case .buildRoad = $0 { return true }
            return false
        }
        for road in roads {
            var next = state
            guard (try? RulesEngine.apply(road, by: seat, to: &next)) != nil else { continue }
            next.players[0].resources = [.brick: 1, .lumber: 1, .grain: 1, .wool: 1]
            let site = RulesEngine.legalMoves(for: next, seat: seat).first {
                if case .buildSettlement = $0 { return true }
                return false
            }
            if let site {
                state = next
                return site
            }
        }
        return nil
    }

    /// Winning is not a large number of points; it is the end of the
    /// comparison. A seat at the target must out-score any seat below it
    /// however good that seat's economy is.
    @Test func reachingTheTargetOutweighsEveryOtherTerm() {
        var state = opening(seed: 15)
        let seat = state.players[0].id
        // A commanding economy, but short of the target.
        state.players[0].resources = [.ore: 9, .grain: 9]

        let board = BoardIndex(state: state)
        let evaluator = PositionEvaluator(seat: seat)
        let short = evaluator.standing(
            of: seat, in: state, ledger: ledger(for: state, seat: seat), board: board
        )

        var won = state
        won.players[0].devCards = Array(repeating: .victoryPoint, count: won.victoryPointTarget)
        let winning = evaluator.standing(
            of: seat, in: won, ledger: ledger(for: won, seat: seat), board: BoardIndex(state: won)
        )
        #expect(winning > short * 10, "reaching the target must dominate, not merely lead")
    }

    /// A sweep reads and writes weights positionally. If the two orders ever
    /// disagree, every tuned weight lands in the wrong slot and the resulting
    /// strength number describes a policy nobody can rebuild.
    @Test func weightsRoundTripThroughTheirVector() {
        let weights = EvaluationWeights(vector: (1...14).map { Double($0) / 7.0 })
        #expect(EvaluationWeights(vector: weights.vector) == weights)
        #expect(weights.vector.count == EvaluationWeights.vectorLabels.count)
    }
}
