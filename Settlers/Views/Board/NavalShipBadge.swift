import SwiftUI

/// Painted vessels use the current controller's cloth and hull silhouette.
/// Ownership needs no building stamped on the sail. All board, fleet, build
/// and proposal callers share this image; the surrounding control owns taps
/// and spoken ship identity. Selection decoration stays thin at maximum zoom.
struct NavalShipBadge: View {
    let color: Color
    let civilization: Civilization
    var isSelected = false
    var isProvisional = false

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                if isSelected || isProvisional {
                    RoundedRectangle(cornerRadius: min(14, max(6, size * 0.16)))
                        .fill(color.opacity(isProvisional ? 0.09 : 0.15))
                    RoundedRectangle(cornerRadius: min(14, max(6, size * 0.16)))
                        .strokeBorder(CatanTheme.chipGold,
                                      style: StrokeStyle(lineWidth: min(2.5, max(1.25, size * 0.025)),
                                                         dash: isProvisional ? [5, 3] : []))
                }
                Image(civilization.shipAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .opacity(isProvisional ? 0.78 : 1)
                    .shadow(color: .black.opacity(0.25), radius: max(0.5, size * 0.018),
                            x: 0, y: max(0.5, size * 0.018))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The painted image fills more of its square than the retired polygon.
/// A common visual size prevents proposals growing larger than real ships;
/// interaction continues to use the separate, at-least-44pt hit geometry.
enum NavalShipArtworkMetrics {
    static func diameter(hexSize: CGFloat) -> CGFloat { max(22, hexSize * 0.92) }
}
