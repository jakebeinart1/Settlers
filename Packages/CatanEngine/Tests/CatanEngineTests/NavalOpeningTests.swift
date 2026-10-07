import Testing
@testable import CatanEngine

struct NavalOpeningTests {
    @Test(arguments: NavalMapFamily.allCases)
    func firstPlacementAndRoadArePlayable(family: NavalMapFamily) throws {
        var state = Naval.newGame(seed: 42, options: NavalOptions(mapFamily: family))
        #expect(state.board.tiles.count == 169)
        let seat = state.players[0].id
        let first = try #require(RulesEngine.legalMoves(for: state).first)
        guard case .placeInitialSettlement(let vertex) = first else {
            Issue.record("opening must offer a home-island settlement")
            return
        }
        #expect(Naval.isHomeSite(vertex, in: state))
        try RulesEngine.apply(first, by: seat, to: &state)
        let road = try #require(RulesEngine.legalMoves(for: state).first)
        try RulesEngine.apply(road, by: seat, to: &state)
        #expect(state.phase == .setupForward(playerIndex: 1))
        #expect(Naval.launchSites(for: seat, in: state).isEmpty == !Naval.isCoastal(vertex, in: state))
    }
}
