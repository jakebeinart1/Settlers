import SwiftUI
import CatanEngine

/// Dense cloud banks cover an exact opaque hidden-cell core. A decorative
/// frontier extends into known cells; its transparency never exposes unknown
/// terrain. The field uses public coordinates only and has no idle animation.
nonisolated enum NavalMistDrawing {
    private static let cloudCount = 6
    private static let fringeRadius: CGFloat = 0.24

    static func draw(_ cells: [HexCoordinate], geometry: HexGeometry, viewport: CGSize,
                     opacity: CGFloat, withdrawal: CGFloat, in context: GraphicsContext) {
        guard !cells.isEmpty, opacity > 0 else { return }
        let bounds = CGRect(origin: .zero, size: viewport).insetBy(dx: -geometry.size * 3, dy: -geometry.size * 3)
        let visible = cells.filter { TileDrawing.hexPath(for: $0, geometry: geometry).boundingRect.intersects(bounds) }
        let cover = visible.reduce(into: Path()) { $0.addPath(TileDrawing.hexPath(for: $1, geometry: geometry)) }
        context.drawLayer { layer in
            layer.opacity = opacity
            drawFringe(visible, hidden: Set(cells), geometry: geometry, withdrawal: withdrawal, in: layer)
            layer.clip(to: cover)
            layer.fill(cover, with: .color(NavalArtwork.mist))
            for cell in visible { drawBanks(cell, geometry: geometry, withdrawal: withdrawal, in: layer) }
        }
    }

    private static func drawBanks(_ cell: HexCoordinate, geometry: HexGeometry, withdrawal: CGFloat, in context: GraphicsContext) {
        let center = geometry.center(of: cell)
        for index in 0..<cloudCount {
            let noise = NavalVisualNoise.sample(cell, index: index)
            let spread = geometry.size * (0.60 + noise * 1.15)
            var bank = context
            bank.translateBy(x: center.x + geometry.size * (noise - 0.5 + withdrawal * 0.85),
                             y: center.y + geometry.size * (NavalVisualNoise.sample(cell, index: index, channel: 1) - 0.5 - withdrawal * 0.24))
            bank.scaleBy(x: 1, y: 0.28 + NavalVisualNoise.sample(cell, index: index, channel: 2) * 0.42)
            let cloud = Path(ellipseIn: CGRect(x: -spread, y: -spread, width: spread * 2, height: spread * 2))
            let shade = index.isMultiple(of: 3) ? NavalArtwork.mistShadow : NavalArtwork.mistLight
            bank.fill(cloud, with: .radialGradient(
                Gradient(stops: [.init(color: shade.opacity(index.isMultiple(of: 3) ? 0.42 : 0.72), location: 0),
                                 .init(color: shade.opacity(0.22), location: 0.52),
                                 .init(color: shade.opacity(0), location: 1)]),
                center: .zero, startRadius: 0, endRadius: spread))
        }
    }

    private static func drawFringe(_ visible: [HexCoordinate], hidden: Set<HexCoordinate>,
                                   geometry: HexGeometry, withdrawal: CGFloat, in context: GraphicsContext) {
        for cell in visible {
            for direction in 0..<6 where !hidden.contains(cell.neighbor(direction)) {
                let first = (6 - direction) % 6
                let a = geometry.corner(of: cell, index: first)
                let b = geometry.corner(of: cell, index: (first + 1) % 6)
                for sample in 0..<5 {
                    let fraction = CGFloat(sample) / 4
                    let noise = NavalVisualNoise.sample(cell, index: sample + direction * 5)
                    let radius = geometry.size * fringeRadius * (0.7 + noise * 0.8) * (1 - withdrawal * 0.35)
                    let point = CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
                    let cloud = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius * 0.8,
                                                       width: radius * 2, height: radius * 1.6))
                    context.fill(cloud, with: .radialGradient(
                        Gradient(colors: [NavalArtwork.mist.opacity(0.88), NavalArtwork.mistLight.opacity(0)]),
                        center: point, startRadius: 0, endRadius: radius))
                }
            }
        }
    }
}
