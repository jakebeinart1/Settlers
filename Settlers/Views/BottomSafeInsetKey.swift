import SwiftUI

/// Reports the bottom safe-area inset - the home-indicator band - up to
/// `GameView`, which spends most of it on the board.
///
/// Read from a `GeometryReader` that still sits INSIDE the safe area, which
/// is the only kind that reports one. Measured on an iPhone 17 Pro: a reader
/// placed in the screen's background layer - which ignores the safe area -
/// was handed the whole screen and reported an inset of 0.0, while a plain
/// reader in the same view's background reported 34.0.
///
/// It is a preference rather than a constant because it is not one number.
/// It is 34.67 on a Face ID iPhone and exactly 0 on a home-button one, and a
/// constant tuned on the former pushes the action row off the bottom of the
/// latter.
struct BottomSafeInsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
