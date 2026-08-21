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
    /// Asset name of a painted, border-less fill texture (see
    /// design-references/STATUS.md) for the 3 fixed action-row roles
    /// (Trade/Build/turn-action), which always mean the same thing and so
    /// always get the same texture. `nil` for every other use of this same
    /// button (robber-victim picks, Cancel, dynamic Road/Settlement/City
    /// labels) - those keep the plain flat background, since there's no
    /// fixed texture per label to paint ahead of time.
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
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
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
            // The gold pill border is drawn natively here, not baked into
            // the image - a whole ornate bordered plaque asset (tried
            // first) has a fixed aspect ratio, and this button's real
            // on-screen proportions never landed close enough to any
            // single generated aspect to avoid either cropping the border
            // away on some buttons or leaving inconsistent dead margin on
            // others (see chat / design-references/STATUS.md). A native
            // `Capsule` stroke is correct at any size by construction, so
            // the image asset only needs to be a plain repeating texture
            // swatch - nothing in it can ever go "missing".
            Capsule()
                .fill(.clear)
                .background(
                    Image(backgroundImageName)
                        .resizable()
                        .scaledToFill()
                )
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.95, green: 0.8, blue: 0.4),
                                    Color(red: 0.78, green: 0.56, blue: 0.16),
                                    Color(red: 0.95, green: 0.8, blue: 0.4),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2.5
                        )
                )
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18))
        }
    }
}
