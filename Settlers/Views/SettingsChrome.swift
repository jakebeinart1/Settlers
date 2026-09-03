import SwiftUI

/// The painted chrome the settings surfaces are built from: an ornamented
/// section header, an info plaque, a segmented choice row, and a confirmation
/// card.
///
/// Factored out of `InGameSettingsView` because the same pieces are what
/// any settings surface in this app needs, and because the alternative is what
/// `SettingsView` currently is - a screen assembled from system controls that
/// renders grey-on-grey and is the one screen in the app that does not look
/// like the rest of it. `Picker`, `Form`, `List` and `.segmented` are
/// deliberately absent from this file: none of them can be given the painted
/// gold-hairline treatment `PaintedChromeBackground` draws, and every attempt
/// to restyle them has ended up fighting the system's own rendering.
enum SettingsChrome {
    /// The warm gold of the reference art's engraved section rules and title
    /// ornaments. Distinct from `CatanTheme.cityPennantGold` (a board flag,
    /// pushed more yellow so it reads at hex size) and from
    /// `PaintedChromeBackground.gold` (a gradient for a 1.25pt border, too
    /// light in its mid-stop to carry a word of text).
    static let ornamentGold = Color(red: 0.89, green: 0.63, blue: 0.22)

    /// Fill of the segmented control's selected option - satin gold
    /// (`#D4AF37`), dark enough that near-white text on top of it still
    /// reads. Went through two wrong swatches, both Jake's ask, 2026-09-03:
    /// a bronze (0.68/0.49/0.10) that read as brown - low blue, low
    /// luminance, pulled it toward wood/leather - and then `ornamentGold`
    /// itself (0.89/0.63/0.22), which still read as orange rather than gold
    /// because its green channel sits too far below red (G/R = 0.71). Gold
    /// wants green much closer to red - `#D4AF37`'s G/R is 0.83 - so this
    /// value is its own constant rather than reusing `ornamentGold`, which
    /// stays as-is for headers/hairlines/borders where nobody has flagged it.
    /// The wave texture is blended over it at 60% in `.overlay` mode, which
    /// pulls the rendered result about a third darker than the flat swatch.
    static let selectedOptionFill = Color(red: 0.831, green: 0.686, blue: 0.216)

    /// Fill of the plaques on these screens: darker than `Color(white: 0.18)`
    /// (the popup rows' swatch) so the gold hairline around it is the brightest
    /// thing on the row, as it is in the reference.
    static let plaqueFill = Color(red: 0.06, green: 0.11, blue: 0.19)

    /// The deep navy the settings surfaces sit on.
    static let screenBackground = Color(red: 0.047, green: 0.102, blue: 0.180)
}

/// A section title with a hairline rule running out to both edges - the
/// reference art's chapter-heading treatment, minus the diamond ornaments
/// that used to flank the title (Jake's ask, 2026-09-03: removed from both
/// this header and the two screens' own title ornaments, on New Game Setup
/// and In-Game Settings).
struct SettingsSectionHeader: View {
    let title: String
    /// Gold by default; New Game Setup's "Players & Civilizations" and
    /// "Match Settings" pass `.white` (Jake's ask, 2026-09-03). Per-call
    /// rather than a global change to `ornamentGold`, since In-Game
    /// Settings' section titles (Pacing, Trade Offer Timer, Game Control)
    /// were not part of that ask.
    var titleColor: Color = SettingsChrome.ornamentGold

    var body: some View {
        HStack(spacing: 8) {
            rule
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .serif))
                .foregroundStyle(titleColor)
                .fixedSize()
            rule
        }
    }

    /// `maxWidth: .infinity` on both rules, so the title sits centred and the
    /// two rules divide whatever is left evenly however long the title is.
    private var rule: some View {
        Rectangle()
            .fill(SettingsChrome.ornamentGold.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 1)
    }
}

/// A non-interactive plaque carrying one line of standing context - on the
/// in-game surface, the promise that nothing on the screen touches the rules
/// (spec B4). A plaque rather than a bare caption because the claim is the
/// screen's contract with the player and should read as part of its chrome.
struct SettingsInfoPlaque: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(SettingsChrome.ornamentGold)
            Text(text)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.6))
    }
}

