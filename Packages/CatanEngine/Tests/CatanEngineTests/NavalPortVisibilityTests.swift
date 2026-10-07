import Foundation
import Testing
@testable import CatanEngine

struct NavalPortVisibilityTests {
    @Test(arguments: NavalMapFamily.allCases)
    func openingChartsHomeHarborsWithoutDiscoveringTheirSea(family: NavalMapFamily) throws {
        let state = Naval.newGame(seed: 73, options: NavalOptions(mapFamily: family))
        let home = homePorts(in: state)
        let publicBoard = Naval.visibleBoard(in: state)
        #expect(home.count == 4)
        #expect(publicBoard.ports == home)
        #expect(home.filter { $0.kind == .generic }.count == 2)
        #expect(home.contains { $0.kind == .resource(.grain) })
        #expect(home.contains { $0.kind == .resource(.wool) })
        #expect(state.board.ports.count == 9)
        let unknown = Set(state.board.tiles.map(\.coordinate)).subtracting(state.naval!.revealed)
        #expect(Set(publicBoard.tiles.filter { $0.kind == .fog }.map(\.coordinate)) == unknown)
        #expect(publicBoard.tiles.filter { unknown.contains($0.coordinate) }.allSatisfy { $0.numberToken == nil })
        var masked = state
        masked.board = publicBoard
        #expect(Naval.visibleBoard(in: masked) == publicBoard)
        let observation = GameObservation(seat: state.players[0].id, state: state, legalMoves: [])
        #expect(observation.state.board == publicBoard)
        #expect(try JSONDecoder().decode(GameObservation.self, from: JSONEncoder().encode(observation)) == observation)
    }

    @Test func discoveringAnOverseasCoastChartsItsHarborWhileOtherHexesStayFogged() throws {
        var state = Naval.newGame(seed: 73)
        let port = try #require(state.board.ports.first { !homePorts(in: state).contains($0) })
        let shared = Set(port.vertexA.touchingTiles).intersection(port.vertexB.touchingTiles)
        let sea = try #require(state.board.tiles.first { shared.contains($0.coordinate) && $0.kind == .sea })
        let land = try #require(state.board.tiles.first { shared.contains($0.coordinate) && $0.kind.isLand })
        state.naval?.revealed.insert(sea.coordinate)
        #expect(!Naval.visibleBoard(in: state).ports.contains(port))
        state.naval?.revealed.insert(land.coordinate)
        let publicBoard = Naval.visibleBoard(in: state)
        #expect(publicBoard.ports.contains(port))
        let bordering = Set(port.vertexA.touchingTiles).union(port.vertexB.touchingTiles)
        #expect(publicBoard.tiles.contains { bordering.contains($0.coordinate) && $0.kind == .fog })
        var masked = state
        masked.board = publicBoard
        #expect(Naval.visibleBoard(in: masked) == publicBoard)
    }

    @Test func concealedTerrainAndPortsCannotChangeChartedHarbors() throws {
        var state = Naval.newGame(seed: 73)
        let seat = state.players[0].id
        let before = GameObservation(seat: seat, state: state, legalMoves: [])
        let hidden = try #require(state.board.tiles.first {
            $0.kind.isLand && !Naval.isRevealed($0.coordinate, in: state)
        })
        let corners = state.board.corners(of: hidden.coordinate)
        let privatePort = CatanEngine.Port(vertexA: corners[0], vertexB: corners[1], kind: .resource(.ore))
        let tiles = state.board.tiles.map { tile in
            Naval.isRevealed(tile.coordinate, in: state) ? tile
                : Tile(coordinate: tile.coordinate, kind: .resource(.ore), numberToken: 6)
        }
        state.board = Board(tiles: tiles, ports: state.board.ports + [privatePort],
                            onBoardVertices: state.board.onBoardVertices, onBoardEdges: state.board.onBoardEdges,
                            robberTile: state.board.robberTile)
        #expect(GameObservation(seat: seat, state: state, legalMoves: []) == before)
    }

    @Test(arguments: [PortKind.generic, .resource(.grain), .resource(.wool)])
    func chartedPortNeedsAnOwnedBuildingAndPreservesActualBankRates(kind: PortKind) throws {
        var state = Naval.newGame(seed: 73)
        state.phase = .mainTurn(playerIndex: 0)
        let owner = state.players[0].id
        let port = try #require(homePorts(in: state).first { $0.kind == kind })
        for resource in Resource.allCases {
            #expect(Trading.bestRate(for: resource, player: owner, state: state) == 4)
        }
        state.players[0].settlements.insert(port.vertexA)
        try expectRates(kind: kind, in: state)
        state.players[0].settlements.remove(port.vertexA)
        state.players[0].cities.insert(port.vertexA)
        try expectRates(kind: kind, in: state)
    }

    private func expectRates(kind: PortKind, in state: GameState) throws {
        let owner = state.players[0].id
        let observation = GameObservation(seat: owner, state: state, legalMoves: [])
        for resource in Resource.allCases {
            let rate = kind == .generic ? 3 : (kind == .resource(resource) ? 2 : 4)
            #expect(Trading.bestRate(for: resource, player: owner, state: state) == rate)
            #expect(Trading.bestRate(for: resource, player: owner, state: observation.state) == rate)
            var traded = state
            NavalTestSupport.fund([resource: rate], in: &traded)
            let received = try #require(Resource.allCases.first { $0 != resource })
            let bankBefore = traded.bank
            try RulesEngine.apply(.bankTrade(give: [resource: rate], get: [received: 1]), by: owner, to: &traded)
            #expect(traded.players[0].resources[resource, default: 0] == 0)
            #expect(traded.players[0].resources[received, default: 0] == 1)
            #expect(traded.bank[resource, default: 0] == bankBefore[resource, default: 0] + rate)
            #expect(traded.bank[received, default: 0] == bankBefore[received, default: 0] - 1)
        }
    }

    private func homePorts(in state: GameState) -> [CatanEngine.Port] {
        state.board.ports.filter { port in
            let shared = Set(port.vertexA.touchingTiles).intersection(port.vertexB.touchingTiles)
            return shared.contains { state.naval?.islandByHex[$0] == 0 }
        }
    }
}
