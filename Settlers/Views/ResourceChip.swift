import SwiftUI
import CatanEngine

/// Shared resource button. Existing pickers keep their compact swatch;
/// the trade composer opts into named commodity artwork because an exchange
/// must be understandable without memorizing the HUD's five-color key.
struct ResourceChip: View {
    enum Appearance { case swatch, illustrated }

    let resource: Resource
    let count: Int?
    var isEnabled: Bool = true
    /// Selection rims the actual button surface, never a hand-drawn hex that
    /// could drift out of register with the resource art's painted border.
    var isSelected: Bool = false
    var size: CGFloat = ResourceChip.defaultSize
    var appearance: Appearance = .swatch
    var accent: Color = CatanTheme.chipGold
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
            chipContent
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityText))
        .disabled(!isEnabled)
        // Identity and staged quantity stay readable even when adding is blocked.
        .opacity(isEnabled || (appearance == .illustrated && isSelected) ? 1 : 0.6)
    }

    @ViewBuilder
    private var chipContent: some View {
        switch appearance {
        case .swatch:
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
        case .illustrated:
            illustratedContent
        }
    }

    private var illustratedContent: some View {
        VStack(spacing: 2) {
            Image(CatanTheme.iconImageName(for: resource))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
            Text(resource.rawValue.capitalized)
                .font(.system(size: 11, weight: .semibold, design: .serif))
                .foregroundStyle(CatanTheme.onWaterText)
            HStack(spacing: 4) {
                Text("\(count ?? 0)").monospacedDigit()
                Image(systemName: "plus.circle.fill")
                    .opacity(isEnabled ? 1 : 0.35)
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(isSelected ? accent.opacity(0.13) : Color.black.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(accent.opacity(isSelected ? 0.8 : 0.22)))
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
    var actionHint = "Remove one selected card"
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
                .accessibilityHidden(staged == 0)
                .accessibilityHint(actionHint)
            }
        }
    }
}
