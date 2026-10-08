import CatanEngine
import Foundation
import Testing
@testable import CatanAI

/// Frozen complete checkpoints from failed v5 matrix cells, followed by their
/// actual committed voyage/trades/card or road purchase. Policies still receive
/// the ordinary masked observation; the fixture supplies the replay boundary.
@Suite struct NavalReturnPolicyTests {
    private struct StoredStep: Decodable { let actor: PlayerID; let move: GameMove }
    private struct Sequence: Decodable {
        let checkpoint: GameSession.Checkpoint
        let steps: [StoredStep]
    }

    @Test(arguments: [47, 77])
    func ownSpendingCannotRewardAnImmediateUndiscoveringReturn(caseIndex: Int) throws {
        let sequence = try fixture(caseIndex)
        let policies = Dictionary(uniqueKeysWithValues: sequence.checkpoint.state.players.map {
            ($0.id, NavalPolicy(tier: .traditional, revision: .scoutingV2) as any Policy)
        })
        var session = try GameSession(checkpoint: sequence.checkpoint, policies: policies)
        let origin = try #require(sequence.checkpoint.state.naval?.ships.first {
            if case .sailShip(let id, _) = sequence.steps[0].move { return $0.id == id }; return false
        }?.coordinate)
        for stored in sequence.steps.dropLast() {
            let next = session.decideNextDetailed()
            let decision = try #require(next)
            #expect(decision.seat == stored.actor && decision.move == stored.move)
            _ = try session.commit(seat: stored.actor, move: stored.move)
        }
        let stored = try #require(sequence.steps.last)
        let observed = observation(for: session.state, seat: stored.actor)
        guard case .sailShip(let id, let destination) = stored.move else { Issue.record("Fixture lost its return"); return }
        #expect(destination == origin && observed.legalMoves.contains(stored.move), "Humans retain their legal return")
        #expect(observed.state.naval?.ships.first { $0.id == id }?.previousSailingOrigin == origin)
        let policy = NavalPolicy(tier: .traditional, revision: .scoutingV2)
        #expect(try #require(policy.assess(observed).first { $0.move == stored.move }).score < 0)
        var rng = RandomSource(seed: 71)
        #expect(policy.decide(observed, rng: &rng) != stored.move)
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(session.checkpoint))
        let resumed = try GameSession(checkpoint: checkpoint, policies: policies)
        #expect(resumed.checkpoint == session.checkpoint)
        #expect(policy.decide(observation(for: resumed.state, seat: stored.actor), rng: &rng) != stored.move)
    }

    private func observation(for state: GameState, seat: PlayerID) -> GameObservation {
        GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
    }

    @Test func concealedWorldAndHandsCannotAlterTheHistoryGuard() throws {
        let sequence = try fixture(47)
        let policies = Dictionary(uniqueKeysWithValues: sequence.checkpoint.state.players.map {
            ($0.id, NavalPolicy(tier: .traditional, revision: .scoutingV2) as any Policy)
        })
        var session = try GameSession(checkpoint: sequence.checkpoint, policies: policies)
        for stored in sequence.steps.dropLast() { _ = try session.commit(seat: stored.actor, move: stored.move) }
        let seat = try #require(sequence.steps.last?.actor)
        var first = session.state
        let rival = try #require(first.players.first { $0.id != seat }?.id)
        first.players[rival.index].resources = [.wool: 3]
        first.devCardDeck = [.knight]
        var altered = first
        altered.players[rival.index].resources = [.ore: 3]
        altered.devCardDeck = [.monopoly]
        altered.rng = RandomSource(seed: 991)
        altered.board = Board(tiles: first.board.tiles.map {
            first.naval!.revealed.contains($0.coordinate) ? $0 : Tile(coordinate: $0.coordinate, kind: .resource(.ore), numberToken: 8)
        }, ports: first.board.ports, onBoardVertices: first.board.onBoardVertices,
        onBoardEdges: first.board.onBoardEdges, robberTile: first.board.robberTile)
        let original = observation(for: first, seat: seat), changed = observation(for: altered, seat: seat)
        #expect(original == changed)
        var rng = RandomSource(seed: 71), other = rng
        let policy = NavalPolicy(tier: .traditional, revision: .scoutingV2)
        #expect(policy.decide(original, rng: &rng) == policy.decide(changed, rng: &other))
        #expect(rng == other)
    }

    @Test func actualSuppliesPermitAnImprovedImmediateLandingButForecastsDoNot() throws {
        var state = try fundedReturnPosition()
        let ship = try #require(state.naval?.ships.first)
        let target = try #require(ship.previousSailingOrigin)
        let move = GameMove.sailShip(id: ship.id, to: target)
        let policy = NavalPolicy(tier: .traditional, revision: .scoutingV2)
        let funded = observation(for: state, seat: ship.owner)
        #expect(funded.legalMoves.contains(move))
        #expect(try #require(policy.assess(funded).first { $0.move == move }).score > 0)
        state.players[ship.owner.index].resources[.wool] = 0
        let incomplete = observation(for: state, seat: ship.owner)
        #expect(try #require(policy.assess(incomplete).first { $0.move == move }).score < 0)
    }

    @Test func aProvableWinningColonyStillPermitsTheReturn() throws {
        var state = try fundedReturnPosition()
        let ship = try #require(state.naval?.ships.first)
        state.victoryPointTarget = state.victoryPoints(for: ship.owner) + 2
        let move = GameMove.sailShip(id: ship.id, to: try #require(ship.previousSailingOrigin))
        var rng = RandomSource(seed: 71)
        let chosen = NavalPolicy(tier: .expert, revision: .scoutingV2).decide(observation(for: state, seat: ship.owner), rng: &rng)
        #expect(chosen == move)
        try RulesEngine.apply(move, by: ship.owner, to: &state)
        let build = try #require(RulesEngine.legalMoves(for: state, seat: ship.owner).first {
            if case .buildSettlement(let vertex) = $0 { return Naval.canFoundColony(at: vertex, by: ship.owner, in: state) }; return false
        })
        try RulesEngine.apply(build, by: ship.owner, to: &state)
        #expect(state.phase == .gameOver(winner: ship.owner))
    }

    /// A real generated chart with an empty sea hex one step from an available
    /// overseas landing. The ship's recorded origin is that landing's sea hex.
    private func fundedReturnPosition() throws -> GameState {
        var state = Naval.newGame(seed: 73, options: NavalOptions(fogEnabled: false))
        while state.phase.isSetup {
            let index = try #require(state.phase.awaitingSeatIndex)
            try RulesEngine.apply(try #require(RulesEngine.legalMoves(for: state).first), by: state.players[index].id, to: &state)
        }
        let seat = PlayerID(index: 0)
        let sites = Naval.potentialColonySites(for: seat, in: state)
        let seas = Set(state.board.tiles.filter { $0.kind == .sea }.map(\.coordinate))
        let pair = try #require(returnCoast(sites: sites, seas: seas, in: state))
        state.naval?.ships = [Ship(id: 0, owner: seat, coordinate: pair.1, stepsRemaining: 1, previousSailingOrigin: pair.0)]
        state.naval?.nextShipID = 1
        state.naval?.hullsBuilt = [seat: 1]
        state.phase = .mainTurn(playerIndex: 0)
        for resource in Resource.allCases {
            state.bank[resource, default: 0] += state.players[0].resources[resource, default: 0] - Building.settlementCost[resource, default: 0]
        }
        state.players[0].resources = Building.settlementCost
        return state
    }

    private func returnCoast(sites: [VertexID], seas: Set<HexCoordinate>, in state: GameState) -> (HexCoordinate, HexCoordinate)? {
        for site in sites where NavalNavigationDiagnostics.isOverseasSite(site, in: state) {
            for origin in site.touchingTiles.sorted() where seas.contains(origin) {
                for direction in 0..<6 {
                    let next = origin.neighbor(direction)
                    if seas.contains(next), !sites.contains(where: { $0.touchingTiles.contains(next) }) { return (origin, next) }
                }
            }
        }
        return nil
    }

    private func fixture(_ caseIndex: Int) throws -> Sequence {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try JSONDecoder().decode(Sequence.self, from: Data(contentsOf: directory.appendingPathComponent("stall-\(caseIndex).json")))
    }
}
