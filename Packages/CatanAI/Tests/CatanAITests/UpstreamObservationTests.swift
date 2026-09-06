import Foundation
import Testing
import CatanEngine
@testable import CatanAI

@Suite struct UpstreamObservationTests {
    @Test func liveSetupContextMatchesRustWithoutAnOverride() throws {
        let url = try #require(Bundle.module.url(forResource: "upstream-observations", withExtension: "jsonl", subdirectory: "Fixtures"))
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let fixture = try JSONDecoder().decode(UpstreamObservationFixture.self, from: Data(line.utf8))
            guard fixture.gamePhase < 2 else { continue }
            var state = fixture.makeState()
            state.phase = fixture.gamePhase == 0
                ? .setupForward(playerIndex: fixture.seat) : .setupBackward(playerIndex: fixture.seat)
            let actual = try UpstreamObservation.encode(state: state, seat: PlayerID(index: fixture.seat))
            for index in actual.indices {
                #expect(abs(actual[index] - fixture.features[index]) < 0.000_001,
                        "live setup slot \(index), seat \(fixture.seat)")
            }
        }
    }

    @Test func matchesPinnedRustEncoderOnRealThreeAndFourSeatPositions() throws {
        let url = try #require(Bundle.module.url(forResource: "upstream-observations", withExtension: "jsonl", subdirectory: "Fixtures"))
        let fixtures = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try JSONDecoder().decode(UpstreamObservationFixture.self, from: Data($0.utf8))
        }
        #expect(fixtures.count >= 35)
        #expect(Set(fixtures.map(\.players)) == [3, 4])
        #expect(Set(fixtures.map(\.seat)) == [0, 1, 2, 3])
        for fixture in fixtures {
            let state = fixture.makeState()
            let layout = try UpstreamBoardLayout(board: state.board)
            #expect(layout.edges.map { [layout.vertices.firstIndex(of: $0.a)!, layout.vertices.firstIndex(of: $0.b)!].sorted() } == fixture.edgeVertices)
            var context = UpstreamDecisionContext(state: state, seat: PlayerID(index: fixture.seat))
            context.gamePhase = fixture.gamePhase
            context.turnPhase = fixture.turnPhase
            context.turnOwner = PlayerID(index: fixture.turnOwner)
            context.hasRolled = fixture.hasRolled
            context.roadsToPlace = fixture.roadsToPlace
            context.discardsRemaining = fixture.discardsRemaining
            let actual = try UpstreamObservation.encode(state: state, seat: PlayerID(index: fixture.seat), context: context)
            #expect(actual.count == fixture.features.count)
            for index in actual.indices {
                #expect(abs(actual[index] - fixture.features[index]) < 0.000_001,
                        "slot \(index), seat \(fixture.seat), phase \(fixture.gamePhase)/\(fixture.turnPhase)")
            }
        }
    }

    @Test func refusesLegacyTurnGuessAndInvalidSeat() throws {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 1)
        state.completedTurnCount = nil
        #expect(throws: UpstreamObservation.EncodingError.self) {
            try UpstreamObservation.encode(state: state, seat: PlayerID(index: 0))
        }
        state.completedTurnCount = 0
        #expect(throws: UpstreamObservation.EncodingError.self) {
            try UpstreamObservation.encode(state: state, seat: PlayerID(index: 4))
        }
    }

    @Test func rejectsMalformedTopologyInsteadOfTrappingOrReindexing() throws {
        let standard = BoardGenerator.standard()
        let vertices = standard.onBoardVertices.sorted()
        var changed = standard.onBoardEdges
        changed.remove(changed.sorted()[0])
        let nonadjacent = try #require(vertices.first { !standard.onBoardEdges.contains(EdgeID(vertices[0], $0)) && $0 != vertices[0] })
        changed.insert(EdgeID(vertices[0], nonadjacent))
        let fake = VertexID(touchingTiles: [HexCoordinate(q: 99, r: 99)])
        var absent = standard.onBoardEdges
        absent.remove(absent.sorted()[0])
        absent.insert(EdgeID(vertices[0], fake))
        for (tiles, edges) in [(standard.tiles + [standard.tiles[0]], standard.onBoardEdges),
                               (standard.tiles, changed), (standard.tiles, absent)] {
            let board = Board(tiles: tiles, ports: standard.ports, onBoardVertices: standard.onBoardVertices,
                              onBoardEdges: edges, robberTile: standard.robberTile)
            #expect(throws: UpstreamBoardLayout.LayoutError.self) { try UpstreamBoardLayout(board: board) }
        }
    }

    @Test func mainTurnOwnerDoesNotUseStaleRobberBookkeeping() {
        var state = GameSetup.newGame(board: BoardGenerator.standard(), seed: 3)
        state.phase = .mainTurn(playerIndex: 2)
        state.robberMoverIndex = 0
        #expect(UpstreamDecisionContext(state: state, seat: PlayerID(index: 2)).turnOwner == PlayerID(index: 2))
    }
}

