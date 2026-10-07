import SwiftUI

/// Full-width row button for popups/menus (`InGameSettingsView`, `BuildPopupView`,
/// `TradePopupView`, `DevCardPopupView`, `MainMenuView`): the same
/// `PaintedChromeBackground` gold-hairline border/notched-corner chrome as
/// `UniformActionButton` in the bottom action row, but laid out as a
/// horizontal row (icon, title/subtitle, optional trailing content) instead
/// of an icon-over-title tile - popup rows need to show a resource cost, an
/// accept/decline pair, or just a plain menu label, none of which fit the
/// tile shape.
///
/// Uses `PaintedChromeBackground`'s flat-color fill rather than a painted
/// texture - unlike Trade/Build/turn-action, there's no small fixed set of
/// popup rows to paint a texture per label for (every screen this covers
/// would need its own asset), so every row shares one plain dark plaque and
/// leans on `iconColor`/`titleColor` for whatever distinction a screen wants
/// (building-type colors in Build, red for destructive actions, etc.) -
/// see the "keep a colored icon/accent, gold plaque background" design
/// decision in chat.
struct GoldRowButton<Trailing: View>: View {
    @ScaledMetric(relativeTo: .callout) private var iconPointSize = 17.0
    let title: String
    var subtitle: String?
    let systemImage: String
    var iconColor: Color = .white
    var titleColor: Color = .white
    var isEnabled: Bool = true
    /// The plaque's interior. Defaults to the flat dark swatch every popup row
    /// has always used, so no existing call site changes; `InGameSettingsView`
    /// tints its three Game Control rows (green resume, blue restart, red
    /// quit) so the destructive one is distinguishable at a glance rather than
    /// only by the colour of a 16pt glyph.
    var fill: PaintedChromeBackground.Fill = .color(Color(white: 0.18))
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: min(44, iconPointSize)))
                    .foregroundStyle(iconColor.opacity(isEnabled ? 1 : 0.6))
                    // Reserve the space the enlarged symbol actually draws in.
                    // A fixed 22pt column let large-text symbols overlap labels.
                    .frame(width: max(22, min(44, iconPointSize)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(titleColor.opacity(isEnabled ? 1 : 0.85))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .background(
                PaintedChromeBackground(fill: fill, cornerRadius: 10)
            )
        }
        .buttonStyle(GoldRowButtonStyle())
        .disabled(!isEnabled)
    }
}

/// PlainButtonStyle fades a disabled label including its plaque. Keeping the
/// painted background opaque preserves contrast against a bright modal card.
private struct GoldRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.9 : 1)
    }
}

extension GoldRowButton where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconColor: Color = .white,
        titleColor: Color = .white,
        isEnabled: Bool = true,
        fill: PaintedChromeBackground.Fill = .color(Color(white: 0.18)),
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            iconColor: iconColor,
            titleColor: titleColor,
            isEnabled: isEnabled,
            fill: fill,
            trailing: { EmptyView() },
            action: action
        )
    }
}
