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
    /// Asset name of a painted button-frame background (see
    /// design-references/STATUS.md) for the 3 fixed action-row roles
    /// (Trade/Build/turn-action), which always mean the same thing and so
    /// always get the same frame. `nil` for every other use of this same
    /// button (robber-victim picks, Cancel, dynamic Road/Settlement/City
    /// labels) - those keep the plain flat background, since there's no
    /// fixed frame per label to paint ahead of time.
    public let backgroundImageName: String?
    public let action: () -> Void

    public init(title: String, systemImage: String, isEnabled: Bool, isArmed: Bool = false, backgroundImageName: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.isArmed = isArmed
        self.backgroundImageName = backgroundImageName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(background)
            .foregroundStyle(.white)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var background: some View {
        if isArmed {
            RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.35))
        } else if let backgroundImageName {
            // `.scaledToFill()` + clip, not a 9-slice `capInsets` stretch -
            // stretching warped the frame's corner ornamentation whenever
            // the button's real proportions didn't match the source
            // image's, which is what read as "cut off"/rough. Fill+clip
            // can only crop evenly, never distort.
            Image(backgroundImageName)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18))
        }
    }
}
