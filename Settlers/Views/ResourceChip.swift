import SwiftUI
import CatanEngine

/// Shared "resource chip" button - a resource-colored rounded square with the
/// count printed underneath - used by every give/want/discard-style popup
/// (`TradePopupView`, `DiscardPopupView`, `DevCardPopupView`'s
/// Monopoly/Year of Plenty picker) so their trays and slots look and behave
/// the same.
///
/// ## Why this is a flat square again, not painted hex art
/// It spent a while as painted resource-card artwork (bricks, a sheaf of
/// wheat, ...) on a gold-rimmed hexagon, specifically so a new player could
/// identify a resource without already knowing "grey means ore." That
/// tradeoff is a real one - a flat color square asks the player to have
/// learned the mapping - but Jake asked for it back explicitly: these
/// popups should match the resource squares already on the board itself
/// (`PlayerHUDView.resourceDot`, the human's own hand row), not introduce a
/// second, different-shaped vocabulary for what is the same information.
/// Consistency with the one row the player checks every turn won this over
/// the new-player-legibility case for these transient pickers.
///
/// The count sits below the square as its own `Text`, matching
/// `resourceDot` exactly, rather than a corner badge - a badge was needed
/// only to stay legible over painted artwork; over a flat color it is not,
/// and matching the board's own layout is the point.
struct ResourceChip: View {
    let resource: Resource
    let count: Int?
    var isEnabled: Bool = true
    /// A gold ring around the square. Marks a card that is actually part of
    /// the offer, which is what distinguishes a staged slot row from the
    /// palette below it - the rows are otherwise the same five cards.
    ///
    /// A stroked outline was rejected once before, on the painted-hex
    /// version, because the art's hexagon didn't stay in register with a
    /// drawn hex path. That problem is gone now that the shape being
    /// stroked is the `RoundedRectangle` actually being drawn, not
    /// artwork inset inside one - so a plain stroke is the simplest thing
    /// that works.
    var isSelected: Bool = false
    var size: CGFloat = ResourceChip.defaultSize
    let action: () -> Void

    /// Bigger than the 18pt swatch `PlayerHUDView.resourceDot` uses on the
    /// board - these are tap targets, not a read-only glance, and 18pt is
    /// well under Apple's comfortable-touch guidance. 32pt keeps the same
    /// silhouette while staying under the 49.4pt-per-chip ceiling a
    /// five-across row has on the narrowest phone this ships to (see the
    /// arithmetic this replaced, in git history of this file, for how that
    /// ceiling was measured).
    static let defaultSize: CGFloat = 32

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(CatanTheme.color(for: resource))
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(CatanTheme.chipGold, lineWidth: isSelected ? 3 : 0)
                    )
                // Reserves the same line whether or not there is a count,
                // via a non-empty placeholder held at zero opacity - so a
                // bare-palette chip (`count: nil`) and a counted one sit at
                // identical heights in the same row instead of the row's
                // baseline jumping card to card.
                Text(count.map { "\($0)" } ?? "0")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CatanTheme.onWaterText)
                    .opacity(count == nil ? 0 : 1)
            }
            .accessibilityLabel(Text(accessibilityText))
        }
        .disabled(!isEnabled)
        // Gentle: a heavily faded card takes on the blue behind it. A card you
        // cannot tap still has to be readable, because reading it is how you
        // learn you hold none.
        .opacity(isEnabled ? 1 : 0.6)
    }

    /// Spoken form - VoiceOver reads the color square as decorative
    /// otherwise, so the resource name has to come from here.
    private var accessibilityText: String {
        let name = resource.rawValue.capitalized
        guard let count else { return name }
        return "\(count) \(name)"
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
                // No badge at all when nothing is staged, matching the bank
                // rows. Stamping "0" on five cards directly above the hand row
                // made the staged rows read as a claim about the hand.
                ResourceChip(resource: resource, count: staged > 0 ? staged : nil,
                             isEnabled: staged > 0, isSelected: staged > 0) {
                    onTap(resource)
                }
            }
        }
    }
}
