import CatanEngine
import SwiftUI

/// Difficulty selects a separate competition, rather than changing any game.
struct PlayerRatingTierPicker: View {
    let selection: BotDifficulty
    let onSelect: (BotDifficulty) -> Void
    let onCancel: () -> Void
    @AccessibilityFocusState private var isHeadingFocused: Bool

    var body: some View {
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                Text("Choose an opponent")
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isHeadingFocused)
                ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                    GoldRowButton(title: "\(difficulty.displayName) AI", systemImage: "shield",
                                  iconColor: SettingsChrome.ornamentGold,
                                  fill: difficulty == selection ? .tintedTexture(SettingsChrome.selectedOptionFill)
                                      : .color(SettingsChrome.plaqueFill)) { onSelect(difficulty) }
                        .accessibilityAddTraits(difficulty == selection ? [.isSelected] : [])
                        .accessibilityIdentifier("ratings.difficulty.\(difficulty.rawValue)")
                }
                GoldRowButton(title: "Cancel", systemImage: "xmark", action: onCancel)
                    .accessibilityIdentifier("ratings.tier-cancel")
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(16)
            .frame(maxWidth: 366)
            .foregroundStyle(.white)
            .fontDesign(.serif)
        }
        .padding(.vertical, 16)
        .accessibilityAddTraits(.isModal)
        .onAppear { isHeadingFocused = true }
    }
}
