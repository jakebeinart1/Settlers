import SwiftUI

/// Corner treatment used throughout the reference art's painted-plaque
/// chrome: the frame doesn't meet at a plain round/mitered corner - the
/// border (and the fill it traces) detour through a small single-step notch
/// right at each corner, as part of the same continuous outline. This
/// reshapes the actual boundary `Shape` used for both the fill clip and the
/// border strokes, rather than overlaying a separate decoration on top of a
/// plain `RoundedRectangle` - an earlier version of this file did the
/// latter (see git history) and it read as disconnected clutter rather than
/// part of the frame, since two lines sharing one vertex can only ever look
/// like a bracket sitting *inside* the corner, never like the border itself
/// changing shape.
///
/// Every vertex (the notch's own corners, and the two points where it meets
/// the straight edges) gets the same very slight rounding rather than a
/// sharp point - Jake asked for every corner in the app, buttons included,
/// to read as very softly rounded rather than knife-edged.
struct FrameCornerRect: Shape, InsettableShape {
    var cornerRadius: CGFloat
    /// Scales the notch step size relative to the buttons' own size (1.0) -
    /// the dice/bank chips and player cards want a noticeably smaller notch
    /// than the bottom action buttons, not just the same notch on a
    /// differently-sized shape.
    var notchScale: CGFloat = 1.0
    /// Accumulated inset from `.strokeBorder`/`.inset(by:)` - lets this
    /// shape stand in for `RoundedRectangle` in the same sandwiched
    /// hairline/gold/hairline (or hairline/player-color/hairline) border
    /// stack the plain-rect version used, each ring insetting a little
    /// further than the last.
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat, notchScale: CGFloat = 1.0) {
        self.cornerRadius = cornerRadius
        self.notchScale = notchScale
    }

    func inset(by amount: CGFloat) -> FrameCornerRect {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    /// Size of the one notch step, proportional to the corner radius (and
    /// `notchScale`) - deliberately independent of `insetAmount`. Every ring
    /// of a border sandwich (outer hairline, gold, inner hairline) uses this
    /// exact same `s`, and each ring's rect is a plain uniform inset of the
    /// one before it - so every ring's notch is the *same shape*, just
    /// translated by `(insetAmount, insetAmount)`. That's what keeps the gap
    /// between rings a constant width all the way around, including through
    /// the notch: shrinking `s` along with the inset (an earlier version of
    /// this did that) made each ring trace a differently-sized notch, so the
    /// rings converged and diverged near every corner instead of staying
    /// parallel.
    private var s: CGFloat { max(1.5, cornerRadius * 0.45 * notchScale) }

    /// Every vertex - the notch's own two inner corners and the two points
    /// where it meets the straight edges - gets pulled into this same very
    /// small radius instead of a sharp point: a "very very slight round",
    /// not a second bevel that competes with the notch itself. Proportional
    /// to `s`, not a fixed constant - a fixed 1.25pt was tuned against the
    /// buttons' own (larger) notch and looked right there, but applied to
    /// the dice/bank/card notch (much smaller once `notchScale` shrinks it)
    /// it consumed more than half the notch's own size, rounding it away
    /// into what read as a plain corner with no notch at all instead of a
    /// smaller notch - capped at that same 1.25pt so the buttons' own look
    /// is unchanged.
    private var vertexRounding: CGFloat { min(1.25, s * 0.3) }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let s = s
        guard rect.width > s * 4, rect.height > s * 4 else {
            return Path(roundedRect: rect, cornerRadius: max(0, cornerRadius - insetAmount))
        }

        let vertices = Corner.allCases.flatMap { detour(for: $0, in: rect, s: s) }
        return roundedPolygon(vertices, radius: vertexRounding)
    }

    /// Builds a closed path around `vertices` with every corner replaced by
    /// a short quadratic curve through the original vertex point instead of
    /// a sharp line join - the standard "rounded polygon" construction: pull
    /// back `radius` along each incident edge and bow a curve between those
    /// two pulled-back points, using the real vertex as the curve's control
    /// point. Works for any simple polygon, so the same helper rounds both
    /// the notch's own tight corners and the shallower angle where a notch
    /// meets a long straight edge.
    private func roundedPolygon(_ vertices: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        let n = vertices.count
        guard n >= 3 else { return path }

        func along(_ a: CGPoint, _ b: CGPoint, distance: CGFloat) -> CGPoint {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { return a }
            let t = min(distance, length / 2) / length
            return CGPoint(x: a.x + dx * t, y: a.y + dy * t)
        }

        path.move(to: along(vertices[0], vertices[n - 1], distance: radius))
        for i in 0..<n {
            let curr = vertices[i]
            let next = vertices[(i + 1) % n]
            let approach = along(next, curr, distance: radius)
            path.addQuadCurve(to: approach, control: curr)
            path.addLine(to: along(curr, next, distance: radius))
        }
        path.closeSubpath()
        return path
    }

    private enum Corner: CaseIterable {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    /// One corner's full detour: from a point on the incoming edge, `s` from
    /// the true corner, through a single right-angle step, to a point on the
    /// outgoing edge the same distance out. `inDir`/`outDir` are the unit
    /// directions from the true corner point *into* the incoming/outgoing
    /// edges - the whole detour is built from just these two vectors so all
    /// 4 corners share one formula instead of 4 hand-copied point lists
    /// (which is exactly what let an earlier version's path-stitching bug
    /// hide undetected in 3 of the 4 corners).
    private func detour(for corner: Corner, in rect: CGRect, s: CGFloat) -> [CGPoint] {
        let apex: CGPoint
        let inDir: CGPoint
        let outDir: CGPoint
        switch corner {
        case .topLeft:
            apex = CGPoint(x: rect.minX, y: rect.minY)
            inDir = CGPoint(x: 0, y: 1)
            outDir = CGPoint(x: 1, y: 0)
        case .topRight:
            apex = CGPoint(x: rect.maxX, y: rect.minY)
            inDir = CGPoint(x: -1, y: 0)
            outDir = CGPoint(x: 0, y: 1)
        case .bottomRight:
            apex = CGPoint(x: rect.maxX, y: rect.maxY)
            inDir = CGPoint(x: 0, y: -1)
            outDir = CGPoint(x: -1, y: 0)
        case .bottomLeft:
            apex = CGPoint(x: rect.minX, y: rect.maxY)
            inDir = CGPoint(x: 1, y: 0)
            outDir = CGPoint(x: 0, y: -1)
        }

        func offset(_ base: CGPoint, _ dir: CGPoint, _ amount: CGFloat) -> CGPoint {
            CGPoint(x: base.x + dir.x * amount, y: base.y + dir.y * amount)
        }

        let corner1 = offset(apex, inDir, s)
        let corner2 = offset(offset(apex, inDir, s), outDir, s)
        let corner3 = offset(apex, outDir, s)
        return [corner1, corner2, corner3]
    }
}
