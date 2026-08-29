import SwiftUI

/// Full-width row button for popups/menus (`PauseMenuView`, `BuildPopupView`,
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
    let title: String
    var subtitle: String?
    let systemImage: String
    var iconColor: Color = .white
    var titleColor: Color = .white
    var isEnabled: Bool = true
    @ViewBuilder var trailing: () -> Trailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.callout)
                    .foregroundStyle(iconColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(titleColor)
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
            .background(
                PaintedChromeBackground(fill: .color(Color(white: 0.18)), cornerRadius: 10)
            )
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
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
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            iconColor: iconColor,
            titleColor: titleColor,
            isEnabled: isEnabled,
            trailing: { EmptyView() },
            action: action
        )
    }
}
