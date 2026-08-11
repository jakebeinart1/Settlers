import SwiftUI

// Small, bold, single-silhouette shapes for `CivilizationBadge` - one per
// civilization, distinct enough to tell apart at a glance even tiny.
// Deliberately simple (a handful of straight lines/arcs each, flat fill, no
// isometric shading) after both detailed illustrated buildings and plain
// circle-with-glyph badges didn't land - these read as an actual building
// silhouette without needing real size to do it.

/// Egypt: a plain triangle. The simplest possible pyramid silhouette.
struct EgyptPyramidGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Aztec: a 3-tier stepped ziggurat, each tier narrower than the one below.
struct AztecZigguratGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tiers = 3
        let tierHeight = rect.height / CGFloat(tiers)
        for tier in 0..<tiers {
            let inset = rect.width * 0.5 * (CGFloat(tier) / CGFloat(tiers))
            let top = rect.minY + CGFloat(tier) * tierHeight
            path.addRect(CGRect(x: rect.minX + inset, y: top, width: rect.width - inset * 2, height: tierHeight))
        }
        return path
    }
}

/// Greece: a temple front - triangular pediment over four columns on a base.
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
        let columnWidth = rect.width * 0.14
        for i in 0..<4 {
            let x = rect.minX + rect.width * 0.08 + CGFloat(i) * (rect.width * 0.28)
            path.addRect(CGRect(x: x, y: columnTop, width: columnWidth, height: columnBottom - columnTop))
        }
        return path
    }
}

/// Rome: a rounded archway - distinct from Greece's flat-topped temple so
/// the two "classical column" civilizations don't read as the same shape.
struct RomeArchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let archCenter = CGPoint(x: rect.midX, y: rect.minY + radius)
        path.addArc(center: archCenter, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
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
