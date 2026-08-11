import SwiftUI

/// A small, flat marker for a settlement/city on the board - replaces the
/// detailed isometric/illustrated building art (Rome's arch, Egypt's
/// pyramid, etc.) that kept needing real size to stay legible. This is
/// deliberately simple instead: a solid circle in the civilization's own
/// color, a thin black outline (matching the flat, straight-bordered board
/// style), and that civilization's emblem glyph in white - reads clearly
/// even tiny, same as the number tokens' own black-outlined circles. A city
/// is the same badge, just bigger, with an extra white ring so the upgrade
/// from settlement -> city is visible even at a glance.
struct CivilizationBadge: View {
    let civilization: Civilization
    let isCity: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(civilization.accentColor)
            if isCity {
                Circle()
                    .strokeBorder(.white, lineWidth: max(1.5, size * 0.07))
                    .padding(size * 0.1)
            }
            Circle()
                .strokeBorder(.black, lineWidth: 1.5)
            Image(systemName: civilization.emblemSymbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
