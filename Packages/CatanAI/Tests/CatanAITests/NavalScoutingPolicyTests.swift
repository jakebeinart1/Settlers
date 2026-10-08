import CatanEngine
import Foundation
import Testing
@testable import CatanAI

/// Two actual public decisions from frozen v1 self-play. Their concealed world,
/// rival hands, decks and engine RNG were removed by GameObservation before export.
/// These fixtures reproduce ships reserving an unfunded coast for many turns
/// while legal voyages can discover new hexes. They contain no hand-authored scores.
@Suite struct NavalScoutingPolicyTests {
    @Test(arguments: NavalPolicy.Tier.allCases)
    func anUnfundedLandingDoesNotPreventRealScouting(tier: NavalPolicy.Tier) throws {
        let observation = try fixture(for: tier)
        var rng = RandomSource(seed: 71)
        let legacy = NavalPolicy(tier: tier).decide(observation, rng: &rng)
        #expect(legacy == .endTurn, "The frozen failure must remain reproducible")
        let beforeRNG = rng
        let move = NavalPolicy(tier: tier, revision: .scoutingV2).decide(observation, rng: &rng)
        #expect(observation.legalMoves.contains(move))
        #expect(rng == beforeRNG)
        guard case .sailShip(let id, let destination) = move else {
            Issue.record("An unfunded landing with reachable fog chose \(move)")
            return
        }
        let ship = try #require(observation.state.naval?.ships.first { $0.id == id })
        let route = try #require(Naval.sailingRoute(for: ship, to: destination, in: observation.state))
        #expect(observation.state.board.tiles.contains { tile in
            tile.kind == .fog && route.contains { tile.coordinate.distance(to: $0) <= Naval.viewingRange }
        })
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aFundedBuildingPrecedesLeavingForScouting(tier: NavalPolicy.Tier) throws {
        var state = try fixture(for: tier).state
        let seat = state.players.first { $0.id == (tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)) }!.id
        state.players[seat.index].resources = Building.settlementCost
        let observation = observation(for: state, seat: seat)
        #expect(observation.legalMoves.contains { move in
            if case .buildSettlement(let site) = move {
                return state.naval?.ships.contains { $0.owner == seat && site.touchingTiles.contains($0.coordinate) } == true
            }
            return false
        })
        var rng = RandomSource(seed: 71)
        let move = NavalPolicy(tier: tier, revision: .scoutingV2).decide(observation, rng: &rng)
        guard case .buildSettlement(let site) = move else { Issue.record("A funded landing chose \(move)"); return }
        // A more productive home building is also a legitimate permanent gain.
        #expect(Building.canBuildSettlement(site, for: seat, in: state))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aFriendlyHullCanReserveTheLandingWhileAnotherScouts(tier: NavalPolicy.Tier) throws {
        var state = try fixture(for: tier).state
        let seat = tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)
        state.players[seat.index].resources = Building.settlementCost
        let ship = try #require(state.naval?.ships.first { $0.owner == seat })
        state.naval?.ships.append(Ship(id: 900, owner: seat, coordinate: ship.coordinate, stepsRemaining: 0))
        let full = observation(for: state, seat: seat)
        let sails = full.legalMoves.filter { if case .sailShip = $0 { true } else { false } }
        let focused = GameObservation(seat: seat, state: state, legalMoves: sails + [.endTurn])
        var rng = RandomSource(seed: 71)
        let move = NavalPolicy(tier: tier, revision: .scoutingV2).decide(focused, rng: &rng)
        guard case .sailShip(let id, _) = move else { Issue.record("A redundant reserved hull chose \(move)"); return }
        #expect(id == ship.id)
        #expect(Naval.canFoundColony(at: Naval.potentialColonySites(for: seat, in: state).first {
            $0.touchingTiles.contains(ship.coordinate)
        }!, by: seat, in: state))
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aChartedSeaWithoutAColonyOrFrontierEndsInsteadOfCircling(tier: NavalPolicy.Tier) throws {
        var state = try fixture(for: tier).state
        let seat = tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)
        let tiles = state.board.tiles.map { Tile(coordinate: $0.coordinate, kind: .sea, numberToken: nil) }
        state.board = Board(tiles: tiles, ports: [], onBoardVertices: [], onBoardEdges: [], robberTile: HexCoordinate(q: 0, r: 0))
        state.naval?.revealed = Set(tiles.map(\.coordinate))
        state.players[seat.index].resources = [:]
        let observation = observation(for: state, seat: seat)
        #expect(observation.legalMoves.contains { if case .sailShip = $0 { true } else { false } })
        var rng = RandomSource(seed: 71)
        #expect(NavalPolicy(tier: tier, revision: .scoutingV2).decide(observation, rng: &rng) == .endTurn)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func opposingPublicGradientsCannotRewardAZeroDiscoveryRoundTrip(tier: NavalPolicy.Tier) throws {
        var state = try fixture(for: tier).state
        let seat = tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)
        let ship = try #require(state.naval?.ships.first { $0.owner == seat })
        let base = context(for: state, seat: seat, tier: tier)
        let pair = try #require(opposingGradients(in: base, ship: ship))
        let index = try #require(state.naval?.ships.firstIndex { $0.id == ship.id })
        state.naval?.ships[index].coordinate = pair.0
        let forward = context(for: state, seat: seat, tier: tier)
        let forwardScore = forward.sailingGain(shipID: ship.id, to: pair.1)
        state.naval?.ships[index].coordinate = pair.1
        let reverse = context(for: state, seat: seat, tier: tier)
        let reverseScore = reverse.sailingGain(shipID: ship.id, to: pair.0)
        #expect(!(forwardScore > 0 && reverseScore > 0), "Both directions rewarded a voyage with no new information")
    }

    private func opposingGradients(in context: NavalDecisionContext, ship: Ship) -> (HexCoordinate, HexCoordinate)? {
        for origin in context.tiles.keys.sorted() where context.tiles[origin]?.kind == .sea && context.unknownCellsSeen(from: origin) == 0 {
            for direction in 0..<6 {
                let next = origin.neighbor(direction)
                guard context.tiles[next]?.kind == .sea, context.unknownCellsSeen(from: next) == 0,
                      !Naval.isBlockaded(origin, by: ship.owner, in: context.state),
                      !Naval.isBlockaded(next, by: ship.owner, in: context.state) else { continue }
                let colony = context.voyagePotential(at: next, shipID: ship.id) - context.voyagePotential(at: origin, shipID: ship.id)
                let frontier = context.frontierPotential(at: next) - context.frontierPotential(at: origin)
                if colony * frontier < 0 && abs(colony) > 0.01 && abs(frontier) > 0.01 { return (origin, next) }
            }
        }
        return nil
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func concealedWorldChangesCannotAlterTheScoutingDecision(tier: NavalPolicy.Tier) throws {
        var first = try fixture(for: tier).state
        let seat = tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)
        let rival = first.players.first { $0.id != seat }!.id
        first.players[rival.index].resources = [.wool: 3]
        first.players[rival.index].devCards = [.knight]
        first.devCardDeck = [.knight]
        var second = first
        second.players[rival.index].resources = [.ore: 3]
        second.players[rival.index].devCards = [.monopoly]
        second.devCardDeck = [.monopoly]
        second.rng = RandomSource(seed: 999)
        second.board = Board(tiles: first.board.tiles.map {
            $0.kind == .fog ? Tile(coordinate: $0.coordinate, kind: .resource(.ore), numberToken: 8) : $0
        }, ports: first.board.ports, onBoardVertices: first.board.onBoardVertices,
        onBoardEdges: first.board.onBoardEdges, robberTile: first.board.robberTile)
        let original = observation(for: first, seat: seat), altered = observation(for: second, seat: seat)
        #expect(original == altered)
        var firstRNG = RandomSource(seed: 71), secondRNG = firstRNG
        let policy = NavalPolicy(tier: tier, revision: .scoutingV2)
        #expect(policy.decide(original, rng: &firstRNG) == policy.decide(altered, rng: &secondRNG))
        #expect(firstRNG == secondRNG)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func savedBrainsStayDistinctAndReloadWithTheirOriginalPolicy(tier: NavalPolicy.Tier) throws {
        let state = Naval.newGame(seed: 76)
        let legacy = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, NavalPolicy(tier: tier) as any Policy) })
        let current = Dictionary(uniqueKeysWithValues: state.players.map {
            ($0.id, NavalPolicy(tier: tier, revision: .scoutingV2) as any Policy)
        })
        var session = GameSession(state: state, policies: current, policySeed: 71)
        for _ in 0..<20 { _ = try #require(try session.step()) }
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self, from: JSONEncoder().encode(session.checkpoint))
        var resumed = try GameSession(checkpoint: checkpoint, policies: current)
        #expect(throws: (any Error).self) { try GameSession(checkpoint: checkpoint, policies: legacy) }
        for _ in 0..<10 {
            let first = try #require(try session.step()), second = try #require(try resumed.step())
            #expect(first.actor == second.actor && first.move == second.move && first.events == second.events)
            #expect(session.checkpoint == resumed.checkpoint)
        }
        #expect(ExpertRevision.navalV2.policyID == "naval-expert-v2")
    }

    @Test(arguments: [1, 2, 3, 4, 5])
    func directAdaptersSelectTheSavedRulesBrain(version: Int) throws {
        var state = try fixture(for: .traditional).state
        let seat = PlayerID(index: 1)
        state.naval?.rulesVersion = version
        let observed = observation(for: state, seat: seat)
        let expected: NavalPolicy.Revision = version >= 5 ? .scoutingV2 : .legacyV1
        #expect(NavalPolicy.Revision.forGame(state) == expected)
        var rng = RandomSource(seed: 71)
        let move = NavalPolicy(tier: .traditional, revision: expected).decide(observed, rng: &rng)
        #expect(HeuristicPolicy(personality: .balanced, id: "adapter").decide(observed, rng: &rng) == move)
        #expect(Bot(personality: .balanced).decide(for: state, player: seat) == move)
        let expert = NavalPolicy(tier: .expert, revision: .scoutingV2).decide(observed, rng: &rng)
        #expect(EvaluationPolicy(revision: .navalV2).decide(observed, rng: &rng) == expert)
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aNearFundedColonyKeepsItsOnlyHullAtTheLanding(tier: NavalPolicy.Tier) throws {
        var state = try fixture(for: tier).state
        let seat = tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)
        state.players[seat.index].cities = state.players[seat.index].settlements
        state.players[seat.index].settlements = []
        let initial = context(for: state, seat: seat, tier: tier)
        let resource = try #require(Resource.allCases.first {
            Building.settlementCost[$0] != nil && initial.fixedProduction[$0] >= 0.25
        })
        state.players[seat.index].resources = Building.settlementCost
        state.players[seat.index].resources[resource] = 0
        let observation = observation(for: state, seat: seat)
        let available = context(for: state, seat: seat, tier: tier)
        #expect(available.recipeRolls(Building.settlementCost, hand: available.me.resources,
                                     fixed: available.fixedProduction, flexible: available.flexibleProduction) <= 4)
        var rng = RandomSource(seed: 71)
        let move = NavalPolicy(tier: tier, revision: .scoutingV2).decide(observation, rng: &rng)
        if case .sailShip(_, let destination) = move {
            #expect(Naval.potentialColonySites(for: seat, in: state).contains { $0.touchingTiles.contains(destination) },
                    "Near-term funding should retain an immediate landing")
        }
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func anUnavailableBankIngredientCannotReserveAnUnfundedLanding(tier: NavalPolicy.Tier) throws {
        var state = try fixture(for: tier).state
        let seat = tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)
        state.players[seat.index].cities = state.players[seat.index].settlements
        state.players[seat.index].settlements = []
        let initial = context(for: state, seat: seat, tier: tier)
        let resource = try #require(Resource.allCases.first {
            Building.settlementCost[$0] != nil && initial.fixedProduction[$0] >= 0.25
        })
        state.players[seat.index].resources = Building.settlementCost
        state.players[seat.index].resources[resource] = 0
        state.bank[resource] = 0
        let available = context(for: state, seat: seat, tier: tier)
        let ship = try #require(available.ownedShips.first)
        #expect(available.colonySites.contains { $0.touchingTiles.contains(ship.coordinate) })
        #expect(!available.reservesLanding(ship))
        #expect(available.observation.legalMoves.contains { move in
            if case .sailShip(let id, let destination) = move {
                return available.sailingGain(shipID: id, to: destination) > 0
            }
            return false
        })
    }

    @Test(arguments: NavalPolicy.Tier.allCases)
    func aCompleteRivalBlockadeEndsInsteadOfClaimingAFogRoute(tier: NavalPolicy.Tier) throws {
        var state = try fixture(for: tier).state
        let seat = tier == .traditional ? PlayerID(index: 1) : PlayerID(index: 0)
        let ship = try #require(state.naval?.ships.first { $0.owner == seat })
        let rival = state.players.first { $0.id != seat }!.id
        for direction in 0..<6 {
            let neighbor = ship.coordinate.neighbor(direction)
            if state.board.tiles.contains(where: { $0.coordinate == neighbor && $0.kind == .sea }) {
                state.naval?.ships.append(Ship(id: 900 + direction, owner: rival, coordinate: neighbor))
            }
        }
        let observation = observation(for: state, seat: seat)
        #expect(!observation.legalMoves.contains { if case .sailShip = $0 { true } else { false } })
        #expect(observation.state.board.tiles.contains { $0.kind == .fog })
        var rng = RandomSource(seed: 71)
        #expect(NavalPolicy(tier: tier, revision: .scoutingV2).decide(observation, rng: &rng) == .endTurn)
    }

    private func context(for state: GameState, seat: PlayerID, tier: NavalPolicy.Tier) -> NavalDecisionContext {
        let observed = observation(for: state, seat: seat)
        return NavalDecisionContext(observation: observed, ledger: NavalPolicy.positionLedger(observed),
                                    tier: tier, personality: .balanced, revision: .scoutingV2)
    }

    @Test func captureOffRemovesTheExpertsImaginaryExpeditionRisk() throws {
        var state = try fixture(for: .expert).state
        let seat = PlayerID(index: 0)
        let ship = try #require(state.naval?.ships.first { $0.owner == seat })
        state.naval?.options.shipStealingEnabled = false
        #expect(context(for: state, seat: seat, tier: .expert).expeditionRetention(from: ship.coordinate) == 1)
        state.naval?.options.shipStealingEnabled = true
        #expect(context(for: state, seat: seat, tier: .expert).expeditionRetention(from: ship.coordinate) < 1)
    }

    private func observation(for state: GameState, seat: PlayerID) -> GameObservation {
        GameObservation(seat: seat, state: state, legalMoves: RulesEngine.legalMoves(for: state, seat: seat))
    }

    private func fixture(for tier: NavalPolicy.Tier) throws -> GameObservation {
        let name = tier == .traditional ? "traditional-stall" : "expert-stall"
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try JSONDecoder().decode(GameObservation.self, from: Data(contentsOf: directory.appendingPathComponent(name + ".json")))
    }
}
