import SwiftUI

/// The shared uniform-button treatment used by both bottom rows of
/// `GameView` (build actions and trade/turn actions): icon-over-title,
/// `.frame(maxWidth: .infinity)` so every button in a row is the same size
/// regardless of label length, and a consistent disable+dim pattern.
/// Originally lived only in `BuildMenuView`; factored out here so Row 2
/// (Trade / Dev Cards / turn action) can match Row 1 exactly rather than
/// re-implementing the same look with slightly different numbers.
public struct UniformActionButton: View {
    public let title: String
    public let systemImage: String
    public let isEnabled: Bool
    public let isArmed: Bool
    public let action: () -> Void

    public init(title: String, systemImage: String, isEnabled: Bool, isArmed: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isArmed = isArmed
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isArmed ? Color.yellow.opacity(0.35) : Color(white: 0.18))
            )
            .foregroundStyle(.white)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}
