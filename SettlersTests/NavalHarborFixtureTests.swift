import Foundation
import Testing
import CatanEngine
@testable import Settlers

/// A native harbor journey must begin with a real claimable port and a
/// conserved bank, rather than getting its exchange rate from fabricated land.
@MainActor
@Suite struct NavalHarborFixtureTests {
    @Test(arguments: [NavalQAFixture.Position.genericPort, .resourcePort], [false, true])
    func portFixturesClaimRealSetupHarborsAndConserveAnActualExchange(position: NavalQAFixture.Position, fog: Bool) throws {
        let state = try NavalQAFixture.make(position, options: NavalOptions(fogEnabled: fog))
        let actor = state.players[0].id
        let give: Resource = position == .genericPort ? .lumber : .grain
        let expectedRate = position == .genericPort ? 3 : 2
        #expect(state.phase == .mainTurn(playerIndex: 0))
        #expect(state.players.allSatisfy { $0.settlements.count == 2 && $0.roads.count == 2 })
        #expect(state.players[0].resources[give, default: 0] >= 9)
        #expect(state.naval?.ships.isEmpty == true)
        #expect(Trading.bestRate(for: give, player: actor, state: state) == expectedRate)
        for resource in Resource.allCases {
            #expect(state.bank[resource, default: 0] + state.players.reduce(0) { $0 + $1.resources[resource, default: 0] } == 38)
        }
        var session = GameSession(state: state, policies: [:], policySeed: 0)
        try session.checkpoint.validate()
        let move = GameMove.bankTrade(give: [give: expectedRate], get: [.ore: 1])
        #expect(RulesEngine.legalMoves(for: state, seat: actor).contains(move))
        try session.applyExternal(move, by: actor)
        #expect(session.state.players[0].resources[give, default: 0] == state.players[0].resources[give, default: 0] - expectedRate)
        #expect(session.state.players[0].resources[.ore, default: 0] == state.players[0].resources[.ore, default: 0] + 1)
        #expect(session.state.bank[give, default: 0] == state.bank[give, default: 0] + expectedRate)
        #expect(session.state.bank[.ore, default: 0] == state.bank[.ore, default: 0] - 1)
        try session.checkpoint.validate()
    }
}
