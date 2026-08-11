import SwiftUI

// MARK: - Britannia: castle keep / turret silhouettes

/// Britannia settlement: a single square keep with three crenellations
/// along the top and a small pennant, standing in for an early fortified
/// tower.
struct BritanniaKeepShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wallTop = rect.minY + rect.height * 0.32
        let merlonHeight = rect.height * 0.18
        let merlonWidth = rect.width / 5

        // Tower body.
        path.addRect(CGRect(x: rect.minX, y: wallTop, width: rect.width, height: rect.maxY - wallTop))

        // Three crenellation merlons along the top edge.
        for i in [0, 2, 4] {
            let x = rect.minX + merlonWidth * CGFloat(i)
            path.addRect(CGRect(x: x, y: wallTop - merlonHeight, width: merlonWidth, height: merlonHeight))
        }

        // Pennant on a short pole above the center merlon.
        let poleX = rect.midX
        path.move(to: CGPoint(x: poleX, y: wallTop - merlonHeight))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY))
        path.addLine(to: CGPoint(x: poleX + rect.width * 0.22, y: rect.minY + rect.height * 0.08))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.16))
        path.closeSubpath()

        return path
    }
}

/// Britannia city: a wider castle - two flanking towers (each with its own
/// crenellations) joined by a lower curtain wall - reading as a clear
/// upgrade from the single keep.
struct BritanniaCastleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let towerWidth = rect.width * 0.3
        let wallTop = rect.minY + rect.height * 0.45
        let towerTop = rect.minY + rect.height * 0.12
        let merlon = rect.width * 0.08

        // Curtain wall.
        path.addRect(CGRect(x: rect.minX, y: wallTop, width: rect.width, height: rect.maxY - wallTop))
        for x in stride(from: rect.minX, to: rect.maxX, by: rect.width / 6) {
            path.addRect(CGRect(x: x, y: wallTop - merlon, width: rect.width / 12, height: merlon))
        }

        // Two towers.
        for towerX in [rect.minX, rect.maxX - towerWidth] {
            path.addRect(CGRect(x: towerX, y: towerTop, width: towerWidth, height: rect.maxY - towerTop))
            let crenellations = 3
            let cw = towerWidth / CGFloat(crenellations * 2 - 1)
            for i in stride(from: 0, to: crenellations * 2 - 1, by: 2) {
                path.addRect(CGRect(x: towerX + cw * CGFloat(i), y: towerTop - merlon, width: cw, height: merlon))
            }
        }
        return path
    }
}

// MARK: - Rome: column / temple silhouettes

/// Rome settlement: a single classical column - plinth base, fluted shaft,
/// and a capital - standing alone like an early outpost marker.
struct RomanColumnShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseHeight = rect.height * 0.09
        let capitalHeight = rect.height * 0.1
        let shaftWidth = rect.width * 0.34
        let shaftX = rect.midX - shaftWidth / 2
        let baseWidth = rect.width * 0.6
        let capitalWidth = rect.width * 0.52

        // Base plinth.
        path.addRect(CGRect(x: rect.midX - baseWidth / 2, y: rect.maxY - baseHeight, width: baseWidth, height: baseHeight))
        // Shaft - the dominant vertical element, clearly narrower than the
        // base/capital so the whole thing reads as a column rather than an
        // "I-beam" of near-equal-width bars.
        path.addRect(CGRect(x: shaftX, y: rect.minY + capitalHeight, width: shaftWidth, height: rect.maxY - baseHeight - (rect.minY + capitalHeight)))
        // Capital.
        path.addRect(CGRect(x: rect.midX - capitalWidth / 2, y: rect.minY, width: capitalWidth, height: capitalHeight))
        return path
    }
}

/// Rome city: a temple facade - triangular pediment over three columns on a
/// base platform - clearly grander than the lone settlement column.
struct RomanTempleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseHeight = rect.height * 0.12
        let pedimentHeight = rect.height * 0.28
        let columnsTop = rect.minY + pedimentHeight
        let columnsBottom = rect.maxY - baseHeight

        // Base platform.
        path.addRect(CGRect(x: rect.minX, y: columnsBottom, width: rect.width, height: baseHeight))

        // Pediment triangle.
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: columnsTop))
        path.addLine(to: CGPoint(x: rect.minX, y: columnsTop))
        path.closeSubpath()

        // Three columns.
        let columnWidth = rect.width * 0.16
        for i in 0..<3 {
            let x = rect.minX + rect.width * 0.08 + CGFloat(i) * (rect.width * 0.38)
            path.addRect(CGRect(x: x, y: columnsTop, width: columnWidth, height: columnsBottom - columnsTop))
        }
        return path
    }
}

