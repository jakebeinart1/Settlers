import SwiftUI

/// The same painted popup as the game's other choices. Its ordinary five
/// modes hug their content; large text and retained legacy modes get a bounded
/// scrolling middle while the title and Cancel stay reachable.
struct PlayerRatingModePicker: View {
    let options: [RatingPool]
    let selection: RatingPool
    let onSelect: (RatingPool) -> Void
    let onCancel: () -> Void

    @AccessibilityFocusState private var isHeadingFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            PopupCard(onDismiss: onCancel) {
                ViewThatFits(in: .vertical) {
                    panel(scrolling: false, maxHeight: nil)
                    panel(scrolling: true, maxHeight: max(240, geometry.size.height - 48))
                }
            }
            .padding(.vertical, 16)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear { isHeadingFocused = true }
    }

    private func panel(scrolling: Bool, maxHeight: CGFloat?) -> some View {
        VStack(spacing: 14) {
            Text("Choose a mode")
                .font(.system(.title3, design: .serif, weight: .bold))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeadingFocused)
            if scrolling {
                ScrollView { rows }.scrollIndicators(.visible)
                    .background(RatingViewportMarker(identifier: "ratings.mode-options-frame"))
            } else {
                rows.background(RatingViewportMarker(identifier: "ratings.mode-options-frame"))
            }
            GoldRowButton(title: "Cancel", systemImage: "xmark", action: onCancel)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("ratings.mode-cancel")
        }
        .padding(16)
        .frame(maxWidth: 366, maxHeight: maxHeight)
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .background(RatingViewportMarker(identifier: "ratings.mode-frame"))
    }

    private var rows: some View {
        VStack(spacing: 10) {
            ForEach(options) { option in row(option) }
        }
    }

    /// The label gets the whole row. A growing map glyph and checkmark used
    /// to consume its width and split "Classic" in half at large text sizes.
    private func row(_ option: RatingPool) -> some View {
        let selected = option.mode == selection.mode && option.variant == selection.variant
        return Button { onSelect(option) } label: {
            HStack(spacing: 8) {
                Text(option.displayName)
                    .font(.system(.body, design: .serif, weight: selected ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold))
                    .frame(width: 22).opacity(selected ? 1 : 0).accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(PaintedChromeBackground(
                fill: selected ? .tintedTexture(SettingsChrome.selectedOptionFill) : .color(SettingsChrome.plaqueFill),
                cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("ratings.mode.\(option.mode.rawValue).\(option.variant.rawValue)")
    }
}
