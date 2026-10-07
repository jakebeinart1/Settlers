import CatanEngine
import Testing
@testable import CatanAI

@Suite struct NavalNavigationDiagnosticsTests {
    private func voyage() -> (GameState, VertexID, HexCoordinate, HexCoordinate) {
        var state = Naval.newGame(seed: 700_019, options: NavalOptions(fogEnabled: false, mapFamily: .archipelago))
        state.phase = .mainTurn(playerIndex: 0)
        let seat = state.players[0].id
        for site in Naval.potentialColonySites(for: seat, in: state) where NavalNavigationDiagnostics.isOverseasSite(site, in: state) {
            for shore in site.touchingTiles.sorted() where state.board.tiles.contains(where: { $0.coordinate == shore && $0.kind == .sea }) {
                for direction in 0..<6 {
                    let origin = shore.neighbor(direction)
                    if state.board.tiles.contains(where: { $0.coordinate == origin && $0.kind == .sea }) {
                        state.naval!.ships = [Ship(id: 80, owner: seat, coordinate: origin)]
                        state.players[0].resources = Building.settlementCost
                        return (state, site, origin, shore)
                    }
                }
            }
        }
        preconditionFailure("Fixture requires an approachable overseas coast")
    }

    private func apply(_ move: GameMove, state: inout GameState, tracker: inout NavalNavigationDiagnostics) throws {
        let before = state
        let seat = state.players[0].id
        _ = try RulesEngine.apply(move, by: seat, to: &state)
        tracker.observe(move, by: seat, before: before, after: state)
    }

    @Test func anIdleReturnCannotHideBehindResourceStepOrCounterChanges() throws {
        var (state, _, origin, shore) = voyage()
        var tracker = NavalNavigationDiagnostics()
        try apply(.sailShip(id: 80, to: shore), state: &state, tracker: &tracker)
        let before = state
        state.players[0].resources[.ore] = 7
        state.tradesAcceptedThisTurn[state.players[0].id] = 3
        tracker.observe(.bankTrade(give: [.brick: 4], get: [.ore: 1]), by: state.players[0].id, before: before, after: state)
        try apply(.sailShip(id: 80, to: origin), state: &state, tracker: &tracker)
        #expect(tracker.rawRevisits == 1)
        #expect(tracker.idleRevisits == 1)
    }

    @Test func foundingAColonyJustifiesProductiveBacktracking() throws {
        var (state, site, origin, shore) = voyage()
        var tracker = NavalNavigationDiagnostics()
        try apply(.sailShip(id: 80, to: shore), state: &state, tracker: &tracker)
        try apply(.buildSettlement(site), state: &state, tracker: &tracker)
        try apply(.sailShip(id: 80, to: origin), state: &state, tracker: &tracker)
        #expect(Naval.colonyPoints(for: state.players[0].id, in: state) == 1)
        #expect(tracker.rawRevisits == 1)
        #expect(tracker.idleRevisits == 0)
    }

    @Test func aCityUpgradeDoesNotInventNewExpeditionAccess() throws {
        var (state, _, origin, shore) = voyage()
        let home = state.board.onBoardVertices.sorted().first { $0.touchingTiles.contains(HexCoordinate(q: 0, r: 0)) }!
        state.players[0].settlements = [home]
        state.players[0].resources = Building.cityCost
        var tracker = NavalNavigationDiagnostics()
        try apply(.sailShip(id: 80, to: shore), state: &state, tracker: &tracker)
        try apply(.buildCity(home), state: &state, tracker: &tracker)
        try apply(.sailShip(id: 80, to: origin), state: &state, tracker: &tracker)
        #expect(tracker.rawRevisits == 1)
        #expect(tracker.idleRevisits == 1)
    }

    @Test func actualDiscoveryIsIndependentDestinationProgress() throws {
        var (state, _, origin, shore) = voyage()
        state.naval!.options.fogEnabled = true
        state.naval!.revealed = Set(state.board.tiles.filter {
            $0.coordinate.distance(to: origin) <= 2 || $0.coordinate.distance(to: HexCoordinate(q: 0, r: 0)) <= 2
        }.map(\.coordinate))
        var tracker = NavalNavigationDiagnostics()
        try apply(.sailShip(id: 80, to: shore), state: &state, tracker: &tracker)
        #expect(tracker.progressSteps == 1)
        try apply(.sailShip(id: 80, to: origin), state: &state, tracker: &tracker)
        #expect(tracker.rawRevisits == 1)
        #expect(tracker.idleRevisits == 0)
    }

    @Test func aHomeCoastIsNotAnOverseasColony() {
        let (state, overseas, _, _) = voyage()
        let home = state.board.onBoardVertices.sorted().first {
            Naval.isCoastal($0, in: state) && $0.touchingTiles.contains { coordinate in
                coordinate.distance(to: HexCoordinate(q: 0, r: 0)) <= 2 && Naval.isKnownLand(coordinate, in: state)
            }
        }!
        #expect(home.touchingTiles.contains { $0.distance(to: HexCoordinate(q: 0, r: 0)) == 3 })
        #expect(!NavalNavigationDiagnostics.isOverseasSite(home, in: state))
        #expect(NavalNavigationDiagnostics.isOverseasSite(overseas, in: state))
    }
}
