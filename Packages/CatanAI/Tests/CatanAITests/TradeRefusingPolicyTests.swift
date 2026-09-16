import CatanEngine
import Foundation
import Testing
@testable import CatanAI

/// The trade-refusing decorator exists to make one cell of a measurement mean
/// "this opponent will not bail you out". If it ever accepted, that cell would
/// silently become a second copy of the arm it is compared against, and the
/// comparison would read as "trading makes no difference".
@Suite struct TradeRefusingPolicyTests {
    private func spy(_ record: @escaping @Sendable ([GameMove]) -> Void) -> any Policy {
        RecordingPolicy(record: record)
    }

    @Test func itHidesAcceptanceFromTheWrappedPolicy() {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 41)
        playOpeningPlacements(in: &state, seed: 41)
        let seat = state.players[1].id
        let offer = TradeOffer(from: state.players[0].id,
                               give: [.brick: 1], want: [.grain: 1])
        let moves: [GameMove] = [
            .respondToTrade(offerID: offer.id, accept: true),
            .respondToTrade(offerID: offer.id, accept: false),
            .endTurn
        ]

        let seen = Box()
        let policy = TradeRefusingPolicy(base: spy { seen.value = $0 })
        var rng = RandomSource(seed: 7)
        _ = policy.decide(
            GameObservation(seat: seat, state: state, legalMoves: moves), rng: &rng
        )

        #expect(!seen.value.contains { if case .respondToTrade(_, true) = $0 { return true }
                                      return false },
                "an acceptance reached the wrapped policy")
        #expect(seen.value.count == 2, "only the acceptance may be removed")
    }

    /// A mask holding nothing but an acceptance cannot happen today - the rules
    /// engine always emits the decline beside it - but the decorator must not
    /// hand its base an empty move list if it ever does.
    @Test func anAcceptanceOnlyMaskIsPassedThroughRatherThanEmptied() {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 42)
        playOpeningPlacements(in: &state, seed: 42)
        let seat = state.players[1].id
        let only: [GameMove] = [.respondToTrade(offerID: UUID(), accept: true)]

        let seen = Box()
        let policy = TradeRefusingPolicy(base: spy { seen.value = $0 })
        var rng = RandomSource(seed: 7)
        _ = policy.decide(
            GameObservation(seat: seat, state: state, legalMoves: only), rng: &rng
        )

        #expect(seen.value.count == 1, "the base must still be given something to choose from")
    }

    @Test func itNamesItselfAfterWhatItWraps() {
        let policy = TradeRefusingPolicy(
            base: HeuristicPolicy(personality: .balanced, id: "heuristic-balanced")
        )
        #expect(policy.id == "refuses-heuristic-balanced")
    }
}

/// Captures the move list its caller was actually given.
private final class Box: @unchecked Sendable {
    var value: [GameMove] = []
}

private struct RecordingPolicy: Policy {
    let id = "recording"
    let record: @Sendable ([GameMove]) -> Void

    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        record(observation.legalMoves)
        return observation.legalMoves[0]
    }
}
