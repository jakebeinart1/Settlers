import SwiftUI

/// Surface B of the settings spec: what the player can change *about a game
/// already in progress*, plus the three ways out of it.
///
/// Replaces `PauseMenuView`, which was Resume / Restart / Main Menu and
/// nothing else. The two pacing controls above them used to be numbers in a
/// bundled `pacing.yml` - read-only on iOS, so developer-configurable and not
/// player-configurable (see `PacingPreferences` for what went and why).
///
/// ## What is deliberately absent
/// Nothing here changes a rule, a participant or the win condition (B4): seat
/// composition, names, civilizations, the victory target and the board type
/// are all match contract and belong to New Game Setup. Changing any of them
/// mid-game either does nothing, which is confusing, or corrupts the game in
/// progress, which is worse. If the player wants a different match, that is
/// the Restart row.
///
/// ## Why a full screen and not a `PopupCard`
/// Every other popup in this app is a card over the board because it is a step
/// in a move - pick a resource, answer an offer. This is not part of a move,
/// it is a place you go, and it carries five controls and three destructive
/// actions. The two confirmations it raises *are* `PopupCard`s, layered over
/// this screen, so the "are you sure" step still reads as the same family of
/// popup as everywhere else in the app.
///
/// ## Why no system controls
/// No `Picker`, `Form`, `List` or `.segmented` - they render grey-on-grey
/// against this palette and cannot take the painted gold-hairline treatment.
/// The painted equivalents live in `SettingsChrome`.
public struct InGameSettingsView: View {
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
    /// Which row's ⓘ is currently expanded, or `nil`. One at a time: these
    /// explanations are a sentence each and two open at once just pushes the
    /// Game Control rows off the screen.
    @State private var openHelp: HelpTopic?

    private enum HelpTopic {
        case aiTurnSpeed
        case incomingOfferTimer
    }

    /// Horizontal inset for the whole screen. 20pt each side leaves 335pt of
    /// content on a 375pt iPhone SE / 13 mini - the width the four-option
    /// timer row is sized against (see `PaintedChoiceRow`).
    private static let screenInset: CGFloat = 20

    public var body: some View {
        ZStack {
            SettingsChrome.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 22) {
                        titleBlock
                        SettingsInfoPlaque(text: "These settings do not change match rules.")
                        pacingSection
                        tradeTimerSection
                        gameControlSection
                    }
                    .padding(.horizontal, Self.screenInset)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                bottomBar
            }

