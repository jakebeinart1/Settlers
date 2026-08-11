import SwiftUI

// Small, bold, single-silhouette shapes for `CivilizationBadge` - one per
// civilization, distinct enough to tell apart at a glance even tiny.
// Deliberately simple (a handful of straight lines/arcs each, flat fill, no
// isometric shading) after both detailed illustrated buildings and plain
// circle-with-glyph badges didn't land - these read as an actual building
// silhouette without needing real size to do it.

/// Egypt: a triangle with a small base band underneath (so it reads as a
/// pyramid sitting on ground, not a bare geometric triangle) plus a few
/// horizontal "stone course" lines - added as thin closed sub-rectangles
/// spanning the triangle's actual width at that height, rather than a
/// second stroke color: since the whole shape fills one flat color, a thin
/// band's own top/bottom edges read as a horizontal line once the shape is
/// outlined, without `CivilizationBadge` needing to know about it.
struct EgyptPyramidGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseHeight = rect.height * 0.12
        let peakY = rect.minY
        let bodyBottom = rect.maxY - baseHeight

        path.move(to: CGPoint(x: rect.midX, y: peakY))
        path.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom))
        path.addLine(to: CGPoint(x: rect.minX, y: bodyBottom))
        path.closeSubpath()

        path.addRect(CGRect(x: rect.minX, y: bodyBottom, width: rect.width, height: baseHeight))

        let courseCount = 3
        let lineThickness = max(1, rect.height * 0.02)
        for i in 1...courseCount {
            let y = peakY + (bodyBottom - peakY) * CGFloat(i) / CGFloat(courseCount + 1)
            let halfWidth = (rect.width / 2) * (y - peakY) / (bodyBottom - peakY)
            path.addRect(CGRect(x: rect.midX - halfWidth, y: y - lineThickness / 2, width: halfWidth * 2, height: lineThickness))
        }
        return path
    }
}

/// Aztec: a 3-tier stepped ziggurat, widest at the base and narrowing going
/// up (each tier above sits inset from the one below it), crowned with a
/// small temple block at the peak.
struct AztecZigguratGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let templeHeight = rect.height * 0.14
        let bodyTop = rect.minY + templeHeight
        let tiers = 3
        let tierHeight = (rect.maxY - bodyTop) / CGFloat(tiers)
        for tier in 0..<tiers {
            // tier 0 is the top (narrowest); tier (tiers-1) is the bottom
            // (widest) - inset shrinks as tier increases, i.e. as you go
            // down toward the base.
            let stepsFromTop = CGFloat(tiers - 1 - tier)
            let inset = rect.width * 0.5 * (stepsFromTop / CGFloat(tiers))
            let top = bodyTop + CGFloat(tier) * tierHeight
            path.addRect(CGRect(x: rect.minX + inset, y: top, width: rect.width - inset * 2, height: tierHeight))
        }

        let templeWidth = rect.width * 0.22
        path.addRect(CGRect(x: rect.midX - templeWidth / 2, y: rect.minY, width: templeWidth, height: templeHeight))
        return path
    }
}

/// Greece: a temple front - triangular pediment over four evenly-spaced
/// columns on a base, all sized to actually fit within the shape's bounds
/// (the columns previously ran past the right edge).
struct GreeceTempleGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pedimentHeight = rect.height * 0.32
        let baseHeight = rect.height * 0.15

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + pedimentHeight))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + pedimentHeight))
        path.closeSubpath()

        path.addRect(CGRect(x: rect.minX, y: rect.maxY - baseHeight, width: rect.width, height: baseHeight))

        let columnTop = rect.minY + pedimentHeight
        let columnBottom = rect.maxY - baseHeight
        let margin = rect.width * 0.08
        let usableWidth = rect.width - margin * 2
        let columnCount = 4
        let columnWidth = usableWidth * 0.16
        let gap = (usableWidth - columnWidth * CGFloat(columnCount)) / CGFloat(columnCount - 1)
        for i in 0..<columnCount {
            let x = rect.minX + margin + CGFloat(i) * (columnWidth + gap)
            path.addRect(CGRect(x: x, y: columnTop, width: columnWidth, height: columnBottom - columnTop))
        }
        return path
    }
}

/// Rome: a rounded archway on a small base band - distinct from Greece's
/// flat-topped temple so the two "classical column" civilizations don't
/// read as the same shape.
struct RomeArchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseHeight = rect.height * 0.12
        let archBottom = rect.maxY - baseHeight
        let radius = rect.width / 2
        let archCenter = CGPoint(x: rect.midX, y: rect.minY + radius)

        path.addArc(center: archCenter, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: archBottom))
        path.addLine(to: CGPoint(x: rect.minX, y: archBottom))
        path.closeSubpath()

        path.addRect(CGRect(x: rect.minX, y: archBottom, width: rect.width, height: baseHeight))
        return path
    }
}

extension Civilization {
    /// This civilization's flat piece silhouette, drawn by `CivilizationBadge`.
    @MainActor
    func pieceShape() -> AnyShape {
        switch self {
        case .rome: return AnyShape(RomeArchGlyph())
        case .greece: return AnyShape(GreeceTempleGlyph())
        case .egypt: return AnyShape(EgyptPyramidGlyph())
        case .aztec: return AnyShape(AztecZigguratGlyph())
        }
    }
}