// MARK: - China: pagoda silhouettes

/// China settlement/city: a stack of `tiers` trapezoidal roof tiers, each
/// narrower than the one below with upturned eave corners - one tier for a
/// settlement, two for a city, reading as a taller pagoda.
struct PagodaShape: Shape {
    let tiers: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tierHeight = rect.height / CGFloat(tiers + 1)
        let spireHeight = tierHeight * 0.5

        // Central spire finial at the very top.
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.03, y: rect.minY + spireHeight))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.03, y: rect.minY + spireHeight))
        path.closeSubpath()

        for tier in 0..<tiers {
            let top = rect.minY + spireHeight + CGFloat(tier) * tierHeight
            let bottom = top + tierHeight
            // Each roof narrows toward the top; eaves flare out at the
            // bottom of the tier past the walls below.
            let inset = rect.width * (0.22 - CGFloat(tier) * 0.05)
            let eaveFlare = rect.width * 0.1

            path.move(to: CGPoint(x: rect.minX - eaveFlare, y: bottom))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: top))
            path.addLine(to: CGPoint(x: rect.maxX - inset, y: top))
            path.addLine(to: CGPoint(x: rect.maxX + eaveFlare, y: bottom))
            path.addLine(to: CGPoint(x: rect.minX - eaveFlare, y: bottom))
            path.closeSubpath()
        }

        // Base walls beneath the lowest tier.
        let wallTop = rect.minY + spireHeight + CGFloat(tiers) * tierHeight
        let wallWidth = rect.width * 0.5
        path.addRect(CGRect(x: rect.midX - wallWidth / 2, y: wallTop, width: wallWidth, height: rect.maxY - wallTop))
        return path
    }
}

// MARK: - Mongolia: yurt silhouettes

/// Mongolia settlement: a single domed yurt (ger) - rounded roof over a
/// straight wall base, with a smoke-hole finial on top. No door cutout (a
/// self-intersecting "notch" subpath rendered as a full archway rather than
/// a small doorway at this icon's scale, and the detail wasn't legible at
/// board size anyway) - a clean dome+wall silhouette reads better small.
struct YurtShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let wallTop = rect.minY + rect.height * 0.45
        path.addArc(
            center: CGPoint(x: rect.midX, y: wallTop),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(360),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        // Smoke-hole finial.
        let finialWidth = rect.width * 0.08
        path.addRect(CGRect(x: rect.midX - finialWidth / 2, y: rect.minY - rect.height * 0.05, width: finialWidth, height: rect.height * 0.1))
        return path
    }
}

/// Mongolia city: a small camp - two yurts side by side with a banner pole
/// between them - reading as a settlement grown into an encampment.
struct YurtCampShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let yurtWidth = rect.width * 0.42
        for yurtX in [rect.minX, rect.maxX - yurtWidth] {
            let yurtRect = CGRect(x: yurtX, y: rect.minY + rect.height * 0.2, width: yurtWidth, height: rect.height * 0.8)
            let wallTop = yurtRect.minY + yurtRect.height * 0.4
            path.addArc(
                center: CGPoint(x: yurtRect.midX, y: wallTop),
                radius: yurtWidth / 2,
                startAngle: .degrees(180),
                endAngle: .degrees(360),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: yurtRect.maxX, y: yurtRect.maxY))
            path.addLine(to: CGPoint(x: yurtRect.minX, y: yurtRect.maxY))
            path.closeSubpath()
        }

        // Banner pole between the two yurts.
        let poleX = rect.midX
        path.move(to: CGPoint(x: poleX, y: rect.maxY))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY))
        path.addLine(to: CGPoint(x: poleX + rect.width * 0.16, y: rect.minY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: poleX, y: rect.minY + rect.height * 0.24))
        path.closeSubpath()

        return path
    }
}
