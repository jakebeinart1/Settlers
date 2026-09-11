import SwiftUI
import CatanEngine

/// Picks the rule set a new match is played under.
///
/// A popup rather than a row of chips leaves room to explain what each mode
/// changes and scales to the additional modes planned after Expanded.
struct GameModePickerPopup: View {
    let selection: GameMode
    let onSelect: (GameMode) -> Void
    let onCancel: () -> Void

    var body: some View {
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                Text("Game Mode")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .accessibilityIdentifier(AccessibilityID.NewGame.modePicker)
                ForEach(GameMode.allCases, id: \.rawValue) { mode in
                    Button { onSelect(mode) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mode.displayName)
                                    .font(.system(
                                        size: SeatCardView.bodyTextSize,
                                        weight: .semibold,
                                        design: .serif
                                    ))
                                Text(mode.summary)
                                    .font(.system(size: SeatCardView.bodyTextSize - 3, design: .serif))
                                    .foregroundStyle(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            if mode == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: SeatCardView.bodyTextSize, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier(AccessibilityID.NewGame.modeOption(mode))
                }
                GoldRowButton(title: "Close", systemImage: "xmark", action: onCancel)
            }
            .padding(16)
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    ZStack {
        SettingsChrome.screenBackground.ignoresSafeArea()
        GameModePickerPopup(selection: .classic, onSelect: { _ in }, onCancel: {})
    }
}
