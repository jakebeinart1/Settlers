import SwiftUI
import CatanEngine

/// Charted harbor facts sit above cosmetic mist, without clearing any sea or
/// exposing a concealed island. The engine's public board owns this list.
struct NavalHarborLayer: View {
    let board: Board
    let geometry: HexGeometry
    let boardCenter: CGPoint
    let exposesSemantics: Bool

    var body: some View {
        let points = TileDrawing.portIconPoints(board: board, geometry: geometry, boardCenter: boardCenter)
        ZStack {
            Canvas { context, _ in
                for (index, port) in board.ports.enumerated() {
                    TileDrawing.drawPort(port, at: points[index], geometry: geometry, board: board, in: context)
                }
            }
            if exposesSemantics {
                ForEach(Array(board.ports.enumerated()), id: \.offset) { index, port in
                    marker(port, at: points[index], index: index)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func marker(_ port: CatanEngine.Port, at point: CGPoint, index: Int) -> some View {
        Color.white.opacity(0.001)
            .frame(width: 44, height: 44)
            .position(point)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(BoardInspectionSemantics.portLabel(port))
            .accessibilityValue(port.kind == .generic ? "3:1" : "2:1")
            .accessibilityIdentifier("naval.harbor.\(index)")
            .accessibilityRespondsToUserInteraction(false)
    }
}
