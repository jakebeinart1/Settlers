import Foundation
import Testing
import CatanEngine
@testable import CatanAI

/// A revision identifies the actual Expert brain, not an identity or difficulty.
@Suite struct ExpertRevisionTests {
    @Test func revisionsHaveDistinctCheckpointIdentities() {
        #expect(EvaluationPolicy().id == "evaluation-v1")
        #expect(EvaluationPolicy(revision: .cityProductionV1).id == "evaluation-city-production-v1")
    }

    /// Two 5-pip tiles: ore and grain each produce 5/36 per roll.
    /// Ore limits the 3-ore/2-grain recipe to 5/108 cities per roll;
    /// at the frozen 0.7 value the extra standing is exactly 7/216.
    @Test func matchedProductionAddsTheFrozenValueAndCitiesDoubleIt() throws {
        var state = try economyPosition()
        let seat = state.players[0].id
        #expect(abs(standingGain(state, seat: seat) - 7.0 / 216.0) < 1e-12)
        let vertex = try #require(state.players[0].settlements.first)
        state.players[0].settlements.remove(vertex)
        state.players[0].cities.insert(vertex)
        #expect(abs(standingGain(state, seat: seat) - 7.0 / 108.0) < 1e-12)
    }

    @Test func blockedCityIngredientEarnsNoExtraStanding() throws {
        var state = try economyPosition()
        let ore = try #require(state.board.tiles.first { $0.kind == .resource(.ore) })
        state.board.robberTile = ore.coordinate
        #expect(standingGain(state, seat: state.players[0].id) == 0)
    }

    @Test func rivalProductionIsValuedWithoutReadingTheirResourceComposition() throws {
        var state = try economyPosition()
        let rival = state.players[1].id
        state.players[1].settlements = state.players[0].settlements
        state.players[0].settlements = []
        #expect(abs(standingGain(state, seat: rival) - 7.0 / 216.0) < 1e-12)
        let me = state.players[0].id
        let ledger = PublicLedger.fromPositionAlone(state, observer: me)
        let evaluator = PositionEvaluator(seat: me, revision: .cityProductionV1)
        let before = evaluator.evaluate(state, ledger: ledger)
        state.players[1].resources = [.ore: 99, .grain: 99]
        #expect(evaluator.evaluate(state, ledger: ledger) == before)
        #expect(before < PositionEvaluator(seat: me).evaluate(state, ledger: ledger))
    }

    @Test func diagnosticsForwardRevisionWhileUnselectedCallersStayLegacy() throws {
        let state = try economyPosition()
        let seat = state.players[0].id
        let observation = GameObservation(seat: seat, state: state, legalMoves: [.endTurn])
        let ledger = PublicLedger.fromPositionAlone(state, observer: seat)
        let old = EvaluationPolicy().candidateScores(observation, ledger: ledger)
        #expect(old == EvaluationPolicy(revision: .legacy).candidateScores(observation, ledger: ledger))
        let current = EvaluationPolicy(revision: .cityProductionV1).candidateScores(observation, ledger: ledger)
        let oldScore = try #require(old.first?.score)
        let newScore = try #require(current.first?.score)
        #expect(abs(newScore - oldScore - 7.0 / 216.0) < 1e-12)
    }

    @Test func currentExpertCheckpointContinuesTheSameMovesAndRejectsLegacyPolicies() throws {
        let state = GameSetup.newGame(board: BoardGenerator.randomized(seed: 741), seed: 741)
        let policies = Dictionary(uniqueKeysWithValues: state.players.map {
            ($0.id, EvaluationPolicy(revision: .cityProductionV1) as any Policy)
        })
        var original = GameSession(state: state, policies: policies, policySeed: 741)
        for _ in 0..<30 { _ = try #require(try original.step()) }
        let checkpoint = try JSONDecoder().decode(GameSession.Checkpoint.self,
            from: JSONEncoder().encode(original.checkpoint))
        var resumed = try GameSession(checkpoint: checkpoint, policies: policies)
        for _ in 0..<30 {
            let first = try #require(try original.step())
            let second = try #require(try resumed.step())
            #expect(first.actor == second.actor)
            #expect(first.move == second.move)
            #expect(first.events == second.events)
            #expect(original.checkpoint == resumed.checkpoint)
        }
        let legacy = Dictionary(uniqueKeysWithValues: state.players.map { ($0.id, EvaluationPolicy() as any Policy) })
        #expect(throws: (any Error).self) { try GameSession(checkpoint: checkpoint, policies: legacy) }
    }

    private func standingGain(_ state: GameState, seat: PlayerID) -> Double {
        let ledger = PublicLedger.fromPositionAlone(state, observer: state.players[0].id)
        let board = BoardIndex(state: state)
        let current = PositionEvaluator(seat: state.players[0].id, revision: .cityProductionV1)
        let old = PositionEvaluator(seat: state.players[0].id)
        return current.standing(of: seat, in: state, ledger: ledger, board: board)
            - old.standing(of: seat, in: state, ledger: ledger, board: board)
    }

    /// An analytic scoring position, not an opening-placement simulation.
    /// All other tiles are barren so the worked value has no extra inputs.
    private func economyPosition() throws -> GameState {
        let shape = BoardGenerator.standard()
        let vertex = try #require(shape.onBoardVertices.sorted().first { candidate in
            shape.neighborTiles(of: candidate).allSatisfy { coordinate in
                shape.tiles.contains { $0.coordinate == coordinate }
            }
        })
        let adjacent = shape.neighborTiles(of: vertex).sorted()
        let tiles = shape.tiles.map { tile in
            Tile(coordinate: tile.coordinate,
                 kind: tile.coordinate == adjacent[0] ? .resource(.ore)
                    : tile.coordinate == adjacent[1] ? .resource(.grain) : .desert,
                 numberToken: adjacent.prefix(2).contains(tile.coordinate) ? 6 : nil)
        }
        let board = Board(tiles: tiles, ports: shape.ports, onBoardVertices: shape.onBoardVertices,
                          onBoardEdges: shape.onBoardEdges, robberTile: adjacent[2])
        var state = GameSetup.newGame(board: board, seed: 741)
        state.players[0].settlements = [vertex]
        state.phase = .mainTurn(playerIndex: 0)
        return state
    }
}
