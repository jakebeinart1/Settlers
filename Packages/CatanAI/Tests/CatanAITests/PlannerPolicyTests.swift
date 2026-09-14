import Testing
import CatanEngine
@testable import CatanAI

@Suite struct PlannerPolicyTests {

    private func table(_ state: GameState) -> [PlayerID: any Policy] {
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players { policies[player.id] = PlannerPolicy() }
        return policies
    }

    /// The planner must never return a move the engine did not offer. `Bot`
    /// has the same contract and it is the one that cannot be compromised:
    /// everything else is a question of strength, this is a question of
    /// whether the game still works.
    @Test func everyMoveComesFromTheSuppliedMask() throws {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 21), seed: 21)
        var session = GameSession(state: state, policies: table(state), policySeed: 4)
        for _ in 0..<300 {
            guard let decision = session.decideNextDetailed() else { break }
            #expect(decision.observation.legalMoves.contains(decision.move))
            _ = try session.commit(seat: decision.seat, move: decision.move)
            if case .gameOver = session.state.phase { break }
        }
    }

    /// The information contract, enforced at the decision itself.
    ///
    /// Two positions that differ only in what the planner is not allowed to
    /// see - opponents' exact resource composition, their development-card
    /// faces, and the order of the deck - must produce the same move. If they
    /// do not, something is reading a hand it should not, and any strength
    /// number measured afterwards is partly a measurement of that.
    @Test func thePlannerIgnoresWhatItIsNotEntitledToSee() {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 33), seed: 33)
        playOpeningPlacements(in: &state, seed: 33)
        state.phase = .mainTurn(playerIndex: 0)
        let seat = state.players[0].id
        state.players[0].resources = [.brick: 2, .lumber: 2, .grain: 1, .wool: 1]

        var scrambled = state
        for index in scrambled.players.indices where scrambled.players[index].id != seat {
            // Same hand size, completely different composition.
            let size = scrambled.players[index].resources.values.reduce(0, +)
            scrambled.players[index].resources = size > 0 ? [.ore: size] : [:]
            scrambled.players[index].devCards = [.monopoly, .victoryPoint]
        }
        scrambled.devCardDeck = scrambled.devCardDeck.reversed()

        let policy = PlannerPolicy()
        var rngA = RandomSource(seed: 1)
        var rngB = RandomSource(seed: 1)
        let first = policy.decide(
            GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat)),
            rng: &rngA
        )
        let second = policy.decide(
            GameObservation(
                seat: seat, state: scrambled, legalMoves: RulesEngine.legalMoves(for: scrambled, seat: seat)
            ),
            rng: &rngB
        )
        #expect(first == second, "the planner changed its move when hidden information changed")
    }

    @Test func theSameSeedProducesTheSameGame() throws {
        func play(_ seed: UInt64) throws -> [GameMove] {
            let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
            var session = GameSession(state: state, policies: table(state), policySeed: seed)
            var moves: [GameMove] = []
            for _ in 0..<200 {
                guard let step = try session.step() else { break }
                moves.append(step.move)
                if case .gameOver = session.state.phase { break }
            }
            return moves
        }
        #expect(try play(88) == play(88))
    }

    /// The whole reason for the work: a 25-point game the shipping heuristic
    /// could not reliably finish.
    @Test(arguments: [GameMode.classic, GameMode.expanded])
    func aFullGameReachesAWinner(mode: GameMode) throws {
        let seed: UInt64 = mode == .classic ? 501 : 502
        let state = GameSetup.newGame(
            board: BoardGenerator.randomized(seed: seed, shape: mode == .classic ? .classic : .expanded),
            seed: seed,
            mode: mode
        )
        var session = GameSession(state: state, policies: table(state), policySeed: seed)
        let outcome = try session.run(limit: 8_000)

        guard case .gameOver(let winner) = outcome else {
            Issue.record("\(mode.displayName) game did not finish")
            return
        }
        #expect(session.state.victoryPoints(for: winner) >= session.state.victoryPointTarget)
    }

    /// Jake's worked example, and the one that shows the two layers working:
    /// holding eight cards with a development card affordable but not a city,
    /// ducking under the discard threshold is the best available move - and it
    /// needs no rule of its own, because the seven cost is part of the clock.
    @Test func itShedsCardsRatherThanSitOnAnEightCardHandBeforeASeven() throws {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 44), seed: 44)
        playOpeningPlacements(in: &state, seed: 44)
        state.phase = .mainTurn(playerIndex: 0)
        let seat = state.players[0].id
        // Eight cards: enough for a development card, one ore short of a city.
        state.players[0].resources = [.ore: 2, .grain: 3, .wool: 2, .lumber: 1]

        let rate = ProductionModel.rate(for: seat, in: state)
        let costOfHolding = ClockModel.sevenCost(handSize: 8, rate: rate, rules: state.rules)
        #expect(costOfHolding > 0, "an eight-card hand must carry a real cost, or the example is moot")

        let legal = RulesEngine.legalMoves(for: state, seat: seat)
        #expect(legal.contains(.buyDevCard), "the example needs the card to be affordable")
        #expect(
            !legal.contains(where: { if case .buildCity = $0 { return true } else { return false } }),
            "the example needs the city to be out of reach"
        )

        var rng = RandomSource(seed: 5)
        let chosen = PlannerPolicy().decide(
            GameObservation(seat: seat, state: state, legalMoves: legal), rng: &rng
        )
        #expect(chosen != .endTurn, "sitting on eight cards through a seven is the move being replaced")
    }
}