/// The "are you sure" step in front of an action that throws something away.
///
/// Lifted verbatim out of `PauseMenuView.confirmation` when that view was
/// absorbed into `InGameSettingsView`, and kept as a shared component rather
/// than copied because there is a second caller coming: starting a new game
/// while one is saved destroys the save, and must warn first. Two hand-copied
/// confirmations drift, and the one that drifts is the one nobody reads.
///
/// The buttons are stacked, not side by side: this 280pt-wide card is too
/// narrow to fit two `GoldRowButton`s' icon+title rows next to each other
/// without a title as long as "Main Menu" wrapping. Cancel is first and
/// non-destructive; the confirming action is red.
struct ConfirmationPopupCard: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmIdentifier: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(
        title: String,
        message: String,
        confirmTitle: String,
        confirmIdentifier: String? = nil,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.confirmIdentifier = confirmIdentifier
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        // Tapping outside cancels - the non-destructive way out, matching
        // every other `PopupCard` in the app.
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    GoldRowButton(title: "Cancel", systemImage: "xmark", action: onCancel)
                    GoldRowButton(title: confirmTitle, systemImage: "exclamationmark.triangle.fill",
                                  iconColor: .red, titleColor: .red, action: onConfirm)
                        .accessibilityIdentifier(confirmIdentifier ?? "")
                }
            }
            .padding(20)
            .frame(maxWidth: 280)
        }
    }
}

/// A segmented choice over a small named set: one painted plaque divided into
/// equal-width options, the selected one filled with painted gold.
///
/// ## Why equal widths, and the 375pt arithmetic
/// Every option gets `maxWidth: .infinity`, so the widest label never pushes
/// the others around and the control's own width is whatever the screen gives
/// it. The tightest case in the app is the four-option trade timer on a 375pt
/// screen (iPhone SE / 13 mini, which the simulator's 402pt iPhone 17 does not
/// exercise): 375 - 2 x 20pt screen padding = 335pt, divided four ways = 83.7pt
/// per option. "No Limit" at 15pt serif measures ~58pt, leaving ~12pt of
/// breathing room each side. `minimumScaleFactor` is the backstop for a larger
/// Dynamic Type setting rather than the mechanism - the layout is meant to fit
/// at 1x.
struct PaintedChoiceRow<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    let selection: Option
    /// Tighter vertical padding, for screens that have to fit many of these.
    var isCompact: Bool = false
    /// Overrides `isCompact`'s fixed 6pt/13pt when a caller needs to match
    /// another control's height exactly - `SeatCardView`'s Human/AI row
    /// passes the civilization row's own padding here so the two boxes come
    /// out the same height (Jake's ask, 2026-09-03).
    var verticalPadding: CGFloat?
    /// Overrides the fixed 15pt option text size - `SeatCardView`'s Human/AI
    /// row passes its own `bodyTextSize` here so that text is guaranteed
    /// identical to every other label on the card rather than coincidentally
    /// matching a hardcoded value here (Jake's ask, 2026-09-03).
    var fontSize: CGFloat = 15
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { divider }
                optionButton(option)
            }
        }
        .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10, notchScale: 0.6))
    }

    private func optionButton(_ option: Option) -> some View {
        let isSelected = option == selection
        return Button {
            onSelect(option)
        } label: {
            Text(title(option))
                .font(.system(size: fontSize, weight: isSelected ? .bold : .regular, design: .serif))
                .foregroundStyle(isSelected ? Color(white: 0.98) : Color.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                // 13 suits the In-Game Settings screen, which holds two of
                // these on a mostly empty page. The New Game screen holds ten
                // and has to fit the whole configuration above the fold, so it
                // asks for the compact height.
                .padding(.vertical, verticalPadding ?? (isCompact ? 6 : 13))
                .background {
                    if isSelected {
                        // Inset by a point so this chip's own gold hairline sits
                        // just inside the enclosing plaque's rather than
                        // overprinting it, which reads as one thick smudged edge.
                        PaintedChromeBackground(
                            fill: .tintedTexture(SettingsChrome.selectedOptionFill),
                            cornerRadius: 9,
                            notchScale: 0.5
                        )
                        .padding(1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var divider: some View {
        Rectangle()
            .fill(SettingsChrome.ornamentGold.opacity(0.30))
            .frame(width: 1)
            .padding(.vertical, 7)
    }
}
