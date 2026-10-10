import Testing
import CatanEngine
@testable import CatanAI

struct NavalRoadContinuationPolicyTests {
    private let owner = PlayerID(index: 0)

    @Test(arguments: [BuildingKind.settlement, .city], [true, false])
    func publicExpansionPlanningReachesBeyondARivalTown(kind: BuildingKind, coastal: Bool) throws {
        let fixture = try position(version: 6, kind: kind, coastalJunction: coastal)
        let sites = BoardIndex(state: fixture.state).approachableSites(for: owner, in: fixture.state, limit: 2)
        #expect(sites.contains { $0.vertex == fixture.target && $0.roads == 2 })
    }

    @Test(arguments: [1, 2, 3, 4, 5], [BuildingKind.settlement, .city])
    func legacyPlanningStopsAtTheTown(version: Int, kind: BuildingKind) throws {
        let fixture = try position(version: version, kind: kind)
        let sites = BoardIndex(state: fixture.state).approachableSites(for: owner, in: fixture.state, limit: 2)
        #expect(!sites.contains { $0.vertex == fixture.target })
        #expect(!Building.canBuildRoad(fixture.first, for: owner, in: fixture.state))
    }

    @Test(arguments: NavalPolicy.Tier.allCases, [true, false])
    func bothTiersPriceAndChooseRealProgressBeyondTheTown(tier: NavalPolicy.Tier, coastal: Bool) throws {
        var fixture = try position(version: 6, coastalJunction: coastal)
        // Fund both approach roads and the eventual settlement. With only the
        // first road's ingredients, Expert may correctly reserve them instead.
        for resource in Resource.allCases {
            let amount = 2 * Building.roadCost[resource, default: 0] + Building.settlementCost[resource, default: 0]
            fixture.state.players[0].resources[resource] = amount
            fixture.state.bank[resource, default: 0] -= amount
        }
        let move = GameMove.buildRoad(fixture.first)
        #expect(RulesEngine.legalMoves(for: fixture.state).contains(move))
        let observation = GameObservation(seat: owner, state: fixture.state, legalMoves: [.endTurn, move])
        let context = NavalDecisionContext(observation: observation, ledger: NavalPolicy.positionLedger(observation),
                                           tier: tier, personality: .balanced, revision: .scoutingV2)
        #expect(context.roadApproaches.contains { $0.vertex == fixture.target && $0.roads == 2 })
        #expect(context.roadGain(fixture.first) > 0)
        var rng = RandomSource(seed: 19)
        let policy = NavalPolicy(tier: tier, revision: .scoutingV2)
        #expect(policy.decide(observation, rng: &rng) == move)
        try RulesEngine.apply(move, by: owner, to: &fixture.state)
        let after = BoardIndex(state: fixture.state).approachableSites(for: owner, in: fixture.state, limit: 2)
        #expect(after.contains { $0.vertex == fixture.target && $0.roads == 1 })
    }

    @Test func claimedEdgesHiddenTerrainAndRoadSupplyCannotPromiseAFalseRoute() throws {
        let fixture = try position(version: 6)
        var claimed = fixture.state
        claimed.players[1].roads.insert(fixture.first)
        #expect(!approaches(fixture.target, in: claimed))
        var hidden = fixture.state
        hidden.naval?.options.fogEnabled = true
        hidden.naval?.revealed.subtract(Set(fixture.target.touchingTiles))
        #expect(!approaches(fixture.target, in: hidden))
        var exhausted = fixture.state
        for edge in exhausted.board.onBoardEdges.sorted() where edge != fixture.first && edge != fixture.second {
            guard exhausted.players[0].roads.count < exhausted.rules.maxRoadsPerPlayer else { break }
            exhausted.players[0].roads.insert(edge)
        }
        #expect(!approaches(fixture.target, in: exhausted))
        var disconnected = fixture.state
        disconnected.players[0].roads = []
        #expect(!approaches(fixture.target, in: disconnected))
    }

    private func approaches(_ target: VertexID, in state: GameState) -> Bool {
        BoardIndex(state: state).approachableSites(for: owner, in: state, limit: 2).contains { $0.vertex == target }
    }

    /// Uses the generated island's fixed two-road approach. The future site
    /// is two free edges beyond the rival town, outside both towns' distance
    /// exclusion. No ship or hidden geography supplies an alternative route.
    private func position(version: Int, kind: BuildingKind = .settlement, coastalJunction: Bool = true) throws
        -> (state: GameState, target: VertexID, first: EdgeID, second: EdgeID) {
        var state = Naval.newGame(seed: 73, options: NavalOptions(fogEnabled: false))
        state.naval?.rulesVersion = version
        state.phase = .mainTurn(playerIndex: 0)
        let start = vertex(coastalJunction ? [(-7, 5), (-6, 4), (-6, 5)] : [(-7, 6), (-7, 7), (-6, 6)])
        let middle = vertex(coastalJunction ? [(-7, 5), (-7, 6), (-6, 5)] : [(-7, 7), (-6, 6), (-6, 7)])
        let junction = vertex(coastalJunction ? [(-7, 6), (-6, 5), (-6, 6)] : [(-6, 6), (-6, 7), (-5, 6)])
        state.players[0].settlements = [start]
        state.players[0].roads = [EdgeID(start, middle), EdgeID(middle, junction)]
        switch kind {
        case .settlement: state.players[1].settlements = [junction]
        case .city: state.players[1].cities = [junction]
        }
        let route = try #require(futureSite(beyond: junction, in: state))
        return (state, route.target, route.first, route.second)
    }

    private func futureSite(beyond junction: VertexID, in state: GameState) -> (target: VertexID, first: EdgeID, second: EdgeID)? {
        for first in state.board.edgesTouching(junction) where !state.players[0].roads.contains(first) {
            let middle = first.a == junction ? first.b : first.a
            for second in state.board.edgesTouching(middle) where second != first {
                let target = second.a == middle ? second.b : second.a
                var probe = state
                probe.players[0].roads.formUnion([first, second])
                if Building.canBuildSettlement(target, for: owner, in: probe) { return (target, first, second) }
            }
        }
        return nil
    }

    private func vertex(_ coordinates: [(Int, Int)]) -> VertexID {
        VertexID(touchingTiles: Set(coordinates.map { HexCoordinate(q: $0.0, r: $0.1) }))
    }
}
