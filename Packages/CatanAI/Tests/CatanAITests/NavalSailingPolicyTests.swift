import CatanEngine
import Foundation
import Testing
@testable import CatanAI

struct NavalSailingPolicyTests {
    private let owner = PlayerID(index: 0)
    private let origin = HexCoordinate(q: 3, r: 0)
    private let destination = HexCoordinate(q: 4, r: 1)

    @Test func sailingValuesTheUnionOfCanonicalIntermediateSight() throws {
        let state = seaPosition()
        let context = context(for: state)
        let ship = try #require(state.naval?.ships.first)
        let route = try #require(Naval.sailingRoute(for: ship, to: destination, in: context.state))
        let unknown = Set(context.state.board.tiles.filter { $0.kind == .fog }.map(\.coordinate))
        let expected = unknown.filter { coordinate in
            route.contains { coordinate.distance(to: $0) <= Naval.viewingRange }
        }.count
        #expect(context.unknownCellsSeen(along: route) == expected)
        #expect(expected > context.unknownCellsSeen(from: destination))
        #expect(expected < route.map { context.unknownCellsSeen(from: $0) }.reduce(0, +))
        let progress = (context.voyagePotential(at: destination, shipID: 0)
            - context.voyagePotential(at: origin, shipID: 0)) * 1.35
        #expect(abs(context.sailingGain(shipID: 0, to: destination) - (progress + Double(expected) * 0.075 - 0.005)) < 0.000_001)
    }

    @Test func aTwoHexActionCannotClaimAThirdHexWinningMove() throws {
        var state = fundedWinningPosition()
        let search = context(for: state)
        let seas = state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate).sorted()
        let candidates = seas.compactMap { start -> (Ship, HexCoordinate)? in
            guard search.winningColonyDistance(from: start) == 3 else { return nil }
            let ship = Ship(id: 0, owner: owner, coordinate: start)
            let end = Naval.sailingDestinations(for: ship, in: state).first {
                Naval.sailingRoute(for: ship, to: $0, in: state)?.count == 2
                    && search.winningColonyDistance(from: $0) == 1
            }
            return end.map { (ship, $0) }
        }
        let candidate = try #require(candidates.first)
        state.naval?.ships = [candidate.0]
        let exact = context(for: state)
        #expect(exact.sailingGain(shipID: 0, to: candidate.1) < 18_500)
        #expect(exact.winningColonyDistance(from: candidate.1) == 1)
        #expect(candidate.0.stepsRemaining == 2)
    }

    @Test func launchAndCaptureWinningPlansRespectTheSavedAllowance() throws {
        var state = fundedWinningPosition()
        let search = context(for: state)
        let threeAway = try #require(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate).sorted().first {
            search.winningColonyDistance(from: $0) == 3
        })
        state.naval?.ships = [Ship(id: 0, owner: PlayerID(index: 1), coordinate: threeAway)]
        let current = context(for: state)
        #expect(!current.winningLaunch(at: threeAway))
        #expect(current.captureValue(0) < 19_000)
        state.naval?.rulesVersion = 2
        state.naval?.ships[0].stepsRemaining = 3
        let legacy = context(for: state)
        #expect(legacy.winningLaunch(at: threeAway))
        #expect(legacy.captureValue(0) == 19_000)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func recomputedMasksAndChoicesIgnoreConcealedWorldChanges(tier: NavalPolicy.Tier) throws {
        let baseline = seaPosition()
        let policy = NavalPolicy(tier: tier)
        let original = observation(for: baseline)
        var rng = RandomSource(seed: 71)
        let choice = policy.decide(original, rng: &rng)
        guard case .sailShip = choice else { Issue.record("Funded sailing fixture chose \(choice)"); return }
        for kind in [TileKind.sea, .resource(.ore), .resourceChoice] {
            var changed = baseline
            let tiles = changed.board.tiles.map { tile in
                Naval.isRevealed(tile.coordinate, in: changed) ? tile : Tile(coordinate: tile.coordinate, kind: kind, numberToken: nil)
            }
            changed.board = Board(tiles: tiles, ports: [], onBoardVertices: [], onBoardEdges: [], robberTile: changed.board.robberTile)
            changed.rng = RandomSource(seed: 999)
            let redacted = observation(for: changed)
            #expect(redacted == original)
            #expect(policy.decide(redacted, rng: &rng) == choice)
        }
        #expect(policy.id == "naval-\(tier.rawValue)-v1")
    }

    @Test func navigationEvidenceCountsBothTravelledHexesOfOneVoyage() throws {
        var state = seaPosition()
        let before = state
        let move = GameMove.sailShip(id: 0, to: destination)
        try RulesEngine.apply(move, by: owner, to: &state)
        var tracker = NavalNavigationDiagnostics()
        let progress = tracker.observe(move, by: owner, before: before, after: state)
        #expect(progress)
        #expect(tracker.progressSteps == 2)
        #expect(tracker.rawRevisits == 0 && tracker.idleRevisits == 0)
    }

    private func fundedWinningPosition() -> GameState {
        var state = Naval.newGame(seed: 700_019, options: NavalOptions(fogEnabled: false))
        state.phase = .mainTurn(playerIndex: 0)
        state.players[0].devCards = Array(repeating: .victoryPoint, count: 12)
        state.players[0].resources = Resource.allCases.reduce(into: [:]) {
            $0[$1] = Naval.shipCost[$1, default: 0] + Building.settlementCost[$1, default: 0]
        }
        return state
    }

    private func seaPosition() -> GameState {
        var state = Naval.newGame(seed: 73)
        state.phase = .mainTurn(playerIndex: 0)
        let tiles = state.board.tiles.map { Tile(coordinate: $0.coordinate, kind: .sea, numberToken: nil) }
        state.board = Board(tiles: tiles, ports: [], onBoardVertices: [], onBoardEdges: [], robberTile: state.board.robberTile)
        state.naval?.ships = [Ship(id: 0, owner: owner, coordinate: origin)]
        state.naval?.revealed = Set(tiles.filter {
            $0.coordinate.distance(to: origin) <= Naval.viewingRange
                || $0.coordinate.distance(to: HexCoordinate(q: 0, r: 0)) <= Naval.homeRadius
        }.map(\.coordinate))
        return state
    }

    private func observation(for state: GameState) -> GameObservation {
        GameObservation(seat: owner, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: owner))
    }

    private func context(for state: GameState) -> NavalDecisionContext {
        let observation = observation(for: state)
        return NavalDecisionContext(observation: observation, ledger: NavalPolicy.positionLedger(observation),
                                    tier: .expert, personality: .balanced)
    }
}
