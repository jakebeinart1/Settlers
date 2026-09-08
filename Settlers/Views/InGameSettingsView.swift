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
/// the Restart button.
///
/// ## Why a full screen and not a `PopupCard`
/// Every other popup in this app is a card over the board because it is a step
/// in a move - pick a resource, answer an offer. This is not part of a move,
/// it is a place you go, and it carries two controls plus the three ways out
/// of the game. The two confirmations it raises *are* `PopupCard`s, layered over
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
    /// explanations are a sentence each, and two open at once pushed the
    /// controls under them off the screen.
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
                // Top-pinned, and the slack under the two controls is left
                // alone. Centring them was tried and reverted the same day:
                // `PaintedChoiceRow` grows to whatever height it is given, so
                // a `Spacer` above and below handed it the free space and the
                // two segmented rows ballooned to roughly 500pt tall each.
                ScrollView {
                    VStack(spacing: 22) {
                        titleBlock
                        pacingSection
                        tradeTimerSection
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
            // This line used to be a `SettingsInfoPlaque` of its own, a
            // bordered gold-hairline card reading "These settings do not
            // change match rules." A plaque is the chrome this app uses for
            // something you act on, so a boxed sentence that does nothing read
            // as a button that would not press - Jake's ask, 2026-09-07. The
            // claim still matters (spec B4: nothing here touches the rules),
            // so it survives as the screen's own subtitle, where a sentence
            // explaining a screen belongs.
            Text("Presentation and pacing only — nothing here changes the rules of the game in progress.")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Bottom bar

    /// The three ways out of the game, and the only place they live.
    ///
    /// This row used to be Close and "Resume Game" side by side, over a "Game
    /// Control" section that repeated Resume and carried Restart and Quit as
    /// full-width rows. Two of those were the same button under two names -
    /// nothing on this screen is staged, so there is no "discard my edits" for
    /// Close to mean that Resume does not - and the section duplicated the
    /// other two. A pause menu you reached by pausing does not need to offer
    /// to un-pause twice (Jake's ask, 2026-09-07).
    ///
    /// So: one Close, and the two destructive actions beside it, each still
    /// behind its own confirmation. Bottom bar rather than in the scroll view,
    /// because these are the screen's actions and must not scroll away.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsChrome.ornamentGold.opacity(0.4))
                .frame(height: 1)

            HStack(spacing: 10) {
                UniformActionButton(
                    title: "Close",
                    systemImage: "xmark",
                    isEnabled: true,
                    backgroundImageName: "button-fill-trade",
                    action: onResume
                )
                .accessibilityIdentifier(AccessibilityID.InGameSettings.close)
                // All three share one texture, and that is the point: they are
                // one row of exits, distinguished by their words and by the
                // confirmation each destructive one raises, not by colour.
                // Two other treatments were tried and rejected by screenshot:
                // green (`button-fill-turn`, the End Turn button's own
                // texture) on Restart read as *go* on the button that throws
                // the game away, and dropping the texture from Restart and
                // Quit left them as flat grey slabs with none of the gold
                // hairline the rest of the screen is drawn with.
                UniformActionButton(
                    title: "Restart",
                    systemImage: "arrow.triangle.2.circlepath",
                    isEnabled: true,
                    backgroundImageName: "button-fill-trade",
                    action: { isConfirmingRestart = true }
                )
                .accessibilityIdentifier(AccessibilityID.InGameSettings.restart)
                UniformActionButton(
                    title: "Quit",
                    systemImage: "house.fill",
                    isEnabled: true,
                    backgroundImageName: "button-fill-trade",
                    action: { isConfirmingMainMenu = true }
                )
                .accessibilityIdentifier(AccessibilityID.InGameSettings.quit)
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
