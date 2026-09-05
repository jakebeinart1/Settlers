import SwiftUI

/// Which kind of build placement the human has armed via `BuildPopupView`.
/// While non-nil, `BoardView` accepts only legal targets for that move.
public enum PlacementMode: Equatable {
    case road
    case settlement
    case city

    var label: String {
        switch self {
        case .road: return "Road"
        case .settlement: return "Settlement"
        case .city: return "City"
        }
    }
}

private struct SlotHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Reserves the tallest height its content has measured. Dynamic banners used
/// to resize the flexible board every time they appeared or disappeared.
/// Empty content must be a zero-height view; an unconstrained `Color.clear`
/// competes with the board for the same flexible space before measurement.
struct StableHeightSlot<Content: View>: View {
    @Binding var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: SlotHeightKey.self, value: geometry.size.height)
                }
            )
            .onPreferenceChange(SlotHeightKey.self) { measured in
                if measured > height { height = measured }
            }
            .frame(height: height > 0 ? height : nil, alignment: .top)
    }
}
