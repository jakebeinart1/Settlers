import CatanEngine
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
    /// Both `nil` when opened from the main menu: there is no match to
    /// restart or quit, so the bottom bar is Close alone.
    public let onRestart: (() -> Void)?
    public let onMainMenu: (() -> Void)?
    private let rulebookState: GameState?
    /// Main menu only: called after the lifetime stats are wiped, so the
    /// menu's stats row can drop them without a relaunch.
    private var onResetStats: (() -> Void)?

    public init(onResume: @escaping () -> Void, onRestart: @escaping () -> Void, onMainMenu: @escaping () -> Void,
                rulebookState: GameState? = nil) {
        self.onResume = onResume
        self.onRestart = onRestart
        self.onMainMenu = onMainMenu
        self.rulebookState = rulebookState
    }

    /// The main menu's Settings: the same screen, minus the match exits.
    public init(onClose: @escaping () -> Void, onResetStats: @escaping () -> Void) {
        onResume = onClose
        self.onResetStats = onResetStats
        onRestart = nil
        onMainMenu = nil
        rulebookState = nil
    }

    @AppStorage(BackgroundTheme.storageKey) private var theme: BackgroundTheme = .goldenDawn
    private static let themeThumbnail = CGSize(width: 58, height: 96)

    @State private var isConfirmingRestart = false
    @State private var isConfirmingMainMenu = false
    @State private var isShowingRulebook = false
    @State private var isConfirmingStatsReset = false
    /// Which row's ⓘ is currently expanded, or `nil`. One at a time: these
    /// explanations are a sentence each, and two open at once pushed the
    /// controls under them off the screen.
    @State private var openHelp: HelpTopic?

    private enum HelpTopic {
        case aiTurnSpeed
        case incomingOfferTimer
        case skipPauses
        case blockTradeOffers
    }

    /// Horizontal inset for the whole screen. 20pt each side leaves 335pt of
    /// content on a 375pt iPhone SE / 13 mini - the width the four-option
    /// timer row is sized against (see `PaintedChoiceRow`).
    private static let screenInset: CGFloat = 20

    public var body: some View {
        ZStack {
            // The chosen theme shows through, so picking one repaints this
            // screen the moment it is tapped.
            GeometryReader { geo in
                ThemedBackgroundImage()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            SettingsChrome.screenBackground.opacity(0.78).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top-pinned, and the slack under the two controls is left
                // alone. Centring them was tried and reverted the same day:
                // `PaintedChoiceRow` grows to whatever height it is given, so
                // a `Spacer` above and below handed it the free space and the
                // two segmented rows ballooned to roughly 500pt tall each.
                ScrollView {
                    VStack(spacing: 22) {
                        titleBlock
                        themeSection
                        pacingSection
                        tradeTimerSection
                        skipSection
                        rulebookSection
                        if onResetStats != nil { dataSection }
                    }
                    .padding(.horizontal, Self.screenInset)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                bottomBar
            }

            if isConfirmingRestart { restartConfirmation }
            if isConfirmingMainMenu { mainMenuConfirmation }
            if isConfirmingStatsReset { statsResetConfirmation }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.inGameSettings)
        .foregroundStyle(.white)
        // Serif everywhere, matching the board screen's painted-book type.
        .fontDesign(.serif)
        .fullScreenCover(isPresented: $isShowingRulebook) {
            HowToPlayView(context: rulebookState.map { HowToPlayContent.Context(state: $0) }, initialTab: .rules,
                          onDismiss: { isShowingRulebook = false })
        }
    }

    /// Reading rules stays inside the already-paused settings surface. The
    /// parent supplies the match snapshot; this screen never loads another save.
    private var rulebookSection: some View {
        VStack(spacing: 12) {
            SettingsSectionHeader(title: "Rules of Empires")
            Text("Knight, Monopoly and sevens. Board sizes, card limits and Conquest.")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GoldRowButton(title: "Read the rulebook", systemImage: "book.fill",
                          iconColor: SettingsChrome.ornamentGold, action: { isShowingRulebook = true })
                .accessibilityIdentifier(AccessibilityID.InGameSettings.rulebook)
        }
    }

    // MARK: - Title

    /// No flanking diamond ornaments - Jake's ask, 2026-09-03, along with the
    /// matching ornament on `NewGameSetupView`'s title and both screens'
    /// section headers.
    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text(onRestart == nil ? "Settings" : "In-Game Settings")
                .font(.system(size: 29, weight: .bold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let rulebookState {
                Text(VictoryTargetText.goal(rulebookState.victoryPointTarget))
                    .font(.system(size: 17, weight: .semibold, design: .serif))
                    .foregroundStyle(CatanTheme.cityPennantGold)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("in-game-settings.victory-target")
            }
            // This line used to be a `SettingsInfoPlaque` of its own, a
            // bordered gold-hairline card reading "These settings do not
            // change match rules." A plaque is the chrome this app uses for
            // something you act on, so a boxed sentence that does nothing read
            // as a button that would not press - Jake's ask, 2026-09-07. The
            // claim still matters (spec B4: nothing here touches the rules),
            // so it survives as the screen's own subtitle, where a sentence
            // explaining a screen belongs.
            Text(onRestart == nil ? "Look, pacing and your data. Nothing here changes the rules."
                                  : "Presentation and pacing only — nothing here changes the rules of the game in progress.")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Your data

    private var dataSection: some View {
        VStack(spacing: 12) {
            SettingsSectionHeader(title: "Your Data")
            Text("Clears Played, Win Rate, Avg Time and Avg VP on the main menu. "
                 + "Your rating, game history and ghost are kept.")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GoldRowButton(title: "Reset Stats", systemImage: "arrow.counterclockwise",
                          iconColor: CatanTheme.color(for: Resource.brick), action: { isConfirmingStatsReset = true })
                .accessibilityIdentifier(AccessibilityID.InGameSettings.resetStats)
        }
    }

    private var statsResetConfirmation: some View {
        ConfirmationPopupCard(
            title: "Reset Stats?",
            message: "Played, Win Rate, Avg Time and Avg VP go back to zero. This cannot be undone.",
            confirmTitle: "Reset",
            confirmIdentifier: AccessibilityID.InGameSettings.resetStatsConfirm,
            onConfirm: {
                GameStatsStore.shared.clear()
                onResetStats?()
                isConfirmingStatsReset = false
            },
            onCancel: { isConfirmingStatsReset = false }
        )
    }

    // MARK: - Theme

    /// All five fit one row at 335pt, so there is nothing to scroll past.
    private var themeSection: some View {
        VStack(spacing: 14) {
            SettingsSectionHeader(title: "Theme")
            HStack(spacing: 8) {
                ForEach(BackgroundTheme.allCases) { option in
                    themeButton(option)
                }
            }
        }
    }

    private func themeButton(_ option: BackgroundTheme) -> some View {
        let isSelected = option == theme
        let shape = RoundedRectangle(cornerRadius: 9)
        return Button { theme = option } label: {
            VStack(spacing: 6) {
                Image(option.imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.themeThumbnail.width, height: Self.themeThumbnail.height)
                    .clipShape(shape)
                    .overlay(shape.stroke(isSelected ? CatanTheme.cityPennantGold : .white.opacity(0.25),
                                          lineWidth: isSelected ? 3 : 1))
                Text(option.displayName)
                    .font(.system(size: 11, weight: isSelected ? .bold : .regular, design: .serif))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
            .frame(width: Self.themeThumbnail.width + 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityID.InGameSettings.theme(option.rawValue))
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

    // MARK: - Skipping

    /// Two Off/On switches, painted like the rows above. Together they make
    /// CPU turns run straight through to the player's own turn.
    private var skipSection: some View {
        VStack(spacing: 14) {
            SettingsSectionHeader(title: "Skipping")
            choiceRow(
                label: "Skip Pauses",
                help: .skipPauses,
                helpText: "Bots act with no viewing pause. Your own decisions - placements, discards, the robber - still wait for you."
            ) {
                onOffRow(selection: PacingPreferences.shared.skipPauses,
                         identifier: AccessibilityID.InGameSettings.skipPauses,
                         onSelect: PacingPreferences.shared.setSkipPauses)
            }
            choiceRow(
                label: "Block Trade Offers",
                help: .blockTradeOffers,
                helpText: "Every bot trade offer to you is declined without being shown, all game. "
                    + "To block one round only, tap Block round on the offer itself. "
                    + "With Skip Pauses on too, play jumps straight to your turn."
            ) {
                onOffRow(selection: PacingPreferences.shared.blockTradeOffers,
                         identifier: AccessibilityID.InGameSettings.blockTradeOffers,
                         onSelect: PacingPreferences.shared.setBlockTradeOffers)
            }
        }
    }

    private func onOffRow(selection: Bool, identifier: @escaping (Bool) -> String,
                          onSelect: @escaping (Bool) -> Void) -> some View {
        PaintedChoiceRow(options: [false, true], title: { $0 ? "On" : "Off" }, selection: selection,
                         optionIdentifier: identifier, onSelect: onSelect)
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
                if onRestart != nil {
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
            confirmIdentifier: "in-game-settings.restart-confirm",
            onConfirm: { onRestart?() },
            onCancel: { isConfirmingRestart = false }
        )
    }

    private var mainMenuConfirmation: some View {
        ConfirmationPopupCard(
            title: "Quit to Main Menu?",
            message: "Your progress is saved, so you can pick up this game again from Resume.",
            confirmTitle: "Main Menu",
            onConfirm: { onMainMenu?() },
            onCancel: { isConfirmingMainMenu = false }
        )
    }
}

#Preview {
    InGameSettingsView(onResume: {}, onRestart: {}, onMainMenu: {})
}
