import Foundation
import Testing
@testable import Settlers

@Suite struct EloTests {

    private let jake = RatedEntity.person("Jake")
    private let ghost = RatedEntity.ghost("jake")

    /// Four players at 1000; seat 0 wins. Against each of three losers the
    /// winner scores 1 where 0.5 was expected: 3 x (32/3) x 0.5 = 16. Each
    /// loser gives up (32/3) x 0.5 = 5.333 to the winner, and the losers'
    /// mutual half-points change nothing.
    @Test func aWinAtEqualRatingsIsWorthSixteen() {
        let seats: [RatedEntity] = [jake, ghost, .person("A"), .person("B")]
        let after = Elo.update([:], seats: seats, winner: 0)
        #expect(abs(after[jake]! - 1016) < 1e-9)
        #expect(abs(after[ghost]! - (1000 - 16.0 / 3)) < 1e-9)
        #expect(abs(after[.person("B")]! - (1000 - 16.0 / 3)) < 1e-9)
    }

    /// Classic is the one fixed anchor: it never moves, win or lose.
    @Test func classicNeverMoves() {
        let seats: [RatedEntity] = [.classic, jake, .classic, .classic]
        #expect(Elo.update([:], seats: seats, winner: 0)[.classic] == nil)
        #expect(Elo.update([:], seats: seats, winner: 1)[.classic] == nil)
        #expect(Elo.rating(of: .classic, in: [:]) == 1000)
    }

    /// Jake, 2026-09-25: Expert's Elo comes from human games too. It starts
    /// at 1229 and moves; its three seats do not play each other, and their
    /// deltas sum into one number.
    @Test func expertStartsAt1229AndMovesAsOneEntity() {
        #expect(Elo.rating(of: .expert, in: [:]) == 1229)
        let seats: [RatedEntity] = [jake, .expert, .expert, .expert]
        let after = Elo.update([:], seats: seats, winner: 0)
        let expected = 1.0 / (1 + pow(10, (1229.0 - 1000) / 400))
        let jakeGain = 3 * Elo.pairK * (1 - expected)
        #expect(abs(after[jake]! - (1000 + jakeGain)) < 1e-9)
        #expect(abs(after[.expert]! - (1229 - jakeGain)) < 1e-9, "Expert's three seats sum into one delta")
    }

    /// The spec's derivation of Expert's starting point: 68.4% wins against
    /// three Classic bots gives an expected pairwise score of
    /// 0.684 + 0.5 x (1 - 0.684 - 0.316/3) = 0.789.
    @Test func expertsStartingPointFollowsFromItsMeasuredWinRate() {
        let share = 0.684 + 0.5 * (1 - 0.684 - 0.316 / 3)
        #expect(abs(share - 0.789) < 0.001)
        #expect(Int((400 * log10(share / (1 - share))).rounded()) == 229)
        #expect(Elo.expertStart == 1000 + 229)
    }
}
