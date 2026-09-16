import Testing
import CatanEngine
@testable import CatanAI

/// The contracts `EvaluationPolicy` has to hold whatever its strength turns
/// out to be: it plays legal moves, it plays them from public information, and
/// it plays the same game twice from the same seed.
@Suite struct EvaluationPolicyTests {

    private func table(_ state: GameState) -> [PlayerID: any Policy] {
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players { policies[player.id] = EvaluationPolicy() }
        return policies
    }

    /// The one contract that is not about strength but about whether the game
    /// still works. `Bot` and `PlannerPolicy` are held to the same thing.
    ///
    /// Expert is the one policy allowed a single exception, and only the one
    /// the engine grants: a composed trade proposal - a bundle, or more cards
    /// than the enumeration lists - that `RulesEngine` itself permits. Any
    /// other move outside the mask still fails here. The run is long enough
    /// that composed offers actually occur, which is counted so a version
    /// that quietly stopped composing cannot pass on vacuous truth.
    @Test func everyMoveComesFromTheSuppliedMask() throws {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 21), seed: 21)
        var session = GameSession(state: state, policies: table(state), policySeed: 4)
        var composed = 0
        for _ in 0..<1_500 {
            guard let decision = session.decideNextDetailed() else { break }
            let listed = decision.observation.legalMoves.contains(decision.move)
            let permitted = RulesEngine.isPermittedComposedProposal(
                decision.move, by: decision.seat, in: session.state, legal: decision.observation.legalMoves
            )
            #expect(listed || permitted, "\(decision.move) is neither listed nor a permitted composition")
            if !listed { composed += 1 }
            _ = try session.commit(seat: decision.seat, move: decision.move)
            if case .gameOver = session.state.phase { break }
        }
        #expect(composed > 0, "no composed offer occurred, so this run did not exercise the exception")
    }

    /// Two positions differing only in what this seat may not see - opponents'
    /// resource composition, their development-card faces, and the deck's
    /// order - must produce the same move.
    ///
    /// The deck half of this is what `projectedDevCard` exists for. Scoring
    /// `buyDevCard` by applying it would let the top of the deck decide, and
    /// this test fails immediately if anyone makes that simplification later.
    @Test func theEvaluatorIgnoresWhatItIsNotEntitledToSee() {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 33), seed: 33)
        playOpeningPlacements(in: &state, seed: 33)
        state.phase = .mainTurn(playerIndex: 0)
        let seat = state.players[0].id
        state.players[0].resources = [.brick: 2, .lumber: 2, .grain: 2, .wool: 2, .ore: 1]

        var scrambled = state
        for index in scrambled.players.indices where scrambled.players[index].id != seat {
            let size = scrambled.players[index].resources.values.reduce(0, +)
            scrambled.players[index].resources = size > 0 ? [.ore: size] : [:]
            scrambled.players[index].devCards = [.monopoly, .victoryPoint]
        }
        scrambled.devCardDeck = scrambled.devCardDeck.reversed()

        let policy = EvaluationPolicy()
        var rngA = RandomSource(seed: 1)
        var rngB = RandomSource(seed: 1)
        let first = policy.decide(
            GameObservation(
                seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat)
            ),
            rng: &rngA
        )
        let second = policy.decide(
            GameObservation(
                seat: seat, state: scrambled,
                legalMoves: RulesEngine.legalMoves(for: scrambled, seat: seat)
            ),
            rng: &rngB
        )
        #expect(first == second, "the evaluator changed its move when hidden information changed")
    }

    /// A seeded game must replay move for move. The evaluator sums doubles
    /// over several features and then sorts candidates by the result, which is
    /// exactly the shape that has broken reproducibility five times in this
    /// repository - every one of them a `Set` or `Dictionary` reached during a
    /// floating-point sum.
    @Test func theSameSeedProducesTheSameGame() throws {
        func play(_ seed: UInt64) throws -> [GameMove] {
            let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
            var session = GameSession(state: state, policies: table(state), policySeed: seed)
            var moves: [GameMove] = []
            for _ in 0..<400 {
                guard let decision = session.decideNextDetailed() else { break }
                moves.append(decision.move)
                _ = try session.commit(seat: decision.seat, move: decision.move)
                if case .gameOver = session.state.phase { break }
            }
            return moves
        }
        #expect(try play(77) == play(77))
    }

    /// Both modes terminate. The 25-point mode is the one that exposed a
    /// shipping heuristic failing to close two games in twenty.
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
}
