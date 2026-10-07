import SwiftUI
import CatanEngine

/// A shared ocean wash, varied hand-painted ripples and known-coast foam.
/// Coast detection accepts only the redacted board: no concealed island can
/// influence water color, shore marks or the shape of fog.
enum NavalSeaDrawing {
    private static let deep = Color(red: 0.063, green: 0.235, blue: 0.337)
    private static let blue = Color(red: 0.110, green: 0.353, blue: 0.451)
    private static let teal = Color(red: 0.212, green: 0.482, blue: 0.529)
    private static let glint = Color(red: 0.612, green: 0.769, blue: 0.737)
    private static let detailThreshold: CGFloat = 13
    private static let detailTransitionSpan: CGFloat = 8
    private static let minimumRippleCount = 6
    private static let densityVariation = 3

    static func draw(_ tile: Tile, geometry: HexGeometry, visibleBoard: Board,
                     in context: GraphicsContext) {
        let path = TileDrawing.hexPath(for: tile.coordinate, geometry: geometry)
        guard path.boundingRect.intersects(context.clipBoundingRect) else { return }
        context.fill(path, with: .linearGradient(
            Gradient(colors: [deep, blue, teal, deep]),
            startPoint: geometry.center(of: HexCoordinate(q: -7, r: -3)),
            endPoint: geometry.center(of: HexCoordinate(q: 5, r: 7))))
        guard tile.kind == .sea else { return }
        context.drawLayer { layer in
            layer.clip(to: path)
            drawWash(tile.coordinate, geometry: geometry, in: layer)
            if geometry.size >= detailThreshold { drawRipples(tile.coordinate, geometry: geometry, in: layer) }
            drawCoast(tile.coordinate, geometry: geometry, visibleBoard: visibleBoard, in: layer)
        }
        context.stroke(path, with: .color(glint.opacity(0.10)), lineWidth: max(0.5, geometry.size * 0.01))
    }

    private static func drawWash(_ cell: HexCoordinate, geometry: HexGeometry, in context: GraphicsContext) {
        let center = geometry.center(of: cell)
        let radius = geometry.size * 1.4
        let color = NavalVisualNoise.sample(cell, index: 0) > 0.5 ? teal : deep
        let stain = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.3,
                                           width: radius * 2, height: radius * 0.6))
        context.fill(stain, with: .radialGradient(
            Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
            center: center, startRadius: 0, endRadius: radius))
    }

    private static func drawRipples(_ cell: HexCoordinate, geometry: HexGeometry, in context: GraphicsContext) {
        let center = geometry.center(of: cell)
        let variation = min(densityVariation, Int(NavalVisualNoise.sample(cell, index: 12) * 4))
        let count = minimumRippleCount + variation
        let detailOpacity = min(1, max(0, (geometry.size - detailThreshold) / detailTransitionSpan))
        for index in 0..<count {
            let noise = NavalVisualNoise.sample(cell, index: index)
            let x = center.x + (NavalVisualNoise.sample(cell, index: index, channel: 1) - 0.5) * geometry.size
            let jitter = (NavalVisualNoise.sample(cell, index: index, channel: 2) - 0.5) * 0.22
            let y = center.y + (CGFloat(index) / CGFloat(count - 1) - 0.5 + jitter) * geometry.size * 1.35
            let length = geometry.size * (0.20 + noise * 0.65)
            var wave = Path()
            wave.move(to: CGPoint(x: x - length / 2, y: y))
            wave.addCurve(to: CGPoint(x: x + length / 2, y: y - geometry.size * 0.02),
                          control1: CGPoint(x: x - length * 0.15, y: y + geometry.size * 0.06),
                          control2: CGPoint(x: x + length * 0.15, y: y + geometry.size * 0.05))
            context.stroke(wave, with: .color(glint.opacity((0.13 + noise * 0.19) * detailOpacity)),
                           style: StrokeStyle(lineWidth: max(0.6, geometry.size * (0.009 + noise * 0.012)), lineCap: .round))
        }
    }

    private static func drawCoast(_ cell: HexCoordinate, geometry: HexGeometry, visibleBoard: Board,
                                  in context: GraphicsContext) {
        for direction in 0..<6 {
            let neighbor = cell.neighbor(direction)
            guard visibleBoard.tiles.contains(where: { $0.coordinate == neighbor && $0.kind.isLand }) else { continue }
            let first = (6 - direction) % 6
            let center = geometry.center(of: cell)
            let a = geometry.corner(of: cell, index: first)
            let b = geometry.corner(of: cell, index: (first + 1) % 6)
            let start = CGPoint(x: a.x * 0.94 + center.x * 0.06, y: a.y * 0.94 + center.y * 0.06)
            let end = CGPoint(x: b.x * 0.94 + center.x * 0.06, y: b.y * 0.94 + center.y * 0.06)
            var shore = Path()
            shore.move(to: start)
            shore.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) * 0.5 * 0.96 + center.x * 0.04,
                                                        y: (start.y + end.y) * 0.5 * 0.96 + center.y * 0.04))
            context.stroke(shore, with: .color(teal.opacity(0.65)), lineWidth: geometry.size * 0.12)
            context.stroke(shore, with: .color(glint.opacity(0.65)),
                           style: StrokeStyle(lineWidth: max(0.8, geometry.size * 0.028), lineCap: .round, dash: [4, 3, 8, 2]))
        }
    }
}
