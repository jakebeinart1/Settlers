import SwiftUI
import CatanEngine

/// Canvas-drawing helpers for `BoardView`: hex tile fills, number tokens,
/// the robber, and port icons. Kept out of `BoardView` itself for
/// readability; these operate directly on a `GraphicsContext` rather than
/// being SwiftUI `View`s, since `Canvas` draws imperatively.
enum TileDrawing {
    static func hexPath(for tile: HexCoordinate, geometry: HexGeometry) -> Path {
        var path = Path()
        let corners = (0..<6).map { geometry.corner(of: tile, index: $0) }
        path.move(to: corners[0])
        for corner in corners.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()
        return path
    }

    static func drawTile(_ tile: Tile, geometry: HexGeometry, in context: GraphicsContext) {
        let path = hexPath(for: tile.coordinate, geometry: geometry)
        context.fill(path, with: .color(CatanTheme.color(for: tile.kind)))
        context.stroke(path, with: .color(CatanTheme.tileBorder), lineWidth: 1.5)

        if let number = tile.numberToken {
            drawNumberToken(number, at: geometry.center(of: tile.coordinate), size: geometry.size, in: context)
        }
    }

    private static func drawNumberToken(_ number: Int, at point: CGPoint, size: CGFloat, in context: GraphicsContext) {
        let radius = size * 0.32
        let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        context.fill(circle, with: .color(CatanTheme.numberTokenBackground))

        let isHot = number == 6 || number == 8
        let text = Text("\(number)")
            .font(.system(size: radius * 1.15, weight: .bold, design: .rounded))
            .foregroundColor(isHot ? CatanTheme.hotNumber : CatanTheme.coolNumber)
        context.draw(context.resolve(text), at: point, anchor: .center)
    }

    static func drawRobber(at tileCoordinate: HexCoordinate, geometry: HexGeometry, in context: GraphicsContext) {
        let center = geometry.center(of: tileCoordinate)
        let radius = geometry.size * 0.28
        let path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(path, with: .color(CatanTheme.robber))
        context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 1)
    }

    /// Draws a small port icon pushed outward from `boardCenter`, along the
    /// midpoint of the port's two shoreline vertices, so it reads as sitting
    /// just offshore rather than on top of the board.
    static func drawPort(_ port: CatanEngine.Port, geometry: HexGeometry, board: Board, boardCenter: CGPoint, in context: GraphicsContext) {
        let a = geometry.vertexPosition(port.vertexA, board: board)
        let b = geometry.vertexPosition(port.vertexB, board: board)
        let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)

        var direction = CGVector(dx: midpoint.x - boardCenter.x, dy: midpoint.y - boardCenter.y)
        let length = max(sqrt(direction.dx * direction.dx + direction.dy * direction.dy), 0.001)
        direction = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let iconPoint = CGPoint(x: midpoint.x + direction.dx * geometry.size * 0.45, y: midpoint.y + direction.dy * geometry.size * 0.45)

        let radius = geometry.size * 0.22
        let circle = Path(ellipseIn: CGRect(x: iconPoint.x - radius, y: iconPoint.y - radius, width: radius * 2, height: radius * 2))
        let fillColor: Color
        let label: String
        switch port.kind {
        case .generic:
            fillColor = .gray
            label = "3:1"
        case .resource(let resource):
            fillColor = CatanTheme.color(for: resource)
            label = "2:1"
        }
        context.fill(circle, with: .color(fillColor))
        context.stroke(circle, with: .color(.white), lineWidth: 1.5)
        let text = Text(label)
            .font(.system(size: radius * 0.75, weight: .bold))
            .foregroundColor(.white)
        context.draw(context.resolve(text), at: iconPoint, anchor: .center)
    }
}

/// An invisible, generously-sized tap target over a board vertex, for
/// building settlements/cities.
struct VertexTapTarget: View {
    let position: CGPoint
    let onTap: () -> Void

    private let touchDiameter: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.001))
            .frame(width: touchDiameter, height: touchDiameter)
            .position(position)
            .onTapGesture(perform: onTap)
    }
}

/// An invisible tap target capsule along a board edge, for building roads.
struct EdgeTapTarget: View {
    let start: CGPoint
    let end: CGPoint
    let onTap: () -> Void

    private let touchWidth: CGFloat = 20

    var body: some View {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        Capsule()
            .fill(Color.white.opacity(0.001))
            .frame(width: length, height: touchWidth)
            .rotationEffect(.radians(angle))
            .position(midpoint)
            .onTapGesture(perform: onTap)
    }
}

/// Triangle-roof "house" shape for a settlement.
struct SettlementShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let roofHeight = rect.height * 0.5
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + roofHeight))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + roofHeight))
        path.closeSubpath()
        return path
    }
}

/// Larger house-with-annex shape for a city, so it reads as visibly bigger
/// and more elaborate than a settlement.
struct CityShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let roofHeight = rect.height * 0.4
        let annexWidth = rect.width * 0.45

        // Main house.
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + roofHeight))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + annexWidth, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + annexWidth, y: rect.minY + roofHeight))
        path.closeSubpath()

        // Lower annex block to the left.
        path.addRect(CGRect(
            x: rect.minX,
            y: rect.minY + roofHeight + (rect.maxY - (rect.minY + roofHeight)) * 0.35,
            width: annexWidth,
            height: (rect.maxY - (rect.minY + roofHeight)) * 0.65
        ))
        return path
    }
}

/// Rounded rectangle for a road, drawn along an edge's axis via
/// `rotationEffect` in the caller.
struct RoadShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height / 2)
    }
}
