import SwiftUI

/// The in-game pause menu ("Game Menu": Resume / Restart / Main Menu) -
/// replaces a native `confirmationDialog`, which rendered as a plain
/// system action sheet and was the one piece of chrome in the whole game
/// that didn't match the painted gold-trim theme. Same `PopupCard` chrome
/// as `BuildPopupView`/`TradePopupView`/`DevCardPopupView`/
/// `DiscardPopupView` so it reads as one family with the rest of the app's
/// popups rather than a one-off style.
public struct PauseMenuView: View {
    public let onResume: () -> Void
    public let onRestart: () -> Void
    public let onMainMenu: () -> Void

    public init(onResume: @escaping () -> Void, onRestart: @escaping () -> Void, onMainMenu: @escaping () -> Void) {
        self.onResume = onResume
        self.onRestart = onRestart
        self.onMainMenu = onMainMenu
    }

    @State private var isConfirmingRestart = false
    @State private var isConfirmingMainMenu = false

    public var body: some View {
        // Tapping outside resumes, same as the old dialog's implicit
        // cancel - Resume is the only non-destructive way out.
        PopupCard(onDismiss: onResume) {
            if isConfirmingRestart {
                confirmation(
                    title: "Restart Game?",
                    message: "This throws away the current board and starts a brand new game.",
                    confirmTitle: "Restart",
                    onConfirm: onRestart,
                    onCancel: { isConfirmingRestart = false }
                )
            } else if isConfirmingMainMenu {
                confirmation(
                    title: "Quit to Main Menu?",
                    message: "Your progress is saved, so you can pick up this game again from Resume.",
                    confirmTitle: "Main Menu",
                    onConfirm: onMainMenu,
                    onCancel: { isConfirmingMainMenu = false }
                )
            } else {
                menu
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 14) {
            Text("Game Menu")
                .font(.headline)

            VStack(spacing: 10) {
                menuButton(title: "Resume", icon: "play.fill", isDestructive: false, action: onResume)
                menuButton(title: "Restart Game", icon: "arrow.counterclockwise", isDestructive: true) {
                    isConfirmingRestart = true
                }
                menuButton(title: "Main Menu", icon: "house.fill", isDestructive: true) {
                    isConfirmingMainMenu = true
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 280)
    }

    private func menuButton(title: String, icon: String, isDestructive: Bool, action: @escaping () -> Void) -> some View {
        GoldRowButton(
            title: title,
            systemImage: icon,
            iconColor: isDestructive ? .red : .white,
            titleColor: isDestructive ? .red : .white,
            action: action
        )
    }

    /// Shared layout for the two destructive actions' "are you sure" step -
    /// each one throws away something (the board, or leaves the game
    /// screen) that a stray tap on the main menu shouldn't do by accident.
    private func confirmation(title: String, message: String, confirmTitle: String, onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Stacked, not side-by-side - this 280pt-wide card is too narrow
            // to fit two `GoldRowButton`s' icon+title rows next to each
            // other without "Main Menu" wrapping (see chat).
            VStack(spacing: 10) {
                GoldRowButton(title: "Cancel", systemImage: "xmark", action: onCancel)
                GoldRowButton(title: confirmTitle, systemImage: "exclamationmark.triangle.fill", iconColor: .red, titleColor: .red, action: onConfirm)
            }
        }
        .padding(20)
        .frame(maxWidth: 280)
    }
}
