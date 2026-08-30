import SwiftUI
import CatanEngine

/// Shared "resource chip" button - the painted resource card, with an optional
/// count badge - used by every give/want/discard-style popup
/// (`TradePopupView`, `DiscardPopupView`, `DevCardPopupView`'s
/// Monopoly/Year of Plenty picker) so their trays and slots look and behave
/// the same.
///
/// ## Why this stopped being a colored square
/// It used to be a flat `RoundedRectangle` filled with
/// `CatanTheme.color(for:)` and nothing else - no icon, no name - on the
/// reasoning that "the color alone is the app's one consistent way to identify
/// a resource". That reasoning only holds for someone who already knows the
/// mapping. A new player looking at a grey square and an olive square has no
/// way to learn that one is ore and the other is wool, and the trade popup -
/// where you are being asked to give something away - is the worst place in
/// the app to have to guess.
///
/// It also made the popups look nothing like the board they sit on top of,
/// which is fully painted.
///
/// The count is a corner badge rather than centred text so it stays legible
/// over artwork and does not cover the thing it is counting - and so a
/// two-digit hand does not have to shrink the number to fit.
struct ResourceChip: View {
    let resource: Resource
    let count: Int?
    var isEnabled: Bool = true
    /// Lit with a gold glow. Marks a card that is actually part of the offer,
    /// which is what distinguishes a staged slot row from the palette below
    /// it - the rows are otherwise the same five cards.
    var isSelected: Bool = false
    var size: CGFloat = ResourceChip.defaultSize
    let action: () -> Void

    /// Big enough that the painted art is readable rather than a smudge. The
    /// old flat squares were 36pt, which is fine for a solid colour and far
    /// too small for a sheaf of wheat.
    static let defaultSize: CGFloat = 52

    var body: some View {
        Button(action: action) {
            Image(CatanTheme.iconImageName(for: resource))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .overlay(alignment: .bottomTrailing) {
                    if let count {
                        CountBadge(count: count, diameter: size * 0.42)
                            .offset(x: size * 0.04, y: size * 0.02)
                    }
                }
                // A glow, not a ring. A drawn outline has to stay in register
                // with the artwork's own hexagon, and it did not: the art is a
                // flat-top hexagon inset inside a square image, so a hexagon
                // path fitted to the frame sat visibly rotated against it. A
                // shadow follows the alpha channel, so it traces whatever
                // shape the art actually is and cannot drift out of register.
                .shadow(color: isSelected ? CatanTheme.chipGold : .clear, radius: 5)
                .shadow(color: isSelected ? CatanTheme.chipGold.opacity(0.7) : .clear, radius: 10)
                // Cards are never dimmed or desaturated to say "you have none
                // of these" - the count badge already says it, and every way of
                // fading tried here failed on this popup's saturated blue
                // ground: transparency tinted the card blue, and darkening
                // turned brick a muddy purple. Full colour, always; the badge
                // carries the number.
                .accessibilityLabel(Text(accessibilityText))
        }
        .disabled(!isEnabled)
        // Gentle: a heavily faded card takes on the blue behind it. A card you
        // cannot tap still has to be readable, because reading it is how you
        // learn you hold none.
        .opacity(isEnabled ? 1 : 0.6)
    }

    /// Spoken form, because the art carries the meaning visually and
    /// VoiceOver would otherwise read an image filename.
    private var accessibilityText: String {
        let name = resource.rawValue.capitalized
        guard let count else { return name }
        return "\(count) \(name)"
    }
}

/// The little dark disc a chip's count sits in.
///
/// Its own type because it is drawn over painted artwork of five different
/// dominant colours, so it needs an opaque ground and a rim of its own to stay
/// readable - plain white text directly on the art fails over wheat gold.
private struct CountBadge: View {
    let count: Int
    let diameter: CGFloat

    var body: some View {
        Text("\(count)")
            .font(.system(size: diameter * 0.62, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(Color(red: 0.06, green: 0.09, blue: 0.13)))
            .overlay(Circle().strokeBorder(CatanTheme.chipGold.opacity(0.85), lineWidth: diameter * 0.07))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
    }
}

/// One slot row (Give/Want/Discard): all five resources, each showing how many
/// of it are currently staged. Tap one to take a unit back out.
///
/// ## Why all five, rather than only what is in the slot
/// It used to render just the staged resources, with a line of placeholder
/// text ("Tap a card from your hand below") while the slot was empty. Two
/// problems. The row was a different width on every change, so cards moved
/// under the finger as they were added. And an empty slot spent a full chip's
/// height on a sentence, which is most of why the top of the trade popup read
/// as blank space.
///
/// Showing the whole set, greyed at zero, makes the row a fixed shape that
/// fills in place - and answers "what could go here" without a sentence.
struct ResourceSlotRow: View {
    let counts: [Resource: Int]
    let onTap: (Resource) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                let staged = counts[resource] ?? 0
                ResourceChip(resource: resource, count: staged,
                             isEnabled: staged > 0, isSelected: staged > 0) {
                    onTap(resource)
                }
            }
        }
    }
}
