import SwiftUI
import CatanEngine

/// Range stays above decorative mist. It uses only the decision's public routes
/// and paints no hidden terrain, number, harbor or discovery information.
struct NavalSailingRangeLayer: View {
    let decision: BoardDecisionPresentation
    let geometry: HexGeometry
    let playerIdentity: (PlayerID) -> PlayerIdentity

    var body: some View {
        Canvas { context, _ in
            for coordinate in decision.blockadedTiles.keys.sorted() {
                drawBlockade(coordinate, in: context)
            }
            guard let sailing = decision.sailing else { return }
            for coordinate in decision.legalTiles {
                guard let route = sailing.routes[coordinate] else { continue }
                drawDestination(coordinate, cost: route.count, in: context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawBlockade(_ coordinate: HexCoordinate, in context: GraphicsContext) {
        guard let owner = decision.blockadedTiles[coordinate] else { return }
        let path = TileDrawing.hexPath(for: coordinate, geometry: geometry, scale: 0.92)
        let tint = playerIdentity(owner).civilization.accentColor
        context.stroke(path, with: .color(tint.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.8, dash: [4, 3]))
        let center = geometry.center(of: coordinate)
        let point = CGPoint(x: center.x, y: center.y - geometry.size * 0.53)
        context.draw(Text(Image(systemName: "shield.fill"))
            .font(.system(size: max(8, geometry.size * 0.22)))
            .foregroundColor(CatanTheme.onWaterText), at: point)
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
