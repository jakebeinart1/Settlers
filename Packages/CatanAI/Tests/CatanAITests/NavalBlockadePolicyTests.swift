import CatanEngine
import Foundation
import Testing
@testable import CatanAI

/// Purposeful public-geometry fixtures complement full seeded matches: natural
/// games need not park a rival in the single corridor under examination.
@Suite struct NavalBlockadePolicyTests {
    private let owner = PlayerID(index: 0)
    private let rival = PlayerID(index: 1)
    private let origin = HexCoordinate(q: 3, r: 0)
    private let obstruction = HexCoordinate(q: 4, r: 0)
    private let landing = HexCoordinate(q: 5, r: 0)
    private let detour = HexCoordinate(q: 4, r: 1)
    private let island = HexCoordinate(q: 6, r: 0)

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aRivalCutsThePublicCorridorAndItsColonyFunding(tier: NavalPolicy.Tier) throws {
        let blocked = corridor()
        let context = context(for: blocked, tier: tier)
        #expect(context.seaDistances(from: origin) == [origin: 0])
        #expect(!context.colonySites.isEmpty)
        #expect(context.reachableColonySites.isEmpty)
        #expect(!context.purchaseTargets.contains { $0.cost == Building.settlementCost })
        #expect(!context.reachesWinningColony(from: origin, steps: 2))
        #expect(context.sailingGain(shipID: 0, to: landing) == NavalDecisionContext.negativeScore)
        var rng = RandomSource(seed: 23)
        let observation = observation(for: blocked)
        #expect(NavalPolicy(tier: tier).decide(observation, rng: &rng) == .endTurn)

        var open = blocked
        open.naval?.ships.removeAll { $0.owner == rival }
        let reopened = self.context(for: open, tier: tier)
        #expect(reopened.seaDistances(from: origin)[landing] == 2)
        #expect(!reopened.reachableColonySites.isEmpty)
        #expect(reopened.purchaseTargets.contains { $0.cost == Building.settlementCost })
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func bothTiersTakeTheReachableDetourWithoutClaimingAFalseTwoHexWin(tier: NavalPolicy.Tier) throws {
        var state = corridor(detourEnabled: true)
        state.players[0].resources = Building.settlementCost
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 12)
        let context = context(for: state, tier: tier)
        #expect(context.seaDistances(from: origin)[landing] == 3)
        #expect(context.seaDistances(from: origin)[obstruction] == nil)
        #expect(context.winningColonyDistance(from: origin) == 3)
        #expect(!context.reachesWinningColony(from: origin, steps: 2))
        #expect(context.sailingGain(shipID: 0, to: detour) < 18_500)
        let move = GameMove.sailShip(id: 0, to: detour)
        let legal = RulesEngine.legalMoves(for: state, seat: owner)
        #expect(legal.contains(move))
        #expect(!legal.contains(.sailShip(id: 0, to: landing)))
        var rng = RandomSource(seed: 23)
        let focused = GameObservation(seat: owner, state: state, legalMoves: [move, .endTurn])
        #expect(NavalPolicy(tier: tier).decide(focused, rng: &rng) == move)
        let before = state
        try RulesEngine.apply(move, by: owner, to: &state)
        var tracker = NavalNavigationDiagnostics()
        let progress = tracker.observe(move, by: owner, before: before, after: state)
        #expect(progress)
        #expect(tracker.progressSteps == 2)
        #expect(tracker.idleRevisits == 0)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func friendlyHullOccupancyRetainsRoutesAndColonyFunding(tier: NavalPolicy.Tier) {
        var state = corridor()
        state.naval?.ships[1].owner = owner
        let context = context(for: state, tier: tier)
        #expect(context.seaDistances(from: origin)[obstruction] == 1)
        #expect(context.seaDistances(from: origin)[landing] == 2)
        #expect(!context.reachableColonySites.isEmpty)
        #expect(context.purchaseTargets.contains { $0.cost == Building.settlementCost })
        #expect(RulesEngine.legalMoves(for: state, seat: owner).contains(.sailShip(id: 0, to: landing)))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func sealedHarborsDoNotEarnFogOrFirstHullPurchaseBonuses(tier: NavalPolicy.Tier) {
        var state = corridor(hiddenFog: true, harbor: true)
        state.naval?.ships.removeAll { $0.owner == owner }
        let context = context(for: state, tier: tier)
        #expect(Naval.launchSites(for: owner, in: state) == [origin])
        #expect(context.state.board.tiles.contains { $0.kind == .fog })
        #expect(context.voyagePotential(at: origin, shipID: nil) == 0)
        #expect(context.shipValue(at: origin) == -1)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func capturingOneHullFromAStackAllowsEscapeAndDoesNotAllowReentry(tier: NavalPolicy.Tier) throws {
        var state = corridor()
        state.naval?.ships = [Ship(id: 0, owner: rival, coordinate: origin),
                              Ship(id: 1, owner: rival, coordinate: origin)]
        state.phase = .capturingShip(playerIndex: 0)
        state.naval?.capturePending = true
        state.naval?.productionRollerIndex = 0
        var rng = RandomSource(seed: 23)
        let capture = NavalPolicy(tier: tier).decide(observation(for: state), rng: &rng)
        #expect(capture == .captureShip(id: 0))
        try RulesEngine.apply(capture, by: owner, to: &state)
        #expect(Naval.isBlockaded(origin, by: owner, in: state))
        #expect(context(for: state, tier: tier).seaDistances(from: origin)[landing] == 2)
        let leave = GameMove.sailShip(id: 0, to: obstruction)
        #expect(RulesEngine.legalMoves(for: state, seat: owner).contains(leave))
        let before = state
        try RulesEngine.apply(leave, by: owner, to: &state)
        #expect(!RulesEngine.legalMoves(for: state, seat: owner).contains(.sailShip(id: 0, to: origin)))
        var tracker = NavalNavigationDiagnostics()
        let progress = tracker.observe(leave, by: owner, before: before, after: state)
        #expect(progress)
        #expect(tracker.progressSteps == 1)
    }

