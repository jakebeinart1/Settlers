import SwiftUI

// Small, bold, single-silhouette shapes for `CivilizationBadge` - one per
// civilization, distinct enough to tell apart at a glance even tiny.
// Deliberately simple (a handful of straight lines/arcs each, flat fill, no
// isometric shading) after both detailed illustrated buildings and plain
// circle-with-glyph badges didn't land - these read as an actual building
// silhouette without needing real size to do it. Each civilization also
// gets a small stroked "etch" detail (a doorway, a relief line) via
// `Civilization.etchDetail()`, always drawn on top of the filled silhouette
// - see the Claude Design pass at
// `docs/superpowers/specs/2026-08-12-civilization-expansion-design.md`.

/// Converts a design-doc SVG coordinate (its exports use a 0-100 viewBox)
/// into a point within `rect`, so each glyph below can be transcribed close
/// to its source path data instead of hand-derived fractions.
private func svgPoint(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
}

/// Same conversion as `svgPoint`, for an axis-aligned rect given in SVG
/// 0-100 coordinates.
private func svgRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, in rect: CGRect) -> CGRect {
    CGRect(
        x: rect.minX + x / 100 * rect.width,
        y: rect.minY + y / 100 * rect.height,
        width: width / 100 * rect.width,
        height: height / 100 * rect.height
    )
}

/// A stroked-outline rect (or several) at fixed SVG-space positions - the
/// shared building block for every civilization's "etched detail" doorway
/// except Greece's pediment outline, which needs an actual triangle.
private struct EtchRectsGlyph: Shape {
    let rects: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for r in rects {
            path.addRect(svgRect(r.x, r.y, r.width, r.height, in: rect))
        }
        return path
    }
}

// MARK: - Egypt

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

// MARK: - Aztec

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

// MARK: - Greece

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

/// Greece's etch detail: a small stroked triangle nested inside the
/// pediment, reading as a relief carving rather than a bare flat gable.
/// A solid backing wall spanning the gap the temple's 4 columns stand in
/// (same `columnTop`/`columnBottom` span `GreeceTempleGlyph` uses) - without
/// it, the space *between* columns wasn't part of the fill at all, so it
/// read as see-through (the board tile color showing straight through the
/// temple). Drawn behind `pieceShape()` in white, so it reads as an actual
/// back wall rather than a gap.
private struct GreeceBackWallGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let pedimentHeight = rect.height * 0.32
        let baseHeight = rect.height * 0.15
        let columnTop = rect.minY + pedimentHeight
        let columnBottom = rect.maxY - baseHeight
        return Path(CGRect(x: rect.minX, y: columnTop, width: rect.width, height: columnBottom - columnTop))
    }
}

private struct GreecePedimentEtchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: svgPoint(50, 6, in: rect))
        path.addLine(to: svgPoint(58, 26, in: rect))
        path.addLine(to: svgPoint(42, 26, in: rect))
        path.closeSubpath()
        return path
    }
}

// MARK: - Britannia

/// Medieval Britannia: a square keep with three crenellations along the top
/// and a small pennant on a pole - a castle tower silhouette, distinct from
/// Greece's flat-topped temple and Rome's arch (which this replaced).
struct MedievalKeepGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wallTop = rect.minY + rect.height * 0.34
        let merlonHeight = rect.height * 0.16
        let merlonWidth = rect.width / 5

        path.addRect(CGRect(x: rect.minX, y: wallTop, width: rect.width, height: rect.maxY - wallTop))

        for i in [0, 2, 4] {
            let x = rect.minX + merlonWidth * CGFloat(i)
            path.addRect(CGRect(x: x, y: wallTop - merlonHeight, width: merlonWidth, height: merlonHeight))
        }

        // Pennant on a pole above the center merlon.
        let poleX = rect.midX
        path.move(to: CGPoint(x: poleX, y: wallTop - merlonHeight))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY))
        path.addLine(to: CGPoint(x: poleX + rect.width * 0.24, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.17))
        path.closeSubpath()

        return path
    }
}

// MARK: - Columbia

/// Columbia: a domed capitol - drum, dome and a stepped portico, matching
/// the "monument silhouette" pattern the other three founding civilizations
/// already use (pyramid, temple, keep).
struct ColumbiaCapitolGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Body, drum, and dome all widened/heightened from the original
        // pass, and the dome's own arc pulled up much taller (control point
        // well above the frame instead of only halfway up, plus a pole
        // reaching the very top that overlaps down into the dome so it
        // reads as one connected spire rather than a floating cap) - the
        // original left most of the upper half of the bounding box empty
        // (just a thin disconnected pole), so next to the other
        // civilizations' silhouettes (which all reach clear to the top
        // edge) it read as noticeably smaller despite sharing the same
        // badge size. Verified by rendering both side by side before
        // shipping - see chat.
        path.addRect(svgRect(0, 92, 100, 8, in: rect))
        path.addRect(svgRect(4, 50, 92, 42, in: rect))
        path.addRect(svgRect(30, 36, 40, 14, in: rect))
        path.move(to: svgPoint(30, 36, in: rect))
        path.addQuadCurve(to: svgPoint(70, 36, in: rect), control: svgPoint(50, -14, in: rect))
        path.closeSubpath()
        path.addRect(svgRect(47, 0, 6, 20, in: rect))
        return path
    }
}

