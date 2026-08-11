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

    /// Draws the robber over `tileCoordinate`. `number` is the tile's own
    /// number token (if any), redrawn in white on top of the robber icon so
    /// it stays legible - previously the robber's opaque fill fully covered
    /// the number token `drawTile` already painted underneath it.
    static func drawRobber(at tileCoordinate: HexCoordinate, number: Int?, geometry: HexGeometry, in context: GraphicsContext) {
        let center = geometry.center(of: tileCoordinate)
        let radius = geometry.size * 0.28
        let path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(path, with: .color(CatanTheme.robber))
        context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 1)

        if let number {
            let text = Text("\(number)")
                .font(.system(size: radius * 0.85, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            context.draw(context.resolve(text), at: center, anchor: .center)
        }
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
/// building settlements/cities. During placement mode (`isEnabled: false`),
/// non-highlighted targets ignore taps entirely; a highlighted target draws a
/// glowing ring so the legal placements read as tappable.
struct VertexTapTarget: View {
    let position: CGPoint
    var isHighlighted: Bool = false
    var isEnabled: Bool = true
    let onTap: () -> Void

    private let touchDiameter: CGFloat = 32

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .background(Circle().fill(Color.yellow.opacity(0.35)))
                    .frame(width: touchDiameter, height: touchDiameter)
            }
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: touchDiameter, height: touchDiameter)
        }
        .position(position)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onTapGesture(perform: onTap)
    }
}

/// An invisible tap target capsule along a board edge, for building roads.
/// See `VertexTapTarget` for the highlight/enabled semantics.
struct EdgeTapTarget: View {
    let start: CGPoint
    let end: CGPoint
    var isHighlighted: Bool = false
    var isEnabled: Bool = true
    let onTap: () -> Void

    private let touchWidth: CGFloat = 20

    var body: some View {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        ZStack {
            if isHighlighted {
                Capsule()
                    .fill(Color.yellow.opacity(0.55))
                    .frame(width: length, height: touchWidth * 0.6)
            }
            Capsule()
                .fill(Color.white.opacity(0.001))
                .frame(width: length, height: touchWidth)
        }
        .rotationEffect(.radians(angle))
        .position(midpoint)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onTapGesture(perform: onTap)
    }
}

/// Rounded rectangle for a road, drawn along an edge's axis via
/// `rotationEffect` in the caller.
struct RoadShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height / 2)
    }
}
