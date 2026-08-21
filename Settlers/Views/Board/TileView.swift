import SwiftUI
import CatanEngine

/// Canvas-drawing helpers for `BoardView`: hex tile fills, number tokens,
/// the robber, and port icons. Kept out of `BoardView` itself for
/// readability; these operate directly on a `GraphicsContext` rather than
/// being SwiftUI `View`s, since `Canvas` draws imperatively.
enum TileDrawing {
    /// `scale` shrinks the hex toward its own center (1.0 = full size, the
    /// tap-target/vertex-alignment size every other caller - highlighting,
    /// `BoardView`'s vertex/edge math - still uses). Only `drawTile` itself
    /// passes a smaller scale, for the actual resource-colored fill.
    static func hexPath(for tile: HexCoordinate, geometry: HexGeometry, scale: CGFloat = 1.0) -> Path {
        var path = Path()
        let center = geometry.center(of: tile)
        let corners = (0..<6).map { index -> CGPoint in
            let corner = geometry.corner(of: tile, index: index)
            guard scale != 1.0 else { return corner }
            return CGPoint(x: center.x + (corner.x - center.x) * scale, y: center.y + (corner.y - center.y) * scale)
        }
        path.move(to: corners[0])
        for corner in corners.dropFirst() {
            path.addLine(to: corner)
        }
        path.closeSubpath()
        return path
    }

    /// Each tile draws as two layers - a full-size hex filled with the
    /// board's "frame" color (`CatanTheme.desert`, the same sand/manila
    /// tone the desert tile itself uses), then a smaller resource-textured
    /// hex centered on top - so a visible manila gap shows between every
    /// pair of tiles, like the physical board's beige grout between
    /// pieces, instead of tiles butting directly against each other.
    /// Number tokens, roads, settlements, and tap targets all still align
    /// to the full-size hex geometry - only this visual fill shrinks.
    ///
    /// The frame layer is a plain color fill, now with a very thin gray
    /// outline (subtle enough not to read as a stray grid line in the
    /// manila gap - kept faint on purpose). The resource layer is the
    /// painted tile texture from Assets.xcassets
    /// (`CatanTheme.textureImageName(for:)`), clipped to the hex path and
    /// drawn to fill its bounding box, then gets its own thin gray outline
    /// too - see `design-references/STATUS.md` for where these textures
    /// came from.
    static func drawTile(_ tile: Tile, geometry: HexGeometry, in context: GraphicsContext) {
        let framePath = hexPath(for: tile.coordinate, geometry: geometry)
        context.fill(framePath, with: .color(CatanTheme.desert))
        context.stroke(framePath, with: .color(.black.opacity(0.18)), lineWidth: 1)

        let fillPath = hexPath(for: tile.coordinate, geometry: geometry, scale: 0.86)
        let resolvedTexture = context.resolve(Image(CatanTheme.textureImageName(for: tile.kind)))
        context.drawLayer { layerContext in
            layerContext.clip(to: fillPath)
            layerContext.draw(resolvedTexture, in: fillPath.boundingRect)
        }
        context.stroke(fillPath, with: .color(.black.opacity(0.22)), lineWidth: 1)

        if let number = tile.numberToken {
            drawNumberToken(number, at: geometry.center(of: tile.coordinate), size: geometry.size, in: context)
        }
    }

    private static func drawNumberToken(_ number: Int, at point: CGPoint, size: CGFloat, in context: GraphicsContext) {
        let radius = size * 0.32
        let circle = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))

        context.drawLayer { layerContext in
            layerContext.addFilter(.shadow(color: .black.opacity(0.5), radius: radius * 0.18, x: 0, y: radius * 0.14))
            layerContext.fill(circle, with: .color(CatanTheme.numberTokenBackground))
        }
        context.stroke(circle, with: .color(CatanTheme.numberTokenEdge), lineWidth: 1.25)

        let isHot = number == 6 || number == 8
        let text = Text("\(number)")
            .font(.system(size: radius * 1.15, weight: .bold, design: .serif))
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
                .font(.system(size: radius * 0.85, weight: .bold, design: .serif))
                .foregroundColor(.white)
            context.draw(context.resolve(text), at: center, anchor: .center)
        }
    }

    /// Draws a small port icon pushed outward from `boardCenter`, along the
    /// midpoint of the port's two shoreline vertices, so it reads as sitting
    /// just offshore rather than on top of the board. Two "dock" lines run
    /// from the badge back to each of those two shoreline vertices,
    /// tracing the actual edge the port trades through - previously the
    /// badge just floated near the coast with nothing pinning it to a
    /// specific edge, ambiguous whenever two ports sat close together.
    static func drawPort(_ port: CatanEngine.Port, geometry: HexGeometry, board: Board, boardCenter: CGPoint, in context: GraphicsContext) {
        let a = geometry.vertexPosition(port.vertexA, board: board)
        let b = geometry.vertexPosition(port.vertexB, board: board)
        let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)

        var direction = CGVector(dx: midpoint.x - boardCenter.x, dy: midpoint.y - boardCenter.y)
        let length = max(sqrt(direction.dx * direction.dx + direction.dy * direction.dy), 0.001)
        direction = CGVector(dx: direction.dx / length, dy: direction.dy / length)
        let iconPoint = CGPoint(x: midpoint.x + direction.dx * geometry.size * 0.4, y: midpoint.y + direction.dy * geometry.size * 0.4)

        var dockPath = Path()
        dockPath.move(to: a)
        dockPath.addLine(to: iconPoint)
        dockPath.move(to: b)
        dockPath.addLine(to: iconPoint)
        context.stroke(dockPath, with: .color(CatanTheme.portIcon.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        let radius = geometry.size * 0.24
        // The painted gold-ring badge frame sits behind the actual
        // functional circle (still colored by port kind, still stroked) -
        // decorative only, so the resource-color coding that circle
        // carries (which port trades which resource, at a glance) stays
        // exactly as legible as before. See design-references/STATUS.md.
        let frameRadius = radius * 1.35
        let resolvedFrame = context.resolve(Image("port-frame"))
        context.draw(resolvedFrame, in: CGRect(x: iconPoint.x - frameRadius, y: iconPoint.y - frameRadius, width: frameRadius * 2, height: frameRadius * 2))

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
        context.stroke(circle, with: .color(.white), lineWidth: 2)
        let text = Text(label)
            .font(.system(size: radius * 0.75, weight: .bold, design: .serif))
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
    /// Smaller than `touchDiameter` on purpose - the yellow glow ring
    /// (shown for every legal placement, most noticeably setup's two
    /// rounds of settlements) read as oversized at the full 32pt tap-target
    /// size. The invisible tap circle underneath stays at the full size so
    /// the actual hit target doesn't shrink, only what's visibly drawn.
    private let highlightDiameter: CGFloat = 22

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .strokeBorder(Color.yellow, lineWidth: 3)
                    .background(Circle().fill(Color.yellow.opacity(0.35)))
                    .frame(width: highlightDiameter, height: highlightDiameter)
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

/// Rectangle for a road, drawn along an edge's axis via `rotationEffect` in
/// the caller. Only lightly rounded (not the full-capsule pill this used to
/// be) so that consecutive roads sharing a vertex - now drawn edge-to-edge,
/// see `BoardView.roadViews` - butt up cleanly into one continuous line
/// instead of each segment necking down to a rounded point at the joint.
struct RoadShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: rect.height * 0.18)
    }
}
