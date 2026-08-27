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
            // `maxHeight: .infinity` (below) - lets this button visually
            // grow (background/border included, icon+text staying
            // centered) to fill whatever height its container gives it,
            // rather than always sitting at its own natural ~49pt with
            // empty space left around it. `GameView.actionRow` floors its
            // own row height to match the tallest robber-flow state
            // (`robberTargetingPanel`'s "Steal from:" step) so the board
            // never resizes across that flow - without this, that floor
            // just showed as dead gap under otherwise-normal-sized buttons
            // (see chat: Jake wanted the buttons themselves bigger and
            // flush, not padding).
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.title2)
                    // Fixed height, not just the font's natural size - SF
                    // Symbols aren't all drawn to the same optical height at
                    // a given point size (e.g. "die.face.5.fill" renders
                    // shorter than "hammer.fill" or "arrow.left.arrow.right"
                    // at `.title2`), so without this the Roll Dice button's
                    // whole VStack - and so the whole button, background
                    // included - came out visibly shorter than Trade/Build
                    // just from using a different icon.
                    .frame(height: 26)
                Text(title)
                    .font(.footnote.bold())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 6)
            .background(background)
            .foregroundStyle(.white)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }

    @ViewBuilder
    private var background: some View {
        if let backgroundImageName {
            // See `PaintedChromeBackground` - the gold (+ thin inset red)
            // border is drawn natively there, not baked into the image, so
            // it's correct at any aspect ratio by construction. A fixed
            // corner radius (not `Capsule`, which reads as a full oval/pill
            // rather than a button) matches the squared-off look of the
            // rest of this app's chrome.
            //
            // `isArmed` (Roll Dice's pulsing glow) used to swap this whole
            // painted-plaque background out for a plain `RoundedRectangle`
            // yellow tint - that dropped the notched border/texture Roll
            // Dice otherwise shares with Trade/Build/End Turn, so armed and
            // unarmed read as two different button styles. Layering the
            // glow on top (clipped to the same notched shape the border
            // itself traces) instead keeps the painted-plaque look and adds
            // the highlight, rather than replacing one with the other.
            PaintedChromeBackground(textureImageName: backgroundImageName, cornerRadius: 10)
                .overlay {
                    if isArmed {
                        FrameCornerRect(cornerRadius: 10)
                            .fill(Color.yellow.opacity(0.35))
                    }
                }
        } else if isArmed {
            RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.35))
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.18))
        }
    }
}
