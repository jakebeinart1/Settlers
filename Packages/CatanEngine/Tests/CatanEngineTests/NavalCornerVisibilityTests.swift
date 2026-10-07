import Testing
@testable import CatanEngine

struct NavalCornerVisibilityTests {
    private static let translations = [HexCoordinate(q: 0, r: 0), HexCoordinate(q: 4, r: -3)]
    private static let referenceFootprint: Set<HexCoordinate> = [
        HexCoordinate(q: -1, r: 0), HexCoordinate(q: -1, r: 1),
        HexCoordinate(q: 0, r: -1), HexCoordinate(q: 0, r: 0), HexCoordinate(q: 0, r: 1),
        HexCoordinate(q: 1, r: -2), HexCoordinate(q: 1, r: -1), HexCoordinate(q: 1, r: 0), HexCoordinate(q: 1, r: 1),
        HexCoordinate(q: 2, r: -2), HexCoordinate(q: 2, r: -1), HexCoordinate(q: 2, r: 0)
    ]

    @Test(arguments: 0..<6, translations)
    func cornerFootprintIsCenteredSymmetricAndHasExactCutoff(rotation: Int, origin: HexCoordinate) {
        let corner = HexGeometry.corner(of: origin, between: rotation)
        let expected = Set(Self.referenceFootprint.map { translated(rotated($0, times: rotation), by: origin) })
        let candidates = BoardGenerator.spiralCoordinates(radius: 4).map { translated($0, by: origin) }
        let actual = Set(candidates.filter { Naval.isWithinViewingRange($0, of: corner) })
        #expect(actual == expected)
        #expect(actual.count == 12)
        #expect(corner.touchingTiles.allSatisfy(actual.contains))
        #expect(!actual.contains(translated(rotated(HexCoordinate(q: -1, r: -1), times: rotation), by: origin)))
        #expect(!actual.contains(translated(rotated(HexCoordinate(q: -2, r: 0), times: rotation), by: origin)))
        #expect(Set(candidates.filter { withinPhysicalCircle($0, of: corner) }) == actual)
    }

    @Test(arguments: 0..<6, 1...7)
    func terrainDoesNotChangeTheCornerOriginOrDiscoveryEvents(rotation: Int, landMask: Int) {
        let origin = Self.translations[1]
        let corner = HexGeometry.corner(of: origin, between: rotation)
        var state = fixture(corner: corner, landMask: landMask, origin: origin)
        let player = state.players[0].id
        let expected = Self.referenceFootprint.map { translated(rotated($0, times: rotation), by: origin) }.sorted()
        let events = Naval.revealBuilding(at: corner, by: player, in: &state)
        #expect(state.naval?.revealed == Set(expected))
        #expect(events == [.discovered(player, hexes: expected)])
    }

    @Test func theCompleteCanonicalCornerIncludesSeaAndOffEnvelopeCoordinates() {
        let corner = HexGeometry.corner(of: HexCoordinate(q: 7, r: 0), between: 0)
        #expect(corner.touchingTiles == [HexCoordinate(q: 7, r: 0), HexCoordinate(q: 8, r: -1), HexCoordinate(q: 8, r: 0)])
        #expect(Naval.isWithinViewingRange(HexCoordinate(q: 9, r: -1), of: corner))
        #expect(!Naval.isWithinViewingRange(HexCoordinate(q: 5, r: 0), of: corner))
    }

    @Test func previousPublicDiscoveriesStayVisibleAndRepeatedDiscoveryProducesNoEvent() {
        let origin = HexCoordinate(q: 0, r: 0)
        let corner = HexGeometry.corner(of: origin, between: 0)
        var state = fixture(corner: corner, landMask: 1, origin: origin)
        let previous = HexCoordinate(q: -4, r: 0)
        state.naval?.revealed.insert(previous)
        _ = Naval.revealBuilding(at: corner, by: state.players[0].id, in: &state)
        #expect(state.naval?.revealed == Self.referenceFootprint.union([previous]))
        #expect(Naval.revealBuilding(at: corner, by: state.players[1].id, in: &state).isEmpty)
        #expect(Naval.visibleBoard(in: state).tiles.filter { $0.kind == .fog }.allSatisfy {
            !Self.referenceFootprint.contains($0.coordinate) && $0.coordinate != previous
        })
    }

    @Test(arguments: translations)
    func shipVisionRetainsItsNineteenHexFootprintAndSixCardinalBoundaries(origin: HexCoordinate) {
        let corner = HexGeometry.corner(of: origin, between: 0)
        var state = fixture(corner: corner, landMask: 1, origin: origin)
        _ = Naval.reveal(around: [origin], by: state.players[0].id, in: &state)
        let expected = Set(BoardGenerator.spiralCoordinates(radius: 2).map { translated($0, by: origin) })
        #expect(state.naval?.revealed == expected)
        #expect(expected.count == 19)
        for direction in HexCoordinate.neighborDirections {
            #expect(expected.contains(HexCoordinate(q: origin.q + direction.0 * 2, r: origin.r + direction.1 * 2)))
            #expect(!expected.contains(HexCoordinate(q: origin.q + direction.0 * 3, r: origin.r + direction.1 * 3)))
        }
        for rotation in 0..<6 {
            let footprint = Set(expected.map { coordinate in
                translated(rotated(HexCoordinate(q: coordinate.q - origin.q, r: coordinate.r - origin.r), times: rotation), by: origin)
            })
            #expect(footprint == expected)
        }
    }

    private func fixture(corner: VertexID, landMask: Int, origin: HexCoordinate) -> GameState {
        let land = Set(corner.touchingTiles.enumerated().filter { landMask & (1 << $0.offset) != 0 }.map(\.element))
        let tiles = BoardGenerator.spiralCoordinates(radius: 4).map { coordinate in
            let position = translated(coordinate, by: origin)
            return Tile(coordinate: position, kind: land.contains(position) ? .resource(.lumber) : .sea, numberToken: nil)
        }
        let board = Naval.landBoard(tiles: tiles, ports: [], robber: origin)
        let players = (0..<4).map { Player(id: PlayerID(index: $0)) }
        return GameState(board: board, players: players, phase: .mainTurn(playerIndex: 0), bank: [:], devCardDeck: [],
                         rng: RandomSource(seed: 19), mode: .naval, victoryPointTarget: 14, naval: NavalState())
    }

    private func withinPhysicalCircle(_ coordinate: HexCoordinate, of corner: VertexID) -> Bool {
        let q = 3 * coordinate.q - corner.touchingTiles.map(\.q).reduce(0, +)
        let r = 3 * coordinate.r - corner.touchingTiles.map(\.r).reduce(0, +)
        return q * q + q * r + r * r <= 36
    }

    private func rotated(_ coordinate: HexCoordinate, times: Int) -> HexCoordinate {
        (0..<times).reduce(coordinate) { coordinate, _ in HexCoordinate(q: coordinate.q + coordinate.r, r: -coordinate.q) }
    }

    private func translated(_ coordinate: HexCoordinate, by origin: HexCoordinate) -> HexCoordinate {
        HexCoordinate(q: coordinate.q + origin.q, r: coordinate.r + origin.r)
    }
}
