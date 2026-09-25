import Testing
import CatanEngine
@testable import CatanAI

@Suite struct GhostStyleFeaturesTests {

    private func state(seed: UInt64 = 82) -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.randomized(seed: seed), seed: seed)
        playOpeningPlacements(in: &state, seed: seed)
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    private func value(_ label: String, _ features: [Double]) -> Double {
        features[StyleFeatures.labels.firstIndex(of: label)!]
    }

    @Test func aLopsidedProposalIsDescribed() {
        let s = state()
        let me = s.players[0].id
        let offer = TradeOffer(from: me, give: [.brick: 2, .lumber: 2], want: [.grain: 1])
        let f = StyleFeatures.of(.proposeTrade(offer), by: me, in: s)
        #expect(value("propose", f) == 1)
        #expect(value("proposeCardsGiven", f) == 4)
        #expect(value("proposeLopsided", f) == 3)
        #expect(value("proposeAfterRefusal", f) == 0)
    }

    @Test func reOfferingAfterARefusalIsFlagged() {
        var s = state()
        let me = s.players[0].id
        s.declinedTradeOffersThisTurn[me] = [TradeOffer(from: me, give: [.ore: 1], want: [.wool: 1])]
        let f = StyleFeatures.of(.proposeTrade(TradeOffer(from: me, give: [.ore: 2], want: [.wool: 1])), by: me, in: s)
        #expect(value("proposeAfterRefusal", f) == 1)
    }

    @Test func robbingTheLeaderIsFlagged() {
        var s = state()
        let me = s.players[0].id
        let leader = s.players[2].id
        s.players[2].cities.formUnion(s.players[2].settlements) // doubles seat 2's public points
        let hex = s.board.tiles[0].coordinate
        #expect(s.publicVictoryPoints(for: leader) > s.publicVictoryPoints(for: s.players[1].id))
        #expect(value("robberHitsLeader", StyleFeatures.of(.moveRobber(hex, stealFrom: leader), by: me, in: s)) == 1)
        #expect(value("robberHitsLeader", StyleFeatures.of(.moveRobber(hex, stealFrom: s.players[1].id), by: me, in: s)) == 0)
    }

    @Test func robbingTheBiggestHandIsFlagged() {
        var s = state()
        let me = s.players[0].id
        s.players[1].resources = [.ore: 5]
        s.players[2].resources = [.ore: 1]
        let hex = s.board.tiles[0].coordinate
        #expect(value("robberHitsBiggestHand", StyleFeatures.of(.moveRobber(hex, stealFrom: s.players[1].id), by: me, in: s)) == 1)
        #expect(value("robberHitsBiggestHand", StyleFeatures.of(.moveRobber(hex, stealFrom: s.players[2].id), by: me, in: s)) == 0)
    }

    @Test func everyMoveHasOneValuePerLabel() {
        let s = state()
        for move in RulesEngine.legalMoves(for: s, seat: s.players[0].id) {
            #expect(StyleFeatures.of(move, by: s.players[0].id, in: s).count == StyleFeatures.labels.count)
        }
    }
}
