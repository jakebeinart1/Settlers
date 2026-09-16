import Foundation
import Testing
@testable import CatanEngine

/// A policy may propose a trade `legalMoves` does not list - a bundle, or more
/// cards than the enumeration shows - when the engine permits it.
///
/// The worked example is Jake's: holding three ore, one wheat, two brick and
/// two wood, one wheat short of a city, offer two brick and two wood for the
/// wheat. The enumeration lists one resource a side, so before this a policy
/// that chose that offer crashed the session's mask check.
@Suite struct ComposedProposalTests {

    private func table() -> (GameState, PlayerID) {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 7)
        state.phase = .mainTurn(playerIndex: 0)
        let me = state.players[0].id
        state.players[0].resources = [.ore: 3, .grain: 1, .brick: 2, .lumber: 2]
        return (state, me)
    }

    private func composed(_ me: PlayerID, give: [Resource: Int], want: [Resource: Int]) -> GameMove {
        .proposeTrade(TradeOffer.enumerated(from: me, give: give, want: want))
    }

    private func permitted(_ move: GameMove, _ state: GameState, _ me: PlayerID) -> Bool {
        RulesEngine.isPermittedComposedProposal(
            move, by: me, in: state, legal: RulesEngine.legalMoves(for: state, seat: me)
        )
    }

    @Test func jakesBundleForTheCityIsPermitted() {
        let (state, me) = table()
        let offer = composed(me, give: [.brick: 2, .lumber: 2], want: [.grain: 1])
        #expect(!RulesEngine.legalMoves(for: state, seat: me).contains(offer), "the enumeration never lists a bundle")
        #expect(permitted(offer, state, me))
    }

    /// A random id would make two runs of one seeded game propose "different"
    /// offers, which is the determinism break `TradeOffer.enumerated` exists
    /// to prevent.
    @Test func aComposedOfferMustCarryItsContentDerivedID() {
        let (state, me) = table()
        let random = GameMove.proposeTrade(TradeOffer(from: me, give: [.brick: 2, .lumber: 2], want: [.grain: 1]))
        #expect(!permitted(random, state, me))
    }

    @Test func malformedOrExcessiveCompositionsAreRefused() {
        let (state, me) = table()
        #expect(!permitted(composed(me, give: [.brick: 1, .grain: 1], want: [.grain: 1]), state, me),
                "the same resource on both sides is not a trade")
        #expect(!permitted(composed(me, give: [.ore: 3, .brick: 2, .lumber: 1], want: [.wool: 1]), state, me),
                "six cards is over the give limit")
        #expect(!permitted(composed(me, give: [.ore: 1], want: [.wool: 2, .brick: 2]), state, me),
                "four cards is over the want limit")
        #expect(!permitted(composed(me, give: [.wool: 1, .ore: 1], want: [.grain: 1]), state, me),
                "the proposer holds no wool")
    }

    /// Composition does not reopen anything the enumeration closes: no
    /// proposals in the list means none composed either.
    @Test func noCompositionWhenProposingIsNotAllowed() {
        let (state, me) = table()
        let offer = composed(me, give: [.brick: 2, .lumber: 2], want: [.grain: 1])
        #expect(!RulesEngine.isPermittedComposedProposal(offer, by: me, in: state, legal: [.endTurn]))
    }

    /// The end-to-end contract: a session whose policy chooses a permitted
    /// composed offer does not trip its mask check, and the offer reaches the
    /// table.
    @Test func aSessionAcceptsAndTablesAPermittedComposedOffer() throws {
        let (state, me) = table()
        let offer = TradeOffer.enumerated(from: me, give: [.brick: 2, .lumber: 2], want: [.grain: 1])
        var policies: [PlayerID: any Policy] = [:]
        for player in state.players {
            policies[player.id] = player.id == me ? ComposingPolicy(offer: offer) : DeclinePolicy()
        }
        var session = GameSession(state: state, policies: policies, policySeed: 3)
        let next = session.decideNextDetailed()
        let decision = try #require(next)
        #expect(decision.move == .proposeTrade(offer))
        let step = try session.commit(seat: decision.seat, move: decision.move)
        let tabled = step.events.contains {
            if case .proposedTrade(me, let give, let want) = $0 { return give == offer.give && want == offer.want }
            return false
        }
        #expect(tabled, "the composed offer must reach the table")
    }
}

private struct ComposingPolicy: Policy {
    let id = "composing"
    let offer: TradeOffer
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        let proposing = observation.legalMoves.contains { if case .proposeTrade = $0 { true } else { false } }
        return proposing ? .proposeTrade(offer) : observation.legalMoves[0]
    }
}

private struct DeclinePolicy: Policy {
    let id = "decline"
    func decide(_ observation: GameObservation, rng: inout RandomSource) -> GameMove {
        observation.legalMoves.first { if case .respondToTrade(_, false) = $0 { true } else { false } }
            ?? observation.legalMoves[0]
    }
}