            if isConfirmingRestart { restartConfirmation }
            if isConfirmingMainMenu { mainMenuConfirmation }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.inGameSettings)
        .foregroundStyle(.white)
        // Serif everywhere, matching the board screen's painted-book type.
        .fontDesign(.serif)
    }

    // MARK: - Title

    /// No flanking diamond ornaments - Jake's ask, 2026-09-03, along with the
    /// matching ornament on `NewGameSetupView`'s title and both screens'
    /// section headers.
    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("In-Game Settings")
                .font(.system(size: 29, weight: .bold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Adjust presentation and control the current game.")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Pacing (B1)

    /// B1.1-B1.4. The row writes straight through to `PacingPreferences` on
    /// tap - there is no Apply step, because every read site reads the
    /// singleton at the moment it needs a value, so the next bot action
    /// already uses the new speed (B1.2).
    private var pacingSection: some View {
        VStack(spacing: 14) {
            SettingsSectionHeader(title: "Pacing")
            choiceRow(
                label: "AI Turn Speed",
                help: .aiTurnSpeed,
                helpText: "How long each AI action is held on screen so you can see what it did. It changes nothing about how the bots play, or who wins."
            ) {
                PaintedChoiceRow(
                    options: AITurnSpeed.allCases,
                    title: \.displayName,
                    selection: PacingPreferences.shared.aiTurnSpeed,
                    onSelect: { PacingPreferences.shared.select($0) }
                )
            }
        }
    }

    // MARK: - Trade offer timer (B2)

    /// B2.1-B2.2. Separate from pacing on purpose: wanting fast bots is not
    /// consent to be auto-declined, so the two are never one control.
    private var tradeTimerSection: some View {
        VStack(spacing: 14) {
            SettingsSectionHeader(title: "Trade Offer Timer")
            choiceRow(
                label: "Incoming Offer Timer",
                help: .incomingOfferTimer,
                helpText: "How long you get to answer a trade offer before it is declined for you. Nobody moves while you are deciding, so this is reading time, not a race."
            ) {
                PaintedChoiceRow(
                    options: IncomingOfferTimer.allCases,
                    title: \.displayName,
                    selection: PacingPreferences.shared.incomingOfferTimer,
                    onSelect: { PacingPreferences.shared.select($0) }
                )
            }
        }
    }

    /// Label + ⓘ above a choice control, with the explanation folding out
    /// underneath when the ⓘ is tapped. Inline rather than a popover: a
    /// sentence does not deserve a modal, and a popover over a screen this
    /// dense hides the very control it is explaining.
    private func choiceRow<Control: View>(
        label: String,
        help: HelpTopic,
        helpText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(label)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                Button {
                    openHelp = (openHelp == help) ? nil : help
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(openHelp == help ? 0.95 : 0.55))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(label)")
                Spacer(minLength: 0)
            }
            control()
            if openHelp == help {
                Text(helpText)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Game control (B3)

    private var gameControlSection: some View {
        VStack(spacing: 14) {
            SettingsSectionHeader(title: "Game Control")

            VStack(spacing: 10) {
                controlRow(
                    title: "Resume Game",
                    icon: "play.circle",
                    accent: Self.resumeAccent,
                    tint: Self.resumeTint,
                    action: onResume
                )
                controlRow(
                    title: "Restart Game",
                    icon: "arrow.triangle.2.circlepath.circle",
                    accent: Self.restartAccent,
                    tint: Self.restartTint
                ) { isConfirmingRestart = true }
                // `house.circle`, not the reference's door-and-arrow glyph:
                // that symbol has no `.circle` variant, and the ringed icon is
                // what makes these three read as one set at a glance.
                controlRow(
                    title: "Quit to Main Menu",
                    icon: "house.circle",
                    accent: Self.quitAccent,
                    tint: Self.quitTint
                ) { isConfirmingMainMenu = true }
            }
        }
    }

    private func controlRow(title: String, icon: String, accent: Color, tint: Color, action: @escaping () -> Void) -> some View {
        GoldRowButton(
            title: title,
            systemImage: icon,
            iconColor: accent,
            fill: .tintedTexture(tint),
            trailing: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.55))
            },
            action: action
        )
    }

    // Painted tints for the three Game Control rows. Deep enough that white
    // titles still read, and each paired with a brighter accent for its icon
    // so "this one is destructive" survives being glanced at rather than read.
    private static let resumeTint = Color(red: 0.07, green: 0.26, blue: 0.12)
    private static let resumeAccent = Color(red: 0.30, green: 0.82, blue: 0.40)
    private static let restartTint = Color(red: 0.06, green: 0.16, blue: 0.31)
    private static let restartAccent = Color(red: 0.34, green: 0.60, blue: 0.96)
    private static let quitTint = Color(red: 0.24, green: 0.06, blue: 0.07)
    private static let quitAccent = Color(red: 0.92, green: 0.28, blue: 0.28)

    // MARK: - Bottom bar

    /// Close and Resume Game are the same action, and that is not an
    /// oversight: nothing on this screen is staged, so there is no "discard my
    /// edits" for Close to mean. Both dismiss, and both are here because the
    /// player arrives with one of two intentions - "I came to change a
    /// setting" and "I came to stop playing for a second" - and each should
    /// find the word it was looking for rather than having to read the other.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsChrome.ornamentGold.opacity(0.4))
                .frame(height: 1)

            HStack(spacing: 12) {
                UniformActionButton(
                    title: "Close",
                    systemImage: "xmark",
                    isEnabled: true,
                    backgroundImageName: "button-fill-trade",
                    action: onResume
                )
                .accessibilityIdentifier(AccessibilityID.InGameSettings.close)
                UniformActionButton(
                    title: "Resume Game",
                    systemImage: "play.fill",
                    isEnabled: true,
                    backgroundImageName: "button-fill-turn",
                    action: onResume
                )
            }
            // `UniformActionButton` grows to whatever height it is given
            // (`maxHeight: .infinity`), so the row has to state one.
            .frame(height: 62)
            .padding(.horizontal, Self.screenInset)
            .padding(.vertical, 12)
        }
        .background(SettingsChrome.screenBackground)
    }

    // MARK: - Confirmations (B3.2, B3.3)

    /// Both wordings are carried over unchanged from `PauseMenuView`: Restart
    /// says what is lost, Quit says what is *not*, which is the difference
    /// between the two and the only thing worth reading in the moment.
    private var restartConfirmation: some View {
        ConfirmationPopupCard(
            title: "Restart Game?",
            message: "This throws away the current board and starts a brand new game.",
            confirmTitle: "Restart",
            onConfirm: onRestart,
            onCancel: { isConfirmingRestart = false }
        )
    }

    private var mainMenuConfirmation: some View {
        ConfirmationPopupCard(
            title: "Quit to Main Menu?",
            message: "Your progress is saved, so you can pick up this game again from Resume.",
            confirmTitle: "Main Menu",
            onConfirm: onMainMenu,
            onCancel: { isConfirmingMainMenu = false }
        )
    }
}

#Preview {
    InGameSettingsView(onResume: {}, onRestart: {}, onMainMenu: {})
}
