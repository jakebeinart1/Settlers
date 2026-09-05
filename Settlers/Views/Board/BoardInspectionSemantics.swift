import SwiftUI
import CatanEngine

/// Read-only spatial semantics for inspect mode.
///
/// The board's ordinary accessibility elements are commands: build here or
/// move the robber here. Mandatory discard must remove those actions without
/// turning the position into one generic, content-free "Game board" element.
/// These markers preserve the tile, port, road and building facts at their
/// actual screen locations while exposing no action and accepting no touch.
struct BoardInspectionSemantics: View {
    let state: GameState
    let geometry: HexGeometry
    let boardCenter: CGPoint
    let playerIdentity: (PlayerID) -> PlayerIdentity

    var body: some View {
        ZStack {
            ForEach(state.board.tiles, id: \.coordinate) { tile in
                marker(
                    at: geometry.center(of: tile.coordinate),
                    label: tileLabel(tile),
                    identifier: AccessibilityID.Board.inspectionTile(tile.coordinate)
                )
            }

            ForEach(Array(state.board.ports.enumerated()), id: \.offset) { index, port in
                let a = geometry.vertexPosition(port.vertexA, board: state.board)
                let b = geometry.vertexPosition(port.vertexB, board: state.board)
                marker(
                    at: TileDrawing.portIconPoint(
                        a: a, b: b, boardCenter: boardCenter, size: geometry.size
                    ),
                    label: portLabel(port),
                    identifier: AccessibilityID.Board.inspectionPort(index)
                )
            }

            ForEach(state.players, id: \.id) { player in
                ForEach(player.settlements.sorted(), id: \.self) { vertex in
                    buildingMarker(vertex, player: player.id, kind: "Settlement")
                }
                ForEach(player.cities.sorted(), id: \.self) { vertex in
                    buildingMarker(vertex, player: player.id, kind: "City")
                }
                ForEach(player.roads.sorted(), id: \.self) { edge in
                    marker(
                        at: geometry.edgeMidpoint(edge, board: state.board),
                        label: "\(playerIdentity(player.id).displayName) road",
                        identifier: AccessibilityID.Board.inspectionRoad(edge)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func buildingMarker(_ vertex: VertexID, player: PlayerID, kind: String) -> some View {
        marker(
            at: geometry.vertexPosition(vertex, board: state.board),
            label: "\(playerIdentity(player).displayName) \(kind.lowercased())",
            identifier: AccessibilityID.Board.inspectionBuilding(vertex)
        )
    }

    private func marker(at point: CGPoint, label: String, identifier: String) -> some View {
        Color.white.opacity(0.001)
            .frame(width: 44, height: 44)
            .position(point)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier(identifier)
            .accessibilityRespondsToUserInteraction(false)
    }

    private func tileLabel(_ tile: Tile) -> String {
        let contents: String
        switch tile.kind {
        case .resource(let resource):
            contents = tile.numberToken.map { "\(resource.rawValue), number \($0)" } ?? resource.rawValue
        case .desert:
            contents = "Desert"
        }
        let robber = tile.coordinate == state.board.robberTile ? ", blocked by the robber" : ""
        return "\(contents) tile\(robber)"
    }

    private func portLabel(_ port: CatanEngine.Port) -> String {
        switch port.kind {
        case .generic:
            return "Three for one port"
        case .resource(let resource):
            return "Two \(resource.rawValue) for one port"
        }
    }
}
