import SwiftUI

/// A small, flat marker for a settlement/city on the board - replaces both
/// the detailed isometric/illustrated building art (needed real size to
/// stay legible) and a plain circle-with-glyph badge (read as too generic,
/// not enough like an actual building) tried before this. Each civilization
/// gets its own bold, single-silhouette shape (`CivilizationPieceShapes`)
/// filled with that civilization's own color, a thin black outline, and a
/// small stroked "etch" detail (a doorway, a relief line) matching the
/// board's flat, straight-bordered, black-outlined style.
///
/// A city is the same silhouette, compressed into the bottom ~80% of the
/// same square frame (rather than growing the frame - keeps board layout
/// untouched), with a small gold pennant-on-a-pole flying above it in the
/// freed-up headroom - swapped in for the old plain white ring, which read
/// as a highlight rather than an actual upgrade.
struct CivilizationBadge: View {
    let civilization: Civilization
    let isCity: Bool
    let size: CGFloat

    var body: some View {
        // Painted landmark art (a real famous building - the Colosseum,
        // the Capitol dome, ...) for whichever civilizations have it so
        // far; everything else still falls back to the vector silhouette
        // below until its own art exists. See design-references/STATUS.md.
        if let imageName = civilization.paintedPieceImageName(isCity: isCity) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            vectorBadge
        }
    }

    private var vectorBadge: some View {
        let shape = civilization.pieceShape()
        let etch = civilization.etchDetail()
        let backing = civilization.backingFill()
        let strokeWidth = max(1, size * 0.045)

        return VStack(spacing: 0) {
            if isCity {
                PennantGlyph()
                    .fill(CatanTheme.cityPennantGold)
                    .overlay(PennantGlyph().stroke(.black, lineWidth: strokeWidth * 0.7))
                    .frame(width: size * 0.32, height: size * 0.2)
                    .frame(maxWidth: .infinity)
            }

            ZStack {
                // Behind the main silhouette, e.g. Greece's back wall
                // between its columns - without it, that gap wasn't part
                // of the fill at all and read as see-through. Filled with
                // the piece's own accent color (not plain white) so the
                // wall matches the rest of the piece instead of reading as
                // a lighter patch behind the columns, and stroked the same
                // as the silhouette so the wall's left/right edges - the
                // only edges nothing else in the shape already borders -
                // get an outline too.
                if let backing {
                    backing
                        .fill(civilization.accentColor)
                        .overlay(backing.stroke(.black, lineWidth: strokeWidth))
                }
                shape
                    .fill(civilization.accentColor)
                    .overlay(shape.stroke(.black, lineWidth: strokeWidth))
                etch
                    .stroke(.black, lineWidth: strokeWidth * 0.7)
            }
            .frame(height: isCity ? size * 0.8 : size)
        }
        .frame(width: size, height: size)
    }
}

/// The civilization's board piece presented as a compact heraldic mark.
///
/// HUDs previously paired an ownership-color dot with an unrelated SF Symbol
/// (sun, bolt, crown), while the map used painted settlements. A player then
/// had to learn two logo systems for the same opponent. This crest reuses the
/// exact settlement artwork from `CivilizationBadge`; the dark seal and exact
/// accent ring only give that irregular transparent art a reliable footprint
/// on light, dark and textured surfaces.
struct CivilizationCrest: View {
    let civilization: Civilization
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.42))
            Circle()
                .strokeBorder(Color.black.opacity(0.9), lineWidth: max(1, size * 0.11))
            Circle()
                .inset(by: max(1, size * 0.055))
                .strokeBorder(civilization.accentColor, lineWidth: max(1, size * 0.075))
            CivilizationBadge(
                civilization: civilization,
                isCity: false,
                size: size * 0.72
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The city marker's pennant-on-a-pole, shared across every civilization
/// (only the building silhouette differs) - a thin pole with a small
/// triangular flag near its top, drawn within whatever rect it's given.
struct PennantGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let poleWidth = max(1, rect.width * 0.16)
        path.addRect(CGRect(x: rect.midX - poleWidth / 2, y: rect.minY, width: poleWidth, height: rect.height))

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.32))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.6))
        path.closeSubpath()

        return path
    }
}
