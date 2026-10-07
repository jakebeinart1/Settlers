import SwiftUI
import CatanEngine

/// Range stays above decorative mist. It uses only the decision's public routes
/// and paints no hidden terrain, number, harbor or discovery information.
struct NavalSailingRangeLayer: View {
    let decision: BoardDecisionPresentation
    let geometry: HexGeometry

    var body: some View {
        Canvas { context, _ in
            guard let sailing = decision.sailing else { return }
            for coordinate in decision.legalTiles {
                guard let route = sailing.routes[coordinate] else { continue }
                drawDestination(coordinate, cost: route.count, in: context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawDestination(_ coordinate: HexCoordinate, cost: Int, in context: GraphicsContext) {
        let selected = coordinate == decision.selectedTile
        let path = TileDrawing.hexPath(for: coordinate, geometry: geometry, scale: 0.92)
        context.fill(path, with: .color(CatanTheme.chipGold.opacity(selected ? 0.20 : 0.07)))
        context.stroke(path, with: .color(CatanTheme.chipGold.opacity(selected ? 1 : 0.82)),
                       lineWidth: selected ? 3 : 1.5)
        let center = geometry.center(of: coordinate)
        let point = CGPoint(x: center.x, y: center.y - geometry.size * 0.53)
        let radius = max(4, min(11, geometry.size * 0.16))
        let badge = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                          width: radius * 2, height: radius * 2))
        context.fill(badge, with: .color(CatanTheme.numberTokenBackground))
        context.draw(Text(String(cost)).font(.system(size: radius * 1.35, weight: .bold, design: .serif))
            .foregroundColor(CatanTheme.waterBackground), at: point)
    }
}
