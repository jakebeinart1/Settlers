#if DEBUG
import CatanEngine
import Foundation
import SwiftUI

/// An explicit replacement baseline matching the reported island position:
/// a coastal founder, two connected roads and an existing rival inland town.
/// The generated terrain is unchanged and the two further roads are funded
/// from the bank. Native taps, rather than this fixture, build those exits.
enum NavalRoadJunctionQAFixture {
    private static let seed: UInt64 = 73
    private static let actor = PlayerID(index: 0)
    private static let rival = PlayerID(index: 1)
    private static let additionalRoads = 2

    static let start = vertex([(-7, 6), (-7, 7), (-6, 6)])
    static let middle = vertex([(-7, 7), (-6, 6), (-6, 7)])
    static let junction = vertex([(-6, 6), (-6, 7), (-5, 6)])
    static let upper = EdgeID(junction, vertex([(-6, 6), (-5, 5), (-5, 6)]))
    static let lower = EdgeID(junction, vertex([(-6, 7), (-5, 6), (-5, 7)]))

    static func make() -> GameState {
        var state = Naval.newGame(seed: seed, options: NavalOptions(fogEnabled: false))
        let approach = [EdgeID(start, middle), EdgeID(middle, junction)]
        state.phase = .mainTurn(playerIndex: actor.index)
        state.players[actor.index].settlements = [start]
        state.players[actor.index].roads = Set(approach)
        state.players[rival.index].settlements = [junction]
        recordColony(at: start, for: actor, in: &state)
        recordColony(at: junction, for: rival, in: &state)
        NavalQAFixture.grant(Building.roadCost.mapValues { $0 * additionalRoads }, to: actor, in: &state)
        validate(state, approach: approach)
        return state
    }

    static func branches(in state: GameState) -> [EdgeID] {
        state.board.edgesTouching(junction).filter { $0 != EdgeID(middle, junction) }
    }

    private static func validate(_ state: GameState, approach: [EdgeID]) {
        precondition(state.naval?.rulesVersion == Naval.currentRulesVersion)
        precondition(Naval.isCoastal(start, in: state) && !Naval.isCoastal(junction, in: state))
        precondition(junction.touchingTiles.allSatisfy { Naval.isKnownLand($0, in: state) })
        precondition(!state.board.adjacentVertices(of: start).contains(junction))
        precondition(approach.allSatisfy { isKnownLandEdge($0, in: state) })
        let exits = branches(in: state)
        precondition(Set(exits) == [upper, lower] && exits.count == additionalRoads)
        precondition(exits.allSatisfy { Building.canBuildRoad($0, for: actor, in: state) })
        precondition(Naval.validationProblem(in: state) == nil)
        precondition(LongestRoad.length(for: state.players[actor.index], in: state) == approach.count)
    }

    /// Colonies are historical baseline facts here, just like the two towns;
    /// no ship is allowed to found the inland rival town during preparation.
    private static func recordColony(at vertex: VertexID, for owner: PlayerID, in state: inout GameState) {
        let islands = Set(vertex.touchingTiles.compactMap { state.naval?.islandByHex[$0] }.filter { $0 > 0 })
        precondition(islands.count == 1)
        state.naval?.colonizedIslands[owner] = islands
        state.naval?.colonyPoints[owner] = islands.count
    }

    private static func vertex(_ coordinates: [(Int, Int)]) -> VertexID {
        VertexID(touchingTiles: Set(coordinates.map { HexCoordinate(q: $0.0, r: $0.1) }))
    }

    private static func isKnownLandEdge(_ edge: EdgeID, in state: GameState) -> Bool {
        let touching = Set(edge.a.touchingTiles).intersection(edge.b.touchingTiles)
        return state.board.onBoardEdges.contains(edge) && touching.contains { Naval.isKnownLand($0, in: state) }
    }
}

extension BoardView {
    /// A sibling leaf reads actual committed roads and projected geometry;
    /// it changes neither the camera nor the game and is absent from Release.
    /// The separate inspection argument remains valid on a cold resume without
    /// asking the launch handler to replace the saved position again.
    @ViewBuilder
    func qaNavalRoadJunctionMarkers(geometry: HexGeometry) -> some View {
        if state.mode == .naval, QALaunchFlag.navalRoadJunctionInspection.isSet {
            let fixture = NavalRoadJunctionQAFixture.self
            let point = geometry.vertexPosition(fixture.junction, board: board)
            let roads = state.players[0].roads
            let geometryValue = String(format: "x=%.6f;y=%.6f;hexSize=%.6f", Double(point.x), Double(point.y), Double(geometry.size))
            let stateValue = ";roads=\(roads.count);upperOwned=\(roads.contains(fixture.upper) ? 1 : 0);lowerOwned=\(roads.contains(fixture.lower) ? 1 : 0)"
            Color.white.opacity(0.001)
                .frame(width: 1, height: 1).position(point)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("qa.naval-road-junction.state")
                .accessibilityLabel("Committed public roads at the island junction")
                .accessibilityValue(geometryValue + stateValue)
                .accessibilityRespondsToUserInteraction(false)
                .allowsHitTesting(false)
        }
    }
}
#endif
