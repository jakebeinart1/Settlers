import Foundation
import Testing
import CatanEngine
@testable import CatanAI

/// H6/H10 mechanism checks, deliberately independent of a screenshot or a win rate.
/// Fixtures retain the complete Classic geometry and printed piece limits. They
/// assemble partial positions with legal placements/purchases, not full games.
/// Traces report production policy choices without pinning a questionable choice.
@Suite struct HumanReviewStrategyDiagnosticsTests {
    private let seed: UInt64 = 10_704
    private let tolerance = 1e-12
    private let revisions: [ExpertRevision] = [.legacy, .cityProductionV1]

    @Test func robberBlocksProbabilityTimesBuildingYield() throws {
        let fixture = try robberPosition()
        let state = fixture.state
        let rich = state.players[1].id
        let poor = state.players[2].id
        let onEight = try after(.moveRobber(fixture.grain, stealFrom: nil), in: state)
        let onTwo = try after(.moveRobber(fixture.slow, stealFrom: nil), in: state)
        let cityLoss = ProductionModel.rate(for: rich, in: state)[.grain]
            - ProductionModel.rate(for: rich, in: onEight)[.grain]
        let settlementLoss = ProductionModel.rate(for: poor, in: state).total
            - ProductionModel.rate(for: poor, in: onTwo).total
        #expect(abs(cityLoss - 4 * 5.0 / 36.0) < tolerance)
        #expect(abs(settlementLoss - 1.0 / 36.0) < tolerance)
        #expect(cityLoss > settlementLoss)
        #expect(ProductionModel.bankRates(for: rich, in: state)
            == ProductionModel.bankRates(for: rich, in: onEight), "the robber blocks production, not port access")
    }

    @Test func sharedTileChargesTheRobberMoverForItsOwnCity() throws {
        let fixture = try robberPosition(selfCollateral: true)
        let state = fixture.state
        let me = state.players[0].id
        let next = try after(.moveRobber(fixture.grain, stealFrom: nil), in: state)
        let loss = ProductionModel.rate(for: me, in: state)[.grain]
            - ProductionModel.rate(for: me, in: next)[.grain]
        #expect(abs(loss - 2 * 5.0 / 36.0) < tolerance)
        for revision in revisions {
            let evaluator = PositionEvaluator(seat: me, revision: revision)
            #expect(standing(me, in: next, evaluator: evaluator) < standing(me, in: state, evaluator: evaluator))
        }
    }

    /// Empty victim hands isolate production. Single-card hands add a legal
    /// steal; the trace labels that branch because Expert applies the real steal.
    @Test(arguments: [false, true], [false, true])
    func robberPolicyTraceUsesItsCompleteLegalMask(selfCollateral: Bool, steal: Bool) throws {
        var fixture = try robberPosition(selfCollateral: selfCollateral)
        if steal {
            try fund([.brick: 1], seat: 1, in: &fixture.state)
            try fund([.brick: 1], seat: 2, in: &fixture.state)
        }
        for revision in revisions {
            let policy = EvaluationPolicy(revision: revision)
            let targets = [fixture.grain, fixture.slow].map {
                GameMove.moveRobber($0, stealFrom: Robber.eligibleVictims(
                    for: $0, thief: fixture.state.players[0].id, in: fixture.state).first)
            }
            _ = try trace("H6 collateral=\(selfCollateral) steal=\(steal)",
                          state: fixture.state, policy: policy, inspect: targets)
        }
    }

    /// Public bonuses can change the rival comparison. Hidden VP faces cannot
    /// change it, even when they would make the rival the true private leader.
    @Test func publicRivalStandingAndHiddenVictoryPointsStaySeparate() throws {
        var fixture = try robberPosition()
        fixture.state.players[2].playedKnights = fixture.state.rules.largestArmyMinimum
        fixture.state.largestArmyPlayer = fixture.state.players[2].id
        for _ in 0..<fixture.state.rules.largestArmyMinimum {
            let index = try #require(fixture.state.devCardDeck.firstIndex(of: .knight))
            fixture.state.devCardDeck.remove(at: index)
        }
        var hidden = fixture.state
        for _ in 0..<2 {
            let card = try #require(hidden.devCardDeck.firstIndex(of: .victoryPoint))
            hidden.devCardDeck.remove(at: card)
            hidden.players[2].devCards.append(.victoryPoint)
        }
        #expect(hidden.publicVictoryPoints(for: hidden.players[2].id)
            < hidden.publicVictoryPoints(for: hidden.players[1].id))
        #expect(hidden.victoryPoints(for: hidden.players[2].id)
            > hidden.victoryPoints(for: hidden.players[1].id))
        var disguised = hidden
        disguised.players[2].devCards = [.monopoly, .monopoly]
        for _ in 0..<2 {
            let card = try #require(disguised.devCardDeck.firstIndex(of: .monopoly))
            disguised.devCardDeck[card] = .victoryPoint
        }
        for revision in revisions {
            let evaluator = PositionEvaluator(seat: hidden.players[0].id, revision: revision)
            let ledger = PublicLedger.fromPositionAlone(hidden, observer: evaluator.seat)
            #expect(evaluator.evaluate(hidden, ledger: ledger) == evaluator.evaluate(disguised, ledger: ledger))
            _ = try trace("H6 alternate public army holder", state: fixture.state,
                          policy: EvaluationPolicy(revision: revision), inspect: [])
        }
    }

    @Test func roadProgressFindsARealDistanceLegalSettlement() throws {
        var state = try roadPosition()
        let corners = state.board.corners(of: HexCoordinate(q: 0, r: 0))
        let me = state.players[0].id
        let initial = BoardIndex(state: state).approachableSites(for: me, in: state, limit: 2)
        #expect(initial.contains { $0.vertex == corners[3] && $0.roads == 2 })
        try purchase(.buildRoad(EdgeID(corners[1], corners[2])), cost: Building.roadCost, seat: 0, in: &state)
        #expect(BoardIndex(state: state).approachableSites(for: me, in: state, limit: 2)
            .contains { $0.vertex == corners[3] && $0.roads == 1 })
        try purchase(.buildRoad(EdgeID(corners[2], corners[3])), cost: Building.roadCost, seat: 0, in: &state)
        #expect(BoardIndex(state: state).buildableSites(for: me, in: state).contains(corners[3]))
        try expectCurrentSitesMatchEngine(state)
    }

    /// The oracle enumerates actual legal road applications, independently of
    /// BoardIndex's BFS, and records the minimum construction count per site.
    @Test(arguments: [false, true])
    func blockedPathsAgreeWithEngineAndKeepLegalDetours(blockWithCity: Bool) throws {
        var state = try roadPosition()
        let corners = state.board.corners(of: HexCoordinate(q: 0, r: 0))
        let branch = try #require(state.board.edgesTouching(corners[2]).first {
            $0 != EdgeID(corners[1], corners[2]) && $0 != EdgeID(corners[2], corners[3])
        })
        try initialBuilding(corners[2], seat: 1, road: branch, in: &state)
        if blockWithCity { try purchase(.buildCity(corners[2]), cost: Building.cityCost, seat: 1, in: &state) }
        try purchase(.buildRoad(EdgeID(corners[1], corners[2])), cost: Building.roadCost, seat: 0, in: &state)
        #expect(!Building.canBuildRoad(EdgeID(corners[2], corners[3]), for: state.players[0].id, in: state))
        let expected = try engineApproaches(state, limit: 2)
        #expect(expected[corners[4]] == 2, "the other side of the hex is a legal detour")
        #expect(expected[corners[2]] == nil && expected[corners[3]] == nil)
        #expect(approaches(state, limit: 2) == expected)
        try expectCurrentSitesMatchEngine(state)
    }

    @Test func anOpponentsRoadCannotBecomeAnApproachShortcut() throws {
        var state = try roadPosition()
        let corners = state.board.corners(of: HexCoordinate(q: 0, r: 0))
        try initialBuilding(corners[4], seat: 1, road: EdgeID(corners[4], corners[3]), in: &state)
        try purchase(.buildRoad(EdgeID(corners[3], corners[2])), cost: Building.roadCost, seat: 1, in: &state)
        state.phase = .mainTurn(playerIndex: 0)
        #expect(!Building.canBuildRoad(EdgeID(corners[2], corners[3]), for: state.players[0].id, in: state))
        #expect(approaches(state, limit: 2) == (try engineApproaches(state, limit: 2)))
        try expectCurrentSitesMatchEngine(state)
    }

    @Test func settlementSupplyFiltersSitesAndACityReturnsAPiece() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
        try fillSettlements(in: &state)
        state.phase = .mainTurn(playerIndex: 0)
        let me = state.players[0].id
        #expect(BoardIndex(state: state).buildableSites(for: me, in: state).isEmpty)
        #expect(approaches(state, limit: 2).isEmpty)
        try expectCurrentSitesMatchEngine(state)
        let upgrade = try #require(state.players[0].settlements.sorted().first)
        try purchase(.buildCity(upgrade), cost: Building.cityCost, seat: 0, in: &state)
        #expect(state.players[0].settlements.count == state.rules.pieceLimit(for: .settlement) - 1)
        let expected = try engineApproaches(state, limit: 2)
        #expect(!expected.isEmpty, "freed supply must expose a real construction route")
        #expect(approaches(state, limit: 2) == expected)
    }

    @Test func approachDistanceCannotExceedRemainingRoadPieces() throws {
        var state = try roadPosition()
        while state.players[0].roads.count < state.rules.maxRoadsPerPlayer - 1 {
            let edge = try #require(state.board.onBoardEdges.sorted().first {
                Building.canBuildRoad($0, for: state.players[0].id, in: state)
            })
            try purchase(.buildRoad(edge), cost: Building.roadCost, seat: 0, in: &state)
        }
        #expect(approaches(state, limit: 4).values.allSatisfy { $0 == 1 })
        #expect(approaches(state, limit: 4) == (try engineApproaches(state, limit: 1)))
        let last = try #require(state.board.onBoardEdges.sorted().first {
            Building.canBuildRoad($0, for: state.players[0].id, in: state)
        })
        try purchase(.buildRoad(last), cost: Building.roadCost, seat: 0, in: &state)
        #expect(approaches(state, limit: 4).isEmpty)
        try expectCurrentSitesMatchEngine(state)
    }

    @Test func expertConvertsAnAffordableReachableSiteIntoAPoint() throws {
        var state = try roadPosition()
        let corners = state.board.corners(of: HexCoordinate(q: 0, r: 0))
        try purchase(.buildRoad(EdgeID(corners[1], corners[2])), cost: Building.roadCost, seat: 0, in: &state)
        try fund(Building.settlementCost, seat: 0, in: &state)
        for revision in revisions {
            let chosen = try trace("H10 affordable real site", state: state,
                                   policy: EvaluationPolicy(revision: revision), inspect: [])
            guard case .buildSettlement = chosen else {
                Issue.record("an affordable point lost to \(chosen) under \(revision)")
                continue
            }
            let next = try after(chosen, in: state)
            #expect(next.publicVictoryPoints(for: state.players[0].id)
                == state.publicVictoryPoints(for: state.players[0].id) + 1)
        }
    }

    /// Rival length 15 makes the award impossible to take with 15 own pieces;
    /// five own settlements remove every current/future settlement site. The
    /// selected move and score loss are observations, never required road waste.
    @Test(arguments: [7, 8])
    func roadAndSpendDownTraceUsesActualExpertChoice(handSize: Int) throws {
        var state = try unattainableRoadPosition()
        try fund([.brick: 1, .lumber: 1, .wool: handSize - 2], seat: 0, in: &state)
        let rival = state.players[1]
        #expect(LongestRoad.length(for: rival, in: state) == state.rules.maxRoadsPerPlayer)
        #expect(state.longestRoadPlayer == rival.id)
        #expect(approaches(state, limit: 4).isEmpty)
        #expect(BoardIndex(state: state).buildableSites(for: state.players[0].id, in: state).isEmpty)
        for revision in revisions {
            let free = try trace("H10 hand=\(handSize) discipline=off", state: state,
                                 policy: EvaluationPolicy(handDiscipline: false, revision: revision), inspect: [.endTurn])
            let ruled = try trace("H10 hand=\(handSize) discipline=on", state: state,
                                  policy: EvaluationPolicy(revision: revision), inspect: [.endTurn])
            print("H6H10 override=\(free == .endTurn && ruled != .endTurn) revision=\(revision) hand=\(handSize)")
            if handSize > state.rules.discardThreshold {
                #expect(HandDiscipline.spends(ruled), "empty rivals cannot accept a proposal; a spending move exists")
            }
        }
    }

    // MARK: - Spatial fixtures

    private struct RobberPosition {
        var state: GameState
        let grain: HexCoordinate
        let slow: HexCoordinate
    }

    /// Swap two terrain faces, preserving the printed terrain/token bags and
    /// red-token spacing. Use a real coastal eight and its existing port.
    private func robberPosition(selfCollateral: Bool = false) throws -> RobberPosition {
        let shape = BoardGenerator.standard()
        let hot = try #require(shape.tiles.first { tile in
            tile.numberToken == 8 && shape.ports.contains {
                shape.corners(of: tile.coordinate).contains($0.vertexA)
                    || shape.corners(of: tile.coordinate).contains($0.vertexB)
            }
        })
        let donor = try #require(shape.tiles.first { $0.kind == .resource(.grain) })
        let tiles = shape.tiles.map { tile in
            Tile(coordinate: tile.coordinate,
                 kind: tile.coordinate == hot.coordinate ? .resource(.grain)
                    : tile.coordinate == donor.coordinate ? hot.kind : tile.kind,
                 numberToken: tile.numberToken)
        }
        let board = Board(tiles: tiles, ports: shape.ports, onBoardVertices: shape.onBoardVertices,
                          onBoardEdges: shape.onBoardEdges, robberTile: shape.robberTile)
        var state = GameSetup.newGame(board: board, seed: seed)
        try placeRobberBuildings(on: hot.coordinate, selfCollateral: selfCollateral, in: &state)
        let slow = try #require(tiles.first { $0.numberToken == 2 })
        let vertex = try #require(board.corners(of: slow.coordinate).first {
            state.phase = .setupForward(playerIndex: 2)
            return Building.canBuildSettlement($0, for: state.players[2].id, in: state)
        })
        try initialBuilding(vertex, seat: 2, in: &state)
        state.phase = .movingRobber(playerIndex: 0)
        return RobberPosition(state: state, grain: hot.coordinate, slow: slow.coordinate)
    }

    private func placeRobberBuildings(on tile: HexCoordinate, selfCollateral: Bool, in state: inout GameState) throws {
        let corners = state.board.corners(of: tile)
        let start = try #require(corners.indices.first { index in
            state.board.ports.contains { $0.vertexA == corners[index] || $0.vertexB == corners[index] }
        })
        for offset in [0, 2] {
            let vertex = corners[(start + offset) % corners.count]
            try initialBuilding(vertex, seat: 1, in: &state)
            try purchase(.buildCity(vertex), cost: Building.cityCost, seat: 1, in: &state)
        }
        if selfCollateral {
            let vertex = corners[(start + 4) % corners.count]
            try initialBuilding(vertex, seat: 0, in: &state)
            try purchase(.buildCity(vertex), cost: Building.cityCost, seat: 0, in: &state)
        }
    }

    private func roadPosition() throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
        let corners = state.board.corners(of: HexCoordinate(q: 0, r: 0))
        try initialBuilding(corners[0], seat: 0, road: EdgeID(corners[0], corners[1]), in: &state)
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }

    private func unattainableRoadPosition() throws -> GameState {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: seed)
        let path = try #require(state.board.onBoardVertices.sorted().lazy.compactMap {
            roadPath([$0], length: state.rules.maxRoadsPerPlayer, board: state.board)
        }.first)
        try initialBuilding(path[0], seat: 1, road: EdgeID(path[0], path[1]), in: &state)
        for index in 1..<state.rules.maxRoadsPerPlayer {
            try purchase(.buildRoad(EdgeID(path[index], path[index + 1])),
                         cost: Building.roadCost, seat: 1, in: &state)
        }
        try fillSettlements(excluding: Set(path), in: &state)
        state.phase = .mainTurn(playerIndex: 0)
        #expect(LongestRoad.length(for: state.players[1], in: state) == state.rules.maxRoadsPerPlayer)
        return state
    }

    private func roadPath(_ path: [VertexID], length: Int, board: Board) -> [VertexID]? {
        if path.count == length + 1 { return path }
        for next in board.adjacentVertices(of: path.last!) where !path.contains(next) {
            if let found = roadPath(path + [next], length: length, board: board) { return found }
        }
        return nil
    }

    private func fillSettlements(excluding: Set<VertexID> = [], in state: inout GameState) throws {
        while state.players[0].settlements.count < state.rules.pieceLimit(for: .settlement) {
            state.phase = .setupForward(playerIndex: 0)
            let vertex = try #require(state.board.onBoardVertices.sorted().first {
                !excluding.contains($0) && Building.canBuildSettlement($0, for: state.players[0].id, in: state)
            })
            try initialBuilding(vertex, seat: 0, in: &state)
        }
    }

    private func initialBuilding(_ vertex: VertexID, seat: Int, road: EdgeID? = nil, in state: inout GameState) throws {
        state.phase = .setupForward(playerIndex: seat)
        let player = state.players[seat].id
        let move = GameMove.placeInitialSettlement(vertex)
        try #require(RulesEngine.legalMoves(for: state, seat: player).contains(move))
        try RulesEngine.apply(move, by: player, to: &state)
        let edge = try #require(road ?? state.board.edgesTouching(vertex).first { candidate in
            !state.players.contains { $0.roads.contains(candidate) }
        })
        try #require(!state.players.contains { $0.roads.contains(edge) })
        let placement = GameMove.placeInitialRoad(edge)
        try #require(RulesEngine.legalMoves(for: state, seat: player).contains(placement))
        try RulesEngine.apply(placement, by: player, to: &state)
    }

    /// Fixture endowments come from the bank; purchases still pay engine costs.
    private func fund(_ hand: [Resource: Int], seat: Int, in state: inout GameState) throws {
        for resource in Resource.allCases {
            let available = (state.bank[resource] ?? 0) + (state.players[seat].resources[resource] ?? 0)
            let wanted = hand[resource] ?? 0
            try #require(wanted >= 0 && available >= wanted)
            state.bank[resource] = available - wanted
        }
        state.players[seat].resources = hand
    }

    private func purchase(_ move: GameMove, cost: [Resource: Int], seat: Int, in state: inout GameState) throws {
        state.phase = .mainTurn(playerIndex: seat)
        try fund(cost, seat: seat, in: &state)
        try #require(RulesEngine.legalMoves(for: state, seat: state.players[seat].id).contains(move))
        try RulesEngine.apply(move, by: state.players[seat].id, to: &state)
    }

    // MARK: - Independent engine oracle

    private func approaches(_ state: GameState, limit: Int) -> [VertexID: Int] {
        Dictionary(uniqueKeysWithValues: BoardIndex(state: state)
            .approachableSites(for: state.players[0].id, in: state, limit: limit).map { ($0.vertex, $0.roads) })
    }

    private func expectCurrentSitesMatchEngine(_ state: GameState) throws {
        let me = state.players[0].id
        let expected = state.board.onBoardVertices.sorted().filter { Building.canBuildSettlement($0, for: me, in: state) }
        #expect(BoardIndex(state: state).buildableSites(for: me, in: state) == expected)
    }

    private func engineApproaches(_ state: GameState, limit: Int) throws -> [VertexID: Int] {
        var distances: [VertexID: Int] = [:]
        try collectEngineSites(state, built: 0, limit: limit, distances: &distances)
        return distances.filter { $0.value > 0 }
    }

    private func collectEngineSites(_ state: GameState, built: Int, limit: Int, distances: inout [VertexID: Int]) throws {
        let me = state.players[0].id
        for vertex in state.board.onBoardVertices.sorted() where Building.canBuildSettlement(vertex, for: me, in: state) {
            distances[vertex] = min(distances[vertex] ?? built, built)
        }
        guard built < limit else { return }
        for edge in state.board.onBoardEdges.sorted() where Building.canBuildRoad(edge, for: me, in: state) {
            var next = state
            try purchase(.buildRoad(edge), cost: Building.roadCost, seat: 0, in: &next)
            try collectEngineSites(next, built: built + 1, limit: limit, distances: &distances)
        }
    }

    // MARK: - Production policy diagnostics

    private func after(_ move: GameMove, in state: GameState) throws -> GameState {
        var next = state
        let me = state.players[0].id
        let legal = RulesEngine.legalMoves(for: state, seat: me)
        try #require(legal.contains(move) || RulesEngine.isPermittedComposedProposal(move, by: me, in: state, legal: legal))
        try RulesEngine.apply(move, by: state.players[0].id, to: &next)
        return next
    }

    private func standing(_ player: PlayerID, in state: GameState, evaluator: PositionEvaluator) -> Double {
        evaluator.standing(of: player, in: state,
                           ledger: PublicLedger.fromPositionAlone(state, observer: evaluator.seat), board: BoardIndex(state: state))
    }

    private func trace(_ label: String, state: GameState, policy: EvaluationPolicy, inspect: [GameMove]) throws -> GameMove {
        let me = state.players[0].id
        let legal = RulesEngine.legalMoves(for: state, seat: me)
        let observation = GameObservation(seat: me, state: state, legalMoves: legal)
        let ledger = PublicLedger.fromPositionAlone(state, observer: me)
        var rng = RandomSource(seed: seed)
        let chosen = policy.decide(observation, ledger: ledger, rng: &rng)
        #expect(legal.contains(chosen) || RulesEngine.isPermittedComposedProposal(chosen, by: me, in: state, legal: legal))
        let scores = policy.candidateScores(observation, ledger: ledger)
        #expect(!scores.isEmpty && scores.allSatisfy { $0.score.isFinite })
        let selected = try #require(scores.first { $0.move == chosen })
        print("H6H10 \(label) policy=\(policy.id) chosen=\(chosen) score=\(selected.score)")
        printStandings(state, policy: policy)
        let end = scores.first { $0.move == .endTurn }?.score ?? selected.score
        let ranked = scores.filter { HandDiscipline.spends($0.move) }.sorted { $0.score > $1.score }.prefix(3)
        let moves = Set(inspect + [chosen] + ranked.map(\.move))
        for candidate in scores where moves.contains(candidate.move) {
            try printCandidate(candidate, state: state, ledger: ledger, policy: policy, end: end)
        }
        _ = try after(chosen, in: state)
        return chosen
    }

    private func printStandings(_ state: GameState, policy: EvaluationPolicy) {
        let evaluator = PositionEvaluator(seat: state.players[0].id, weights: policy.weights(for: state), revision: policy.revision)
        for player in state.players {
            let rate = ProductionModel.rate(for: player.id, in: state)
            let value = standing(player.id, in: state, evaluator: evaluator)
            print("H6H10 seat=\(player.id.index) publicVP=\(state.publicVictoryPoints(for: player.id)) standing=\(value)"
                + " production=\(Resource.allCases.map { rate[$0] }) bankRates=\(Resource.allCases.map { ProductionModel.bankRate(of: $0, for: player.id, in: state) })")
        }
    }

    private func printCandidate(_ candidate: ScoredCandidate, state: GameState, ledger: PublicLedger,
                                policy: EvaluationPolicy, end: Double) throws {
        let me = state.players[0].id
        let (next, _) = try #require(policy.applied(candidate.move, to: state, ledger: ledger, by: me))
        let weights = policy.weights(for: state)
        let lengthDelta = LongestRoad.length(for: next.players[0], in: next) - LongestRoad.length(for: state.players[0], in: state)
        let cardDelta = next.players[0].resources.values.reduce(0, +) - state.players[0].resources.values.reduce(0, +)
        print("H6H10 candidate=\(candidate.move) deltaVsEnd=\(candidate.score - end) cardsDelta=\(cardDelta)"
            + " roadLengthDelta=\(lengthDelta) linearRoadCredit=\(Double(lengthDelta) * weights.roadLength)"
            + " sites=\(BoardIndex(state: next).buildableSites(for: me, in: next).count) approaches=\(approaches(next, limit: 4).count)")
    }
}
