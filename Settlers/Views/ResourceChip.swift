import SwiftUI
import CatanEngine

/// Shared "resource chip" button - a resource-colored rounded square with the
/// count printed underneath - used by every give/want/discard-style popup so
/// their rows look and behave the same.
///
/// ## Squares, never the painted hex art
/// Twice now these have been swapped for the gold-rimmed hexagon commodity
/// art, on the argument that a picture reads
/// without learning the colour key. Jake has rejected that both times
/// (2026-10-06: "keep the squares and never revert to the hexes with the
/// small icons"). The squares match `PlayerHUDView.resourceDot`, the bank
/// row and the board, so one colour means one resource everywhere in the
/// game. Spoken names come from `accessibilityText`, not from art. The hex
/// art itself was deleted from the asset catalog on 2026-10-09 after it
/// resurfaced a third time in the Build popup, so it cannot come back.
struct ResourceChip: View {
    let resource: Resource
    let count: Int?
    var isEnabled: Bool = true
    /// A gold ring around the square: this card is actually part of the offer.
    var isSelected: Bool = false
    var size: CGFloat = ResourceChip.defaultSize
    let action: () -> Void

    /// Bigger than the 18pt swatch `PlayerHUDView.resourceDot` uses on the
    /// board - these are tap targets, not a read-only glance. 32pt keeps the
    /// same silhouette while five still fit across the narrowest phone.
    static let defaultSize: CGFloat = 32

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ResourceSquare(resource: resource, size: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(CatanTheme.chipGold, lineWidth: isSelected ? 3 : 0)
                    )
                // Reserves the same line whether or not there is a count, so
                // a bare-palette chip and a counted one sit at one height.
                Text(count.map { "\($0)" } ?? "0")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CatanTheme.onWaterText)
                    .opacity(count == nil ? 0 : (isEnabled || isSelected ? 1 : 0.4))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        // Never fade the square itself: a translucent swatch takes on the
        // panel behind it and stops matching the board's resource colour.
        // `.plain` dims a disabled label, so this style draws it as-is.
        .buttonStyle(UndimmedButtonStyle())
        .accessibilityLabel(Text(accessibilityText))
        .disabled(!isEnabled)
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

/// Draws a button's label as-is when disabled; resource squares must keep
/// their exact colour. Callers dim text themselves.
struct UndimmedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The one drawing of "a resource" outside the board: a flat square in
/// `CatanTheme.color(for:)`. Trade terms, dev-card choices and dev-card
/// emblems all use this, so a colour reads the same on every screen.
struct ResourceSquare: View {
    let resource: Resource
    var size: CGFloat = ResourceChip.defaultSize

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.125)
            .fill(CatanTheme.color(for: resource))
            .frame(width: size, height: size)
        // No accessibilityHidden: a shape is never an element on its own, and
        // hiding it inside a `.combine` row made XCUITest find the row twice.
    }
}

/// Resource words inside a sentence, each with its colour square beside the
/// name ("3 ■ Wool"). Jake reads resources by colour first (2026-10-06), so
/// every sentence that names a resource - trades, steals, Monopoly - draws
/// the square too. An inline glyph, not a view, so it wraps with the text.
enum ResourceText {
    static func term(_ resource: Resource, count: Int? = nil) -> Text {
        let square = Text(Image(systemName: "square.fill")).foregroundStyle(CatanTheme.color(for: resource))
        return Text(count.map { "\($0) " } ?? "") + square + Text(" \(resource.rawValue.capitalized)")
    }

    static func list(_ counts: [Resource: Int], separator: String = ", ") -> Text {
        let terms = Resource.allCases.filter { counts[$0, default: 0] > 0 }.map { term($0, count: counts[$0]) }
        guard let first = terms.first else { return Text("no cards") }
        return terms.dropFirst().reduce(first) { $0 + Text(separator) + $1 }
    }
}
