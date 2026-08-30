import SwiftUI
/// Reports how far down the screen the board's top chips reach, so the board
/// can clear them without anyone hardcoding a number.
///
/// The alternative - and what was here before - is a constant tuned against a
/// screenshot. It was revised four times (18, 30, 50, 38) and still let a port
/// badge slide under the bank chip, because the chips are overlays whose height
/// depends on their content and on the reader's Dynamic Type setting, neither
/// of which a constant can know.
struct TopChipHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
