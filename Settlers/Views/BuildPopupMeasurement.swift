import SwiftUI

nonisolated enum BuildPopupPart: Hashable { case header, choices, footer, error }

/// These are intrinsic popup parts, never the board's fitted geometry. The
/// fresh dictionary replaces earlier measurements, so text changes can shrink
/// as well as grow and a dismissed popup retains no historical size.
nonisolated struct BuildPopupHeightPreference: PreferenceKey {
    static var defaultValue: [BuildPopupPart: CGFloat] { [:] }
    static func reduce(value: inout [BuildPopupPart: CGFloat],
                       nextValue: () -> [BuildPopupPart: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, current in current })
    }
}

extension View {
    func measureBuildPopupPart(_ part: BuildPopupPart) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: BuildPopupHeightPreference.self, value: [part: proxy.size.height])
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