/// Raw upstream fields are converted to typed Empires state independently of
/// the feature encoder. Expected values come from Rust, not a second Swift
/// formula that could share the encoder's mistake.
struct UpstreamObservationFixture: Decodable {
    let players: Int
    let seat: Int
    let turnOwner: Int
    let turn: Int
    let gamePhase: Int
    let turnPhase: Int
    let target: Int
    let dice: Int
    let hasRolled: Bool
    let roadsToPlace: Int
    let discardsRemaining: Int
    let trades: Int
    let tileResources: [Int]
    let tileNumbers: [Int]
    let portTypes: [Int]
    let vertices: [Int]
    let edges: [Int]
    let resources: [[Int]]
    let devCards: [[Int]]
    let bought: [Int]
    let knights: [Int]
    let bank: [Int]
    let robber: Int
    let longest: Int
    let largest: Int
    let tileVertices: [[Int]]
    let edgeVertices: [[Int]]
    let portVertices: [[Int]]
    let features: [Float]

    func makeState() -> GameState {
        let standard = BoardGenerator.standard()
        let coordinates = standard.tiles.map(\.coordinate).sorted { ($0.r, $0.q) < ($1.r, $1.q) }
        let mapped = makeVertices(coordinates)
        let tiles = coordinates.enumerated().map { index, coordinate in
            Tile(coordinate: coordinate,
                 kind: tileResources[index] == 5 ? .desert : .resource(UpstreamObservation.resources[tileResources[index]]),
                 numberToken: tileNumbers[index] == 0 ? nil : tileNumbers[index])
        }
        let ports = portVertices.enumerated().map { index, pair in
            Port(vertexA: mapped[pair[0]], vertexB: mapped[pair[1]],
                 kind: portTypes[index] == 0 ? .generic : .resource(UpstreamObservation.resources[portTypes[index] - 1]))
        }
        let board = Board(tiles: tiles, ports: ports, onBoardVertices: standard.onBoardVertices,
                          onBoardEdges: standard.onBoardEdges, robberTile: coordinates[robber])
        var state = GameSetup.newGame(board: board, seed: 1, playerCount: players, victoryPointTarget: target)
        state.completedTurnCount = turn
        state.tradesProposedThisTurn = trades
        state.lastDiceRoll = dice == 0 ? nil : dice
        state.longestRoadPlayer = longest < 0 ? nil : PlayerID(index: longest)
        state.largestArmyPlayer = largest < 0 ? nil : PlayerID(index: largest)
        state.bank = Dictionary(uniqueKeysWithValues: zip(UpstreamObservation.resources, bank))
        state.players = (0..<players).map { makePlayer($0, vertices: mapped) }
        state.devCardsBoughtThisTurn = [PlayerID(index: seat): expandCards(bought)]
        return state
    }

    private func makeVertices(_ tiles: [HexCoordinate]) -> [VertexID] {
        var mapped = [VertexID?](repeating: nil, count: 54)
        // Top clockwise corners correspond to neighbor pairs 1/2,0/1,5/0,
        // 4/5,3/4,2/3 in Empires' anticlockwise neighbor-direction convention.
        for (tile, ids) in zip(tiles, tileVertices) {
            for (corner, between) in [1, 0, 5, 4, 3, 2].enumerated() {
                mapped[ids[corner]] = VertexID(touchingTiles: [tile, tile.neighbor(between), tile.neighbor(between + 1)])
            }
        }
        return mapped.map { $0! }
    }

    private func makePlayer(_ index: Int, vertices mapped: [VertexID]) -> Player {
        Player(id: PlayerID(index: index),
               resources: Dictionary(uniqueKeysWithValues: zip(UpstreamObservation.resources, resources[index])),
               devCards: expandCards(devCards[index]), playedKnights: knights[index],
               settlements: Set(vertices.indices.filter { vertices[$0] == index }.map { mapped[$0] }),
               cities: Set(vertices.indices.filter { vertices[$0] == index + 4 }.map { mapped[$0] }),
               roads: Set(edges.indices.filter { edges[$0] == index }.map { EdgeID(mapped[edgeVertices[$0][0]], mapped[edgeVertices[$0][1]]) }))
    }

    private func expandCards(_ counts: [Int]) -> [DevCardType] {
        counts.enumerated().flatMap { index, count in Array(repeating: UpstreamObservation.cards[index], count: count) }
    }
}
