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
        let shape = civilization.pieceShape()
        let etch = civilization.etchDetail()
        let backing = civilization.backingFill()
        let strokeWidth = max(1, size * 0.045)

        VStack(spacing: 0) {
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
                // of the fill at all and read as see-through.
                if let backing {
                    backing.fill(.white)
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
