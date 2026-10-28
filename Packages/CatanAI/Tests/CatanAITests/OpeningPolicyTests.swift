import Testing
import CatanEngine
@testable import CatanAI

/// The rollout-fitted opening (2026-10-28). These pin what it values; the
/// evidence is in `OpeningPolicy`'s doc comment.
@Suite struct OpeningPolicyTests {
    @Test func theRevisionSeatsTheFrozenOpening() {
        #expect(ExpertRevision.openingOreGrainV1.policy.id == "evaluation-opening-ore-grain-v1")
        #expect(ExpertRevision.openingOreGrainV1.policy is OpeningPolicy)
    }

    @Test func anOreOrGrainPipOutweighsAnyOtherPip() {
        let policy = OpeningPolicy.v1
        #expect(policy.score([.ore: 4, .grain: 3], owned: []) > policy.score([.brick: 5, .lumber: 4], owned: []))
    }

    @Test func aSecondSettlementPaysForResourcesItDoesNotYetHave() {
        let policy = OpeningPolicy.v1
        #expect(policy.score([.brick: 4, .lumber: 5], owned: [.ore, .grain])
            > policy.score([.brick: 4, .lumber: 5], owned: [.brick, .lumber]))
    }

    @Test func theOpeningPicksTheBestScoringSpotAndLaterMovesAreTradeGuards() throws {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 88), seed: 88)
        let seat = state.players[0].id
        let observation = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        var rng = RandomSource(seed: 1)
        let move = OpeningPolicy.v1.decide(observation, rng: &rng)
        guard case .placeInitialSettlement(let pick) = move else {
            Issue.record("expected an opening settlement, got \(move)"); return
        }
        let scores = observation.legalMoves.compactMap { legal -> Double? in
            guard case .placeInitialSettlement(let vertex) = legal else { return nil }
            return OpeningPolicy.v1.score(OpeningPolicy.pips(at: vertex, state), owned: [])
        }
        #expect(OpeningPolicy.v1.score(OpeningPolicy.pips(at: pick, state), owned: []) == scores.max())
        try RulesEngine.apply(move, by: seat, to: &state)
        let road = GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
        var a = RandomSource(seed: 2), b = RandomSource(seed: 2)
        #expect(OpeningPolicy.v1.decide(road, rng: &a) == TradeGuardPolicy.v1.decide(road, rng: &b))
    }
}
