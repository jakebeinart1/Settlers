import SwiftUI

/// Shared background treatment for the game's "painted plaque" chrome
/// pieces (action buttons, dice chip, bank/dev-card chip): a repeating
/// painted texture fill, clipped to a `RoundedRectangle`, with the gold
/// border drawn natively rather than baked into the texture image, plus a
/// thin inset dark-red accent line just inside it (matching the hairline
/// the reference art uses on its own painted frames).
///
/// The gold+red border used to be part of the image itself - see
/// `UniformActionButton`'s and `GameView.diceChip`'s git history / the
/// "Aug 21 button-border pivot" and "Aug 21 dice-chip border evenness"
/// notes in `design-references/STATUS.md`. A baked-in border only crops
/// evenly when the image's own aspect ratio happens to match the
/// container's real on-screen aspect closely - every single painted-frame
/// chip in this app has needed a second pass once its container's actual
/// proportions were checked for real, so this is now the default way to
/// build one of these instead of something to reach for after the fact.
struct PaintedChromeBackground: View {
    /// Asset name of a *borderless* repeating texture swatch - a plain
    /// crop of the interior of the original painted frame art, well clear
    /// of any border pixels (`dice-fill`, `bank-fill`, `button-fill-*`).
    let textureImageName: String
    let cornerRadius: CGFloat

    private static let gold = LinearGradient(
        colors: [
            Color(red: 0.95, green: 0.8, blue: 0.4),
            Color(red: 0.78, green: 0.56, blue: 0.16),
            Color(red: 0.95, green: 0.8, blue: 0.4),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
    /// Sampled from the original `dice-frame.png` generation's own inset
    /// accent line (a dark maroon, not a bright/saturated red) rather than
    /// picked by eye, so it matches what the reference style already
    /// established.
    private static let innerRed = Color(red: 0.4, green: 0.04, blue: 0.02)

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.clear)
            .background(
                Image(textureImageName)
                    .resizable()
                    .scaledToFill()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Self.gold, lineWidth: 1.25)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .inset(by: 1.25)
                    .strokeBorder(Self.innerRed, lineWidth: 1.75)
            )
    }
}