    @Test(arguments: NavalPolicy.Tier.allCases, [1, 2, 3])
    func legacyRoutesFundingAndPurchaseScoresIgnoreRivalOccupancy(tier: NavalPolicy.Tier, version: Int) {
        var blocked = corridor(hiddenFog: true)
        blocked.naval?.rulesVersion = version
        let legacy = context(for: blocked, tier: tier)
        var open = blocked
        open.naval?.ships.removeAll { $0.owner == rival }
        let old = context(for: open, tier: tier)
        #expect(legacy.seaDistances(from: origin) == old.seaDistances(from: origin))
        #expect(legacy.reachableColonySites == legacy.colonySites)
        #expect(legacy.purchaseTargets.map(\.value) == old.purchaseTargets.map(\.value))
        #expect(legacy.shipValue(at: origin) == old.shipValue(at: origin))
        let policy = NavalPolicy(tier: tier)
        #expect(policy.id == "naval-\(tier.rawValue)-v1")
        #expect(policy.assess(observation(for: blocked)).map(\.score)
            == policy.assess(observation(for: open)).map(\.score))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func blockersDoNotExposeConcealedTerrainHandsDeckOrFutureRandomness(tier: NavalPolicy.Tier) {
        let state = corridor(detourEnabled: true, hiddenFog: true)
        let baseline = observation(for: state)
        var changed = state
        changed.players[1].resources = [.ore: 2]
        changed.players[1].devCards = [.victoryPoint, .knight]
        changed.devCardDeck = [.monopoly]
        changed.rng = RandomSource(seed: 999)
        let tiles = changed.board.tiles.map { tile in
            Naval.isRevealed(tile.coordinate, in: changed) ? tile
                : Tile(coordinate: tile.coordinate, kind: .resource(.ore), numberToken: 8)
        }
        changed.board = Board(tiles: tiles, ports: [], onBoardVertices: changed.board.onBoardVertices,
                              onBoardEdges: [], robberTile: changed.board.robberTile)
        // Public counts stay equal; only the concealed compositions change.
        var original = state
        original.players[1].resources = [.grain: 2]
        original.players[1].devCards = [.roadBuilding, .yearOfPlenty]
        original.devCardDeck = [.knight]
        let first = observation(for: original)
        let second = observation(for: changed)
        #expect(first == second)
        #expect(first.legalMoves == baseline.legalMoves)
        var firstRNG = RandomSource(seed: 23), secondRNG = firstRNG
        let policy = NavalPolicy(tier: tier)
        #expect(policy.decide(first, rng: &firstRNG) == policy.decide(second, rng: &secondRNG))
        #expect(firstRNG == secondRNG)
    }

    private func corridor(detourEnabled: Bool = false, hiddenFog: Bool = false, harbor: Bool = false) -> GameState {
        var state = Naval.newGame(seed: 73, options: NavalOptions(fogEnabled: hiddenFog))
        state.phase = .mainTurn(playerIndex: 0)
        var sea = [origin, obstruction, landing]
        if detourEnabled { sea += [HexCoordinate(q: 3, r: 1), detour] }
        var tiles = sea.map { Tile(coordinate: $0, kind: .sea, numberToken: nil) }
        tiles.append(Tile(coordinate: island, kind: .resource(.grain), numberToken: 4))
        if hiddenFog { tiles.append(Tile(coordinate: HexCoordinate(q: 7, r: -7), kind: .sea, numberToken: nil)) }
        var corners = state.board.corners(of: island)
        if harbor {
            let home = HexCoordinate(q: 2, r: 0)
            tiles.append(Tile(coordinate: home, kind: .resource(.ore), numberToken: 6))
            corners += state.board.corners(of: home)
            state.players[0].settlements = [corners.first { $0.touchingTiles.contains(home) && $0.touchingTiles.contains(origin) }!]
        }
        state.board = Board(tiles: tiles, ports: [], onBoardVertices: Set(corners), onBoardEdges: [], robberTile: island)
        state.naval?.revealed = Set(tiles.filter { $0.coordinate != HexCoordinate(q: 7, r: -7) }.map(\.coordinate))
        state.naval?.ships = [Ship(id: 0, owner: owner, coordinate: origin),
                              Ship(id: 1, owner: rival, coordinate: obstruction)]
        state.devCardDeck = []
        for index in state.players.indices { state.players[index].resources = [:] }
        return state
    }

    private func observation(for state: GameState) -> GameObservation {
        GameObservation(seat: owner, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: owner))
    }

    private func context(for state: GameState, tier: NavalPolicy.Tier) -> NavalDecisionContext {
        let observed = observation(for: state)
        return NavalDecisionContext(observation: observed, ledger: NavalPolicy.positionLedger(observed),
                                    tier: tier, personality: .balanced)
    }
}