/// Columbia's etch detail: the portico's four columns plus the entrance
/// doorway, all stroked outlines over the filled capitol silhouette -
/// rescaled to match `ColumbiaCapitolGlyph`'s bigger body.
private struct ColumbiaEtchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        EtchRectsGlyph(rects: [
            (12, 56, 6, 34),
            (28, 56, 6, 34),
            (66, 56, 6, 34),
            (82, 56, 6, 34),
            (44, 74, 12, 16),
        ]).path(in: rect)
    }
}

// MARK: - Rome

/// Rome: an arena - a cornice band over a colonnaded body, evoking the
/// Colosseum's arched tiers without needing actual arches to stay legible
/// at badge scale.
struct RomeArenaGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(svgRect(0, 20, 100, 8, in: rect))
        path.addRect(svgRect(0, 28, 100, 72, in: rect))
        return path
    }
}

/// Rome's etch detail: four evenly-spaced column bays across the body.
private struct RomeEtchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        EtchRectsGlyph(rects: [
            (8.8, 50, 14, 50),
            (31.6, 50, 14, 50),
            (54.4, 50, 14, 50),
            (77.2, 50, 14, 50),
        ]).path(in: rect)
    }
}

// MARK: - Japan

/// Japan: a stepped pagoda - three tiers of alternating wide roof/narrow
/// body, crowned with a thin spire, mirroring the Aztec ziggurat's
/// stepped-tier language from the opposite direction (roofs flare out over
/// each body instead of tiers stepping straight in).
struct JapanPagodaGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(svgRect(20, 60, 60, 40, in: rect))

        path.move(to: svgPoint(6, 50, in: rect))
        path.addLine(to: svgPoint(94, 50, in: rect))
        path.addLine(to: svgPoint(80, 60, in: rect))
        path.addLine(to: svgPoint(20, 60, in: rect))
        path.closeSubpath()

        path.addRect(svgRect(32, 20, 36, 30, in: rect))

        path.move(to: svgPoint(18, 10, in: rect))
        path.addLine(to: svgPoint(82, 10, in: rect))
        path.addLine(to: svgPoint(68, 20, in: rect))
        path.addLine(to: svgPoint(32, 20, in: rect))
        path.closeSubpath()

        path.addRect(svgRect(48, 0, 4, 10, in: rect))
        return path
    }
}

/// Japan's etch detail: a small entrance doorway in the base tier.
private struct JapanEtchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        EtchRectsGlyph(rects: [(44, 86, 12, 14)]).path(in: rect)
    }
}

// MARK: - Norse

/// Norse: a longhouse - a steep gabled roof over a rectangular hall, with
/// small carved eaves at each corner of the roofline (a nod to dragon-head
/// gable carvings without needing the detail to read at badge scale).
struct NorseLonghouseGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(svgRect(8, 50, 84, 50, in: rect))

        path.move(to: svgPoint(0, 50, in: rect))
        path.addLine(to: svgPoint(50, 10, in: rect))
        path.addLine(to: svgPoint(100, 50, in: rect))
        path.closeSubpath()

        path.move(to: svgPoint(0, 50, in: rect))
        path.addLine(to: svgPoint(8, 50, in: rect))
        path.addLine(to: svgPoint(4, 38, in: rect))
        path.closeSubpath()

        path.move(to: svgPoint(100, 50, in: rect))
        path.addLine(to: svgPoint(92, 50, in: rect))
        path.addLine(to: svgPoint(96, 38, in: rect))
        path.closeSubpath()

        return path
    }
}

/// Norse's etch detail: the hall's entrance doorway.
private struct NorseEtchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        EtchRectsGlyph(rects: [(42, 74, 16, 26)]).path(in: rect)
    }
}

extension Civilization {
    /// An optional solid backing shape drawn behind `pieceShape()`, filled
    /// white - only Greece needs one (see `GreeceBackWallGlyph`), so this
    /// is `nil` everywhere else rather than every civilization needing its
    /// own no-op case.
    @MainActor
    func backingFill() -> AnyShape? {
        switch self {
        case .greece: return AnyShape(GreeceBackWallGlyph())
        default: return nil
        }
    }

    /// This civilization's flat piece silhouette, drawn by `CivilizationBadge`.
    @MainActor
    func pieceShape() -> AnyShape {
        switch self {
        case .medieval: return AnyShape(MedievalKeepGlyph())
        case .greece: return AnyShape(GreeceTempleGlyph())
        case .egypt: return AnyShape(EgyptPyramidGlyph())
        case .aztec: return AnyShape(AztecZigguratGlyph())
        case .columbia: return AnyShape(ColumbiaCapitolGlyph())
        case .rome: return AnyShape(RomeArenaGlyph())
        case .japan: return AnyShape(JapanPagodaGlyph())
        case .norse: return AnyShape(NorseLonghouseGlyph())
        }
    }

    /// This civilization's small stroked "etch" detail - a doorway or
    /// relief line drawn on top of `pieceShape()`, on both the settlement
    /// and city variant.
    @MainActor
    func etchDetail() -> AnyShape {
        switch self {
        case .medieval: return AnyShape(EtchRectsGlyph(rects: [(42, 80, 16, 20)]))
        case .greece: return AnyShape(GreecePedimentEtchGlyph())
        case .egypt: return AnyShape(EtchRectsGlyph(rects: [(43, 79, 14, 9)]))
        case .aztec: return AnyShape(EtchRectsGlyph(rects: [(43, 85, 14, 15)]))
        case .columbia: return AnyShape(ColumbiaEtchGlyph())
        case .rome: return AnyShape(RomeEtchGlyph())
        case .japan: return AnyShape(JapanEtchGlyph())
        case .norse: return AnyShape(NorseEtchGlyph())
        }
    }
}
