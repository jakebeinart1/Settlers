import SwiftUI

/// A small, flat marker for a settlement/city on the board - replaces both
/// the detailed isometric/illustrated building art (needed real size to
/// stay legible) and a plain circle-with-glyph badge (read as too generic,
/// not enough like an actual building) tried before this. Each civilization
/// gets its own bold, single-silhouette shape (`CivilizationPieceShapes`) -
/// Egypt's pyramid, Aztec's ziggurat, Greece's temple front, Rome's arch -
/// filled with that civilization's own color and a thin black outline,
/// matching the board's flat, straight-bordered, black-outlined style. A
/// city is the same silhouette, just bigger, with an added white ring so
/// the upgrade from settlement -> city is visible at a glance.
struct CivilizationBadge: View {
    let civilization: Civilization
    let isCity: Bool
    let size: CGFloat

    var body: some View {
        let shape = civilization.pieceShape()

        ZStack {
            if isCity {
                shape
                    .stroke(.white, lineWidth: max(2, size * 0.16))
                    .padding(size * 0.06)
            }
            shape
                .fill(civilization.accentColor)
                .overlay(shape.stroke(.black, lineWidth: 1.5))
        }
        .frame(width: size, height: size)
    }
}
