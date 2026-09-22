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

    /// How far out to push a port badge, in hex-size units, measured along the
    /// edge's outward normal.
    ///
    /// Sized so the badge clears a vertex's placement ring. The badge's frame
    /// radius is `size * 0.324` and a ring is 11pt in radius, so with the badge
    /// pushed `d` out from an edge midpoint, its distance to either of that
    /// edge's vertices is `hypot(size/2, d)` - the edge is `size` long on a
    /// pointy-top grid.
    ///
    /// This is also, by construction, the single biggest cost in
    /// `BoardView.fittedGeometry`'s reservation: since `fittedGeometry` fits
    /// the hex grid to whatever space is left after reserving this offset
    /// (plus the frame radius) on every port-bearing edge, a bigger offset
    /// directly shrinks the board. 0.55 (kept a full hex-width of shoreline
    /// clearance) made the board visibly smaller than the hexes alone would
    /// need, and read as ports floating apart from the coast rather than
    /// docked to it. 0.44 is the smallest value (in 0.01 steps)
    /// `BoardFitTests.portBadgesDoNotCollideWithPlacementRings` still accepts
    /// across the tested boards - the badge still clears the ring, just with
    /// less daylight to spare, and the board scales up to fill the freed
    /// space.
    static let portOffset: CGFloat = 0.44

    /// Radius of a vertex's placement ring - half `VertexTapTarget`'s
    /// `highlightDiameter` of 22.
    ///
    /// `BoardView.fittedGeometry` reserves this much around the board, since
    /// the ring is a fixed point size and does not shrink with the hex.
    static let vertexRingRadius: CGFloat = 11

    /// Draws the committed robber over `tileCoordinate`, and darkens the tile
    /// it is sitting on.
    ///
    /// ## Why the tile is darkened rather than just marked
    /// The robber used to be a plain near-black disc with a thin white ring,
    /// and on a fully painted board that reads as a hole in the artwork rather
    /// than as a piece - it was reported as "I don't see the robber". A marker
    /// also only says *where* it is, when the thing a player needs to know is
    /// *what it does*: that hex produces nothing while the robber sits there.
    ///
    /// So the tile gets a scrim and the marker gets a gold rim matching the
    /// board's other chrome. The scrim carries the meaning at a glance and the
    /// marker carries the position; the number token is still redrawn on top so
    /// the hex stays identifiable.
    static func drawRobber(at tileCoordinate: HexCoordinate, number: Int?, geometry: HexGeometry, in context: GraphicsContext) {
        drawRobberScrim(at: tileCoordinate, opacity: 0.45, geometry: geometry, in: context)
        drawRobberDisc(at: tileCoordinate, opacity: 1, isProvisional: false, geometry: geometry, in: context)
        drawRobberNumber(number, at: tileCoordinate, geometry: geometry, in: context)
    }

    /// Replaces the committed robber with a hollow departure marker while the
    /// physical piece sits in the drag cradle. The tile remains darkened because
    /// it is still canonically blocked until confirmation succeeds.
    static func drawRobberOrigin(
        at tileCoordinate: HexCoordinate,
        number: Int?,
        geometry: HexGeometry,
        in context: GraphicsContext
    ) {
        drawRobberScrim(at: tileCoordinate, opacity: 0.34, geometry: geometry, in: context)
        let center = geometry.center(of: tileCoordinate)
        let radius = geometry.size * 0.34
        let disc = circle(center: center, radius: radius)
        context.stroke(
            disc,
            with: .color(CatanTheme.cityPennantGold.opacity(0.96)),
            style: StrokeStyle(lineWidth: geometry.size * 0.07, dash: [5, 3])
        )
        context.stroke(
            circle(center: center, radius: radius * 0.58),
            with: .color(CatanTheme.robber.opacity(0.92)),
            lineWidth: geometry.size * 0.06
        )
        drawRobberNumber(number, at: tileCoordinate, geometry: geometry, in: context)
    }

    /// Draws a translucent robber at a proposed destination. The dashed gold
    /// rim is the same provisional cue used by building previews; no canonical
    /// board value has changed when this is visible.
    static func drawRobberPreview(
        at tileCoordinate: HexCoordinate,
        number: Int?,
        geometry: HexGeometry,
        in context: GraphicsContext
    ) {
        drawRobberScrim(at: tileCoordinate, opacity: 0.27, geometry: geometry, in: context)
        drawRobberDisc(at: tileCoordinate, opacity: 0.68, isProvisional: true, geometry: geometry, in: context)
        drawRobberNumber(number, at: tileCoordinate, geometry: geometry, in: context)
    }

    private static func drawRobberScrim(
        at tileCoordinate: HexCoordinate,
        opacity: Double,
        geometry: HexGeometry,
        in context: GraphicsContext
    ) {
        let scrim = hexPath(for: tileCoordinate, geometry: geometry, scale: 0.97)
        context.fill(scrim, with: .color(.black.opacity(opacity)))
    }

    private static func drawRobberDisc(
        at tileCoordinate: HexCoordinate,
        opacity: Double,
        isProvisional: Bool,
        geometry: HexGeometry,
        in context: GraphicsContext
    ) {
        let center = geometry.center(of: tileCoordinate)
        let disc = circle(center: center, radius: geometry.size * 0.32)
        context.fill(disc, with: .color(CatanTheme.robber.opacity(opacity)))
        context.stroke(
            disc,
            with: .color(CatanTheme.cityPennantGold.opacity(isProvisional ? 0.82 : 1)),
            style: StrokeStyle(
                lineWidth: geometry.size * 0.05,
                dash: isProvisional ? [5, 3] : []
            )
        )
    }

    private static func drawRobberNumber(
        _ number: Int?,
        at tileCoordinate: HexCoordinate,
        geometry: HexGeometry,
        in context: GraphicsContext
    ) {
        guard let number else { return }
        let text = Text("\(number)")
            .font(.system(size: geometry.size * 0.32 * 1.15, weight: .bold, design: .serif))
            .foregroundColor(.white)
        context.draw(context.resolve(text), at: geometry.center(of: tileCoordinate), anchor: .center)
    }

    private static func circle(center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    /// Where a port's badge is drawn: out from the midpoint of its two
    /// shoreline vertices, along that edge's OUTWARD NORMAL.
    ///
    /// The normal, not the direction from the board's centre. Those two only
    /// coincide for an edge that happens to face radially; everywhere else the
    /// centre-to-midpoint ray meets the edge at an angle, so the badge slid
    /// sideways along the shore and ended up nearer one of its two vertices
    /// than the other. That is what made some ports look misplaced, and pulled
    /// badges into the vertex placement rings during setup, when every vertex
    /// is ringed at once.
    ///
    /// Shared with `BoardView.fittedGeometry`, which has to know how far
    /// outside the tiles anything is drawn in order to leave room for it. Two
    /// copies of this would let the board be scaled to fit a layout the
    /// renderer no longer uses.
    static func portIconPoint(a: CGPoint, b: CGPoint, boardCenter: CGPoint, size: CGFloat) -> CGPoint {
        let midpoint = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let edge = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let edgeLength = max(sqrt(edge.dx * edge.dx + edge.dy * edge.dy), 0.001)
        // Either perpendicular would do; take the one pointing away from the
        // board, since a port sits offshore.
        var outward = CGVector(dx: -edge.dy / edgeLength, dy: edge.dx / edgeLength)
        let awayFromBoard = CGVector(dx: midpoint.x - boardCenter.x, dy: midpoint.y - boardCenter.y)
        if outward.dx * awayFromBoard.dx + outward.dy * awayFromBoard.dy < 0 {
            outward = CGVector(dx: -outward.dx, dy: -outward.dy)
        }
        return CGPoint(x: midpoint.x + outward.dx * size * portOffset,
                       y: midpoint.y + outward.dy * size * portOffset)
    }

    /// Radius of the painted badge frame, in hex-size units - the outermost
    /// thing drawn for a port, and therefore what the board must leave room
    /// for.
    static let portFrameRadiusFactor: CGFloat = 0.24 * 1.35

    /// A small visible gap, scaled with the badges rather than the viewport.
    static let portBadgeGapFactor: CGFloat = 0.08

    /// Port centers in board order, shared by drawing, fitting and inspection.
    /// Vast has two neighboring edge normals that converge offshore. Separate
    /// only overlapping badges equally along their connecting line, leaving
    /// all other ports and the engine's shoreline vertices untouched. Board
    /// units keep this a pure, zoom-independent layout with no remembered fit.
    static func portIconPoints(board: Board, geometry: HexGeometry, boardCenter: CGPoint) -> [CGPoint] {
        var points = board.ports.map { port in
            portIconPoint(a: geometry.vertexPosition(port.vertexA, board: board),
                          b: geometry.vertexPosition(port.vertexB, board: board),
                          boardCenter: boardCenter, size: geometry.size)
        }
        let clearance = geometry.size * (2 * portFrameRadiusFactor + portBadgeGapFactor)
        let vertices = board.onBoardVertices.sorted().map { geometry.vertexPosition($0, board: board) }
        // Stable pair order; further passes handle a displacement reaching a
        // neighbor. The shipped boards need only one pair adjustment.
        for _ in points.indices {
            var changed = false
            for first in points.indices {
                for second in points.indices where second > first {
                    if separatePortPair(first, second, points: &points, clearance: clearance) {
                        points[first] = clearPortFromRings(points[first], vertices: vertices, center: boardCenter, size: geometry.size)
                        points[second] = clearPortFromRings(points[second], vertices: vertices, center: boardCenter, size: geometry.size)
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return points
    }

    private static func separatePortPair(_ first: Int, _ second: Int,
                                         points: inout [CGPoint], clearance: CGFloat) -> Bool {
        let delta = CGVector(dx: points[second].x - points[first].x, dy: points[second].y - points[first].y)
        let distance = hypot(delta.dx, delta.dy)
        guard distance < clearance else { return false }
        let shift = (clearance - distance) / 2
        let offset = CGVector(dx: distance > 0 ? delta.dx / distance * shift : shift,
                              dy: distance > 0 ? delta.dy / distance * shift : 0)
        points[first].x -= offset.dx
        points[first].y -= offset.dy
        points[second].x += offset.dx
        points[second].y += offset.dy
        return true
    }

    /// Move a displaced badge outward just far enough to clear the vertex
    /// rings. Solve the ray/circle exits directly rather than stepping by a
    /// guessed pixel offset. The unit-scale ring is its maximum proportional
    /// size, keeping fit and rendering identical even when zoom caps the ring.
    private static func clearPortFromRings(_ point: CGPoint, vertices: [CGPoint], center: CGPoint, size: CGFloat) -> CGPoint {
        let radius = size * (portFrameRadiusFactor + VertexTapTarget.highlightDiameter(spacing: 1) / 2
            + portBadgeGapFactor / 2)
        let length = hypot(point.x - center.x, point.y - center.y)
        precondition(length > 0, "an offshore port must be outside the board center")
        let direction = CGVector(dx: (point.x - center.x) / length, dy: (point.y - center.y) / length)
        var shift: CGFloat = 0
        for vertex in vertices {
            let delta = CGVector(dx: vertex.x - point.x, dy: vertex.y - point.y)
            let along = delta.dx * direction.dx + delta.dy * direction.dy
            let across = delta.dx * direction.dy - delta.dy * direction.dx
            guard abs(across) < radius else { continue }
            shift = max(shift, along + sqrt(radius * radius - across * across))
        }
        return CGPoint(x: point.x + direction.dx * shift, y: point.y + direction.dy * shift)
    }

    /// Draws a port badge offshore of the edge it trades through, with two
    /// dock lines running back to that edge's two shoreline vertices - so the
    /// badge is pinned to a specific edge rather than floating near the coast,
    /// which was ambiguous wherever two ports sat close together.
    static func drawPort(_ port: CatanEngine.Port, at iconPoint: CGPoint, geometry: HexGeometry, board: Board, in context: GraphicsContext) {
        let a = geometry.vertexPosition(port.vertexA, board: board)
        let b = geometry.vertexPosition(port.vertexB, board: board)

        // The dock lines start right at the shoreline vertices, tracing the
        // real edge the port trades through.
        //
        // They used to start `vertexRingRadius` further out, "so a line never
        // runs underneath the ring it is pointing at" - but `BoardView.body`
        // already draws every `VertexTapTarget` (rings included) in a layer
        // above this `Canvas`, so a ring occludes whatever is under it
        // regardless of where the line starts; the inset bought nothing
        // during placement and, the rest of the time, with no ring drawn at
        // all, it just left a gap between the coast and the dock line -
        // reported as the ports looking detached from the board.
        var dockPath = Path()
        for shorelineVertex in [a, b] {
            dockPath.move(to: shorelineVertex)
            dockPath.addLine(to: iconPoint)
        }
        context.stroke(dockPath, with: .color(CatanTheme.portIcon.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

        let radius = geometry.size * 0.24
        // The painted gold-ring badge frame sits behind the actual functional
        // circle (still coloured by port kind, still stroked) - decorative
        // only, so the resource-colour coding that circle carries stays exactly
        // as legible. See design-references/STATUS.md.
        let frameRadius = geometry.size * portFrameRadiusFactor
        let resolvedFrame = context.resolve(Image("port-frame"))
        context.draw(resolvedFrame, in: CGRect(x: iconPoint.x - frameRadius, y: iconPoint.y - frameRadius,
                                               width: frameRadius * 2, height: frameRadius * 2))

        let circle = Path(ellipseIn: CGRect(x: iconPoint.x - radius, y: iconPoint.y - radius,
                                            width: radius * 2, height: radius * 2))
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
/// building settlements/cities. The board creates controls only for legal
/// targets; a visible ring makes each available placement read as tappable.
struct VertexTapTarget: View {
    let position: CGPoint
    var isHighlighted: Bool = false
    var isEnabled: Bool = true
    var isSelected: Bool = false
    /// Defaults to the Classic ceiling; see `highlightDiameter(spacing:)`.
    var highlightDiameter: CGFloat = VertexTapTarget.maximumHighlightDiameter
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let onTap: () -> Void

    private let touchDiameter: CGFloat = 44

    /// Smaller than `touchDiameter` on purpose - the yellow glow ring
    /// (shown for every legal placement, most noticeably setup's two
    /// rounds of settlements) read as oversized at the full 44pt tap-target
    /// size. The invisible tap circle underneath stays at the full size so
    /// the actual hit target doesn't shrink, only what's visibly drawn.
    ///
    /// This is the diameter on Classic, and it is a *ceiling*, not a
    /// constant - see `highlightDiameter(spacing:)`.
    nonisolated static let maximumHighlightDiameter: CGFloat = 22

    /// Fraction of the gap between neighbouring corners that the ring may
    /// occupy. 22pt over Classic's ~41pt spacing is where this came from, so
    /// Classic renders exactly as it did before.
    nonisolated private static let highlightShareOfSpacing: CGFloat = 0.53

    /// The ring has to shrink with the board, not sit at a fixed 22pt.
    ///
    /// Neighbouring corners are exactly `HexGeometry.size` apart - a regular
    /// hexagon's edge length equals its circumradius - and that distance is
    /// set by how many tiles have to fit the fixed viewport. Classic (radius
    /// 2, 5 hexes across) leaves ~41pt between corners, so a 22pt ring has
    /// ~19pt of clear space around it. Vast (radius 4, 9 hexes across) leaves
    /// ~23pt, so the same 22pt ring nearly touches its neighbours: during the
    /// opening settlement, when every one of the ~150 corners is legal at
    /// once, they merged into chainmail and the board underneath disappeared.
    ///
    /// Scaling with spacing rather than special-casing Vast is what keeps a
    /// third board size from re-introducing this.
    nonisolated static func highlightDiameter(spacing: CGFloat) -> CGFloat {
        min(maximumHighlightDiameter, spacing * highlightShareOfSpacing)
    }

    /// Held at the same fraction of the ring the 3pt/4pt pair was at 22pt, so
    /// a shrunken ring stays a ring instead of closing up into a dot.
    private var highlightLineWidth: CGFloat {
        highlightDiameter * (isSelected ? 4 : 3) / VertexTapTarget.maximumHighlightDiameter
    }

    var body: some View {
        ZStack {
            if isHighlighted {
                Circle()
                    .strokeBorder(CatanTheme.cityPennantGold, lineWidth: highlightLineWidth)
                    .background(Circle().fill(CatanTheme.cityPennantGold.opacity(isSelected ? 0.5 : 0.32)))
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
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(!isEnabled)
    }
}

/// An invisible tap target capsule along a board edge, for building roads.
/// See `VertexTapTarget` for the highlight/enabled semantics.
struct EdgeTapTarget: View {
    let start: CGPoint
    let end: CGPoint
    var isHighlighted: Bool = false
    var isEnabled: Bool = true
    var isSelected: Bool = false
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let onTap: () -> Void

    private let touchWidth: CGFloat = 44
    private let highlightWidth: CGFloat = 12

    var body: some View {
        let length = hypot(end.x - start.x, end.y - start.y)
        // Keep the visual affordance near the middle of the edge. Three
        // full-length capsules converge beneath every settlement and merge
        // into one amorphous blob; shortened guides remain three readable
        // choices while the invisible hit target still spans the whole edge.
        let guideLength = max(length * 0.62, min(length, 20))
        let angle = atan2(end.y - start.y, end.x - start.x)
        let midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)

        ZStack {
            if isHighlighted {
                Capsule()
                    .fill(CatanTheme.chipGold.opacity(isSelected ? 0.96 : 0.82))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.82), lineWidth: 1.5)
                    }
                    .shadow(color: CatanTheme.chipGold.opacity(0.4), radius: 1.5)
                    .frame(width: guideLength, height: highlightWidth)
            }
            Capsule()
                .fill(Color.white.opacity(0.001))
                .frame(width: max(length, 44), height: touchWidth)
        }
        .rotationEffect(.radians(angle))
        .position(midpoint)
        .allowsHitTesting(isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(!isEnabled)
    }
}

/// Semantic tile target used only while choosing a robber destination.
/// Visual highlighting remains in `BoardView`'s Canvas; this transparent
/// circle gives each hex a stable, independently enabled control for assistive
/// technology and tap-driven journey tests.
struct TileTapTarget: View {
    let position: CGPoint
    let diameter: CGFloat
    let isEnabled: Bool
    let isSelected: Bool
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let onTap: () -> Void

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.001))
            .frame(width: diameter, height: diameter)
            .position(position)
            .allowsHitTesting(isEnabled)
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(accessibilityIdentifier)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .disabled(!isEnabled)
    }
}
