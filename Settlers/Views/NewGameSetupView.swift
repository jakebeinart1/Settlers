import SwiftUI
import CatanEngine

/// Surface A of the settings spec: the match contract, chosen before a game
/// exists and fixed the moment Start is pressed.
///
/// ## What this screen replaced
/// Two toggles on the main menu ("Randomized Board", "Randomize Seat") and
/// nothing else. Everything else the match is made of - how many seats, which
/// of them a person is sitting in, what those people are called, which empire
/// each seat leads, how long the game runs - was either hardcoded, buried in
/// App Settings as a *preference* that silently became the value the game ran
/// on, or simply absent. The spec's rule for where a setting goes (section 0)
/// puts all of it here: if changing it mid-game would change what a legal move
/// is, who is playing, or what winning means, it is match contract.
///
/// ## Where validity lives, and why not here
/// This view never decides whether a configuration can start. `MatchSetup`
/// does, in one place, and it answers with a *sentence* rather than a boolean
/// (`validationProblem`). The screen's job is to show that sentence and to
/// disable Start, so a control that is unavailable always says why (A6.1) -
/// the failure mode this replaces is a greyed-out button with no explanation,
/// which is indistinguishable from a broken one.
///
/// The one rule enforced in the view rather than in the model is A1.3, the
/// last human seat: it is a rule about an *edit* ("you may not make this
/// change") rather than about a state, and refusing the tap with a reason is
/// strictly better than allowing an invalid state and then explaining it.
///
/// ## Why no system controls
/// No `Picker`, `Form`, `List`, `.segmented` or `NavigationStack` chrome -
/// they render grey-on-grey against this palette and cannot take the painted
/// gold-hairline treatment. `SettingsView` is the one screen in the app built
/// that way and is considered a defect. The painted equivalents live in
/// `SettingsChrome`.
struct NewGameSetupView: View {
    /// Handed a configuration that has already passed `validationProblem` and
    /// has already been confirmed against any save it would destroy.
    let onStart: (MatchSetup) -> Void
    let onCancel: () -> Void

    @State private var setup: MatchSetup
    /// Which seat's civilization picker is open, or `nil`.
    @State private var pickingCivilizationForSeat: Int?
    @State private var isConfirmingOverwrite = false
    /// The reason the last seat edit was refused (A1.3), shown in place of the
    /// standing note under the grid. Cleared by the next edit rather than on a
    /// timer: a message that vanishes on its own is a message the player who
    /// looked away has no way to get back.
    @State private var refusal: String?
    @State private var openHelp: HelpTopic?

    /// Read once, at init. Both are App Settings *preferences* - they prefill
    /// this screen (A2.3, A3.7, C1.1, C2.1) and are never the value the game
    /// runs on (X1.2), so nothing here writes back to them.
    private let preferredName: String
    private let preferredCivilization: Civilization

    /// Whether starting would destroy a game in progress (A6.2). Cached rather
    /// than asked on every render: nothing reachable from this screen can
    /// create or delete a save while it is open, and `MainMenuView` previously
    /// paid a full decode of a 17-40KB state per body evaluation to answer the
    /// same question.
    private let hasSavedGame: Bool

    init(onStart: @escaping (MatchSetup) -> Void, onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        let name = PlayerNameStore.shared.load()
        let civilization = CivilizationSettingsStore.shared.load().yourCivilization
        preferredName = name
        preferredCivilization = civilization
        hasSavedGame = GameStore.shared.hasSave()
        _setup = State(initialValue: Self.initialSetup(preferredName: name, preferredCivilization: civilization))
        #if DEBUG
        _isConfirmingOverwrite = State(initialValue: QALaunchFlag.showNewGameOverwrite.isSet)
        _pickingCivilizationForSeat = State(
            initialValue: QALaunchFlag.showNewGameCivilizationPicker.isSet ? 1 : nil)
        #endif
    }

    /// Horizontal inset for the whole screen. 20pt each side leaves 335pt of
    /// content on a 375pt iPhone SE / 13 mini, which is the width every layout
    /// decision below (and in `SeatCardView`) is sized against.
    private static let screenInset: CGFloat = 20
    /// Gap between the two seat columns and between the two seat rows.
    private static let seatGutter: CGFloat = 10

    var body: some View {
        ZStack {
            SettingsChrome.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            titleBlock
                            tableSizeSection
                            seatsSection
                            matchSettingsSection
                        }
                        .padding(.horizontal, Self.screenInset)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                        .id(Self.footerAnchor)
                    }
                    // The screen is taller than a phone and half of it is text
                    // fields, so a keyboard that will not go away would hide the
                    // action bar entirely.
                    .scrollDismissesKeyboard(.interactively)
                    #if DEBUG
                    .task { await qaScrollToFooter(proxy) }
                    #endif
                }

                bottomBar
            }

            if let seatIndex = pickingCivilizationForSeat { civilizationPicker(for: seatIndex) }
            if isConfirmingOverwrite { overwriteConfirmation }
        }
        .foregroundStyle(.white)
        .fontDesign(.serif)
    }

    // MARK: - Prefill (A6.4, X4.2)

    /// The configuration the screen opens on: the last one started, or a
    /// standard four-seat table built from the stored preferences.
    ///
    /// The stored setup is checked before it is trusted. It is decoded from
    /// `UserDefaults` and could in principle carry a seat count this build no
    /// longer supports or a victory target this screen has no button for, and
    /// `MatchSetup.resize` traps on the former. Both fall back rather than
    /// opening a screen whose controls disagree with the value behind them.
    private static func initialSetup(preferredName: String, preferredCivilization: Civilization) -> MatchSetup {
        #if DEBUG
        if let fixture = qaFixture() { return fixture }
        #endif
        guard var saved = MatchSetupStore.shared.load(),
              GameSetup.supportedPlayerCounts.contains(saved.seats.count) else {
            return .default(preferredName: preferredName, preferredCivilization: preferredCivilization)
        }
        if MatchLength(rawValue: saved.victoryPointTarget) == nil {
            saved.victoryPointTarget = WinCondition.standardTarget
        }
        return saved
    }

    // MARK: - Title

    /// Title only. The subtitle explained what the screen is to somebody who
    /// can already see four seat cards and a Start button, and cost ~30pt of
    /// the height that the match settings needed.
    private var titleBlock: some View {
        HStack(spacing: 12) {
            titleOrnament
            Text("New Game")
                .font(.system(size: 26, weight: .bold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            titleOrnament
        }
    }

    private var titleOrnament: some View {
        Image(systemName: "diamond.fill")
            .font(.system(size: 11))
            .foregroundStyle(SettingsChrome.ornamentGold)
    }

    // MARK: - Table size (A1.1)

    /// Inline label rather than an ornamented section header of its own - one
    /// control does not need a section, and the header cost ~40pt.
    private var tableSizeSection: some View {
        HStack(spacing: 12) {
            Text("Table")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.75))
            PaintedChoiceRow(
                options: Array(GameSetup.supportedPlayerCounts),
                title: { "\($0) Players" },
                selection: setup.seats.count,
                onSelect: setTableSize
            )
        }
    }

    /// Growing adds an AI seat, shrinking drops the highest one, and neither
    /// may leave a table with nobody in it - all three are `MatchSetup.resize`,
    /// not this screen. The seat cards are a pure function of `setup.seats`, so
    /// there is no separate "number of players" that could disagree with them
    /// (A1.5).
    private func setTableSize(_ count: Int) {
        guard count != setup.seats.count else { return }
        refusal = nil
        setup.resize(to: count, preferredName: preferredName, preferredCivilization: preferredCivilization)
    }

    // MARK: - Seats (A1, A2, A3)

    private var seatsSection: some View {
        VStack(spacing: 12) {
            SettingsSectionHeader(title: "Players & Civilizations")
            seatGrid
            // Only the refusal. The standing note explained that seat 4 is
            // optional, which the "Optional" pill on that card already says,
            // and it occupied ~45pt permanently to do it.
            if let refusal {
                plaque(icon: "exclamationmark.triangle.fill", text: refusal,
                       tint: Self.problemTint, accent: Self.problemAccent)
            }
        }
    }

    private var seatGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Self.seatGutter), GridItem(.flexible())],
            spacing: Self.seatGutter
        ) {
            ForEach(setup.seats) { seat in
                SeatCardView(
                    seat: seat,
                    isOptional: seat.index == GameSetup.supportedPlayerCounts.upperBound - 1,
                    onSetHuman: { setSeat(seat.index, human: $0) },
                    onRename: { setup.seats[seat.index].name = $0 },
                    onEditCivilization: { pickingCivilizationForSeat = seat.index }
                )
            }
        }
    }

    /// A1.2, and A1.3's refusal. The last human seat cannot become AI, because
    /// a table of four bots has nobody to play it - and the tap is answered
    /// with the reason rather than silently doing nothing, which reads as a
    /// broken control.
    private func setSeat(_ index: Int, human: Bool) {
        refusal = nil
        guard human || setup.humanSeats.count > 1 || !setup.seats[index].isHuman else {
            refusal = "Seat \(index + 1) is the only human seat - somebody has to play."
            return
        }
        setup.seats[index].isHuman = human
    }

    /// A3.3 is served by handing the picker exactly the set `MatchSetup`
    /// computes, rather than the view working out what is taken for itself.
    private func civilizationPicker(for seatIndex: Int) -> some View {
        CivilizationPickerPopup(
            seatIndex: seatIndex,
            selection: setup.seats[seatIndex].civilization,
            taken: setup.civilizationsTaken(excluding: seatIndex),
            onSelect: { civilization in
                setup.seats[seatIndex].civilization = civilization
                pickingCivilizationForSeat = nil
            },
            onCancel: { pickingCivilizationForSeat = nil }
        )
    }

    // MARK: - Match settings (A4, A5)

    private var matchSettingsSection: some View {
        VStack(spacing: 10) {
            SettingsSectionHeader(title: "Match Settings")
            matchLengthRow
            boardRow
            seatingRow
        }
    }

    /// A4.1: a small named set, so an unsupported target is unrepresentable
    /// rather than validated. The caption carries the number the name stands
    /// for, because "Standard" alone does not tell a player what they are
    /// playing to and the option chips are too narrow at 375pt to hold both.
    private var matchLengthRow: some View {
        labelledChoice(
            label: "Match Length",
            help: .matchLength,
            helpText: "How many victory points win the game. The bots play toward the same target, "
                + "and a saved game resumes at the target it started with.",
            caption: nil
        ) {
            PaintedChoiceRow(
                options: MatchLength.allCases,
                title: \.displayName,
                selection: MatchLength(rawValue: setup.victoryPointTarget) ?? .standard,
                isCompact: true,
                onSelect: { setup.victoryPointTarget = $0.rawValue }
            )
        }
    }

    private var boardRow: some View {
        labelledChoice(
            label: "Board",
            help: .board,
            helpText: "Standard is the classic fixed layout every game of Catan opens on. "
                + "Randomized reshuffles the terrain and the number tokens.",
            caption: nil
        ) {
            PaintedChoiceRow(
                options: [false, true],
                title: { $0 ? "Randomized" : "Standard" },
                selection: setup.randomizedBoard,
                isCompact: true,
                onSelect: { setup.randomizedBoard = $0 }
            )
        }
    }

    /// A5.4: with "As Shown" the cards above *are* the turn order, so it is
    /// visible before Start; with "Random" the caption says plainly that it is
    /// not yet decided, which is the other half of that criterion.
    private var seatingRow: some View {
        labelledChoice(
            label: "Turn Order",
            help: .seating,
            helpText: "As Shown plays the seats in the order laid out above. Random shuffles who goes "
                + "first — you still play the civilization and name you picked.",
            // No standing caption: "As Shown" and "Random" already say it, and
            // this is the last row on the screen, so a caption here is the one
            // thing that gets clipped by the pinned bar. The fuller
            // explanation is still a tap away on the info button.
            caption: nil
        ) {
            PaintedChoiceRow(
                options: [false, true],
                title: { $0 ? "Random" : "As Shown" },
                selection: setup.randomizeSeatOrder,
                isCompact: true,
                onSelect: { setup.randomizeSeatOrder = $0 }
            )
        }
    }

    private enum HelpTopic {
        case matchLength
        case board
        case seating
    }

    /// A4.1's named set. Deliberately a subset of `WinCondition.supportedTargets`
    /// (8...12): nine and eleven are legal for the engine but are not lengths
    /// anybody asks for by name, and three chips is what fits 335pt.
    private enum MatchLength: Int, CaseIterable {
        case quick = 8
        case standard = 10
        case epic = 12

        /// The number is IN the chip, not in a caption underneath it.
        /// "Standard" alone does not tell a player what they are playing to,
        /// and a caption per row cost more height than the screen had.
        var displayName: String {
            switch self {
            case .quick: return "8 VP"
            case .standard: return "10 VP"
            case .epic: return "12 VP"
            }
        }
    }

    /// Label + ⓘ above a choice control, with the explanation folding out
    /// underneath when the ⓘ is tapped, and an optional standing caption that
    /// states the current choice in words. Matches `InGameSettingsView`'s row
    /// shape so the two settings surfaces read as one family.
    private func labelledChoice<Control: View>(
        label: String,
        help: HelpTopic,
        helpText: String,
        caption: String?,
        @ViewBuilder control: () -> Control
    ) -> some View {
        // Label beside the control, not stacked above it, and no standing
        // caption. Stacked with a caption each row cost ~110pt, so the three of
        // them plus a section header pushed Board, Seating and the status line
        // off the bottom of the screen - on the screen whose entire job is to
        // show you the configuration. `caption` is kept in the signature and
        // shown only while help is closed for rows that genuinely need one.
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 104, alignment: .leading)
                helpButton(label: label, topic: help)
                control()
            }
            if openHelp == help {
                footnote(helpText)
            } else if let caption {
                footnote(caption)
            }
        }
    }

    private func helpButton(label: String, topic: HelpTopic) -> some View {
        Button {
            openHelp = (openHelp == topic) ? nil : topic
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.white.opacity(openHelp == topic ? 0.95 : 0.55))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(label)")
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .serif))
            .foregroundStyle(.white.opacity(0.6))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Status (A6.1)

    /// The screen's single answer to "can this start, and if not, why not".
    /// Green with a summary, or amber with the exact sentence `MatchSetup`
    /// gives - never a bare disabled button.
    @ViewBuilder
    private var statusPlaque: some View {
        if let problem = setup.validationProblem {
            plaque(icon: "exclamationmark.triangle.fill", text: problem,
                   tint: Self.problemTint, accent: Self.problemAccent)
        } else if hasSavedGame {
            // Amber, not green: this configuration is valid AND starting it
            // destroys a game in progress. Two facts, one line, and the colour
            // carries which one matters more.
            plaque(icon: "exclamationmark.triangle.fill", text: readySummary,
                   tint: Self.warningTint, accent: Self.warningAccent)
        } else {
            plaque(icon: "checkmark.circle", text: readySummary,
                   tint: Self.readyTint, accent: Self.readyAccent)
        }
    }

    /// Counts read off the seats themselves (A1.5). The civilization count is
    /// the seat count because distinctness is an invariant of a startable setup
    /// (A3.2), not an aspiration - a seat left on Random draws from what is
    /// still free.
    /// One line, because it lives in the pinned bar and every point it takes
    /// comes off the configuration above it. Two stacked plaques - the summary
    /// and the saved-game warning - pushed Board and Turn Order back off the
    /// screen, which is the problem this move was meant to solve.
    private var readySummary: String {
        let humans = setup.humanSeats.count
        let bots = setup.aiSeats.count
        let composition = "\(humans) Human\(humans == 1 ? "" : "s") • \(bots) AI"
        return hasSavedGame
            ? "Ready • \(composition) • replaces your saved game"
            : "Ready to start • \(composition)"
    }

    private var savedGameWarning: some View {
        plaque(
            icon: "exclamationmark.triangle.fill",
            text: "Saved game in progress — starting a new game will replace it.",
            tint: Self.warningTint,
            accent: Self.warningAccent
        )
    }

    private func plaque(icon: String, text: String, tint: Color, accent: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(accent)
            Text(text)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.92))
                // One line, shrinking rather than wrapping. This plaque sits in
                // the pinned bar, so a second line is 28pt taken directly off
                // the configuration it is describing.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(PaintedChromeBackground(fill: .tintedTexture(tint), cornerRadius: 10, notchScale: 0.6))
    }

    // Painted tints for the three plaque states, deep enough that white text
    // still reads on them, each paired with a brighter accent so the icon
    // carries the state at a glance rather than only the words.
    private static let readyTint = Color(red: 0.05, green: 0.20, blue: 0.10)
    private static let readyAccent = Color(red: 0.30, green: 0.82, blue: 0.40)
    private static let warningTint = Color(red: 0.24, green: 0.16, blue: 0.02)
    private static let warningAccent = Color(red: 0.95, green: 0.72, blue: 0.25)
    private static let problemTint = Color(red: 0.26, green: 0.08, blue: 0.06)
    private static let problemAccent = Color(red: 0.95, green: 0.42, blue: 0.35)

    // MARK: - Bottom bar

    /// Pinned outside the `ScrollView`, because the screen is taller than a
    /// phone and an action bar that has to be scrolled to is an action bar that
    /// gets lost.
    /// Pinned, and it carries the status line.
    ///
    /// The status used to sit at the end of the scroll view, roughly 900pt down,
    /// while Start was pinned outside it - so an invalid configuration showed a
    /// dimmed button with the reason nowhere on screen. A6.1 asks for the
    /// reason to be stated; stating it where the player cannot see it satisfies
    /// the letter and not the point. Here it is always visible, and always next
    /// to the button it is about.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsChrome.ornamentGold.opacity(0.4))
                .frame(height: 1)

            statusPlaque
                .padding(.horizontal, Self.screenInset)
                .padding(.top, 8)

            HStack(spacing: 12) {
                UniformActionButton(
                    title: "Cancel",
                    systemImage: "chevron.left",
                    isEnabled: true,
                    backgroundImageName: "button-fill-trade",
                    action: onCancel
                )
                .frame(width: Self.cancelWidth)
                UniformActionButton(
                    title: "Start New Game",
                    systemImage: "flag.fill",
                    isEnabled: setup.isStartable,
                    backgroundImageName: "button-fill-turn",
                    action: startTapped
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

    /// Cancel is fixed and narrow so Start gets the rest: at 375pt that is
    /// 335 - 108 - 12 = 215pt for "Start New Game", which measures ~100pt at
    /// footnote weight.
    private static let cancelWidth: CGFloat = 108

    // MARK: - Starting (A6.1, A6.2)

    /// The guard is belt and braces - the button is already disabled - but it
    /// is the only thing standing between a future caller and an invalid game,
    /// and `validationProblem` is the single place that decides.
    private func startTapped() {
        guard setup.isStartable else { return }
        if hasSavedGame {
            isConfirmingOverwrite = true
        } else {
            onStart(setup)
        }
    }

    /// A6.2. Cancelling touches nothing: the save is only ever destroyed by
    /// `startNewGame` overwriting it, and that is downstream of `onStart`.
    private var overwriteConfirmation: some View {
        ConfirmationPopupCard(
            title: "Replace your saved game?",
            message: "You have a game in progress. Starting a new one throws it away, and it cannot be recovered.",
            confirmTitle: "Start New Game",
            onConfirm: { onStart(setup) },
            onCancel: { isConfirmingOverwrite = false }
        )
    }

    // MARK: - QA fixtures

    /// Identity of the whole scrollable column, used only as a scroll target.
    private static let footerAnchor = "newGameSetupContent"

    #if DEBUG
    /// `-qaScrollNewGameToBottom`: parks the screen at the bottom so the half
    /// of it that is below the fold can be photographed. The short sleep is
    /// load-bearing - `scrollTo` before the content has been laid out lands on
    /// a height that is still growing and leaves the view part-way down.
    private func qaScrollToFooter(_ proxy: ScrollViewProxy) async {
        guard QALaunchFlag.scrollNewGameToBottom.isSet else { return }
        try? await Task.sleep(for: .milliseconds(400))
        proxy.scrollTo(Self.footerAnchor, anchor: .bottom)
    }
    #endif

    #if DEBUG
    /// What the `-qaShowNewGame*` flags open the screen on, so both the valid
    /// and the invalid state can be photographed without a way to tap.
    ///
    /// There is no touch injection on the simulator and SwiftUI presents no
    /// element tree to the accessibility APIs, so a screen that can only be
    /// reached by typing into it cannot be verified at all otherwise - see
    /// `QALaunchFlag`.
    private static func qaFixture() -> MatchSetup? {
        var valid = MatchSetup(
            seats: [
                MatchSetup.Seat(index: 0, isHuman: true, name: "Alex", civilization: .greece),
                MatchSetup.Seat(index: 1, isHuman: true, name: "Sam", civilization: .rome),
                MatchSetup.Seat(index: 2, isHuman: false, name: "", civilization: .japan),
                MatchSetup.Seat(index: 3, isHuman: false, name: "", civilization: nil),
            ],
            victoryPointTarget: WinCondition.standardTarget,
            randomizedBoard: true,
            randomizeSeatOrder: true
        )
        if QALaunchFlag.newGameThreeSeats.isSet {
            valid.resize(to: GameSetup.supportedPlayerCounts.lowerBound,
                         preferredName: "Alex", preferredCivilization: .greece)
        }
        if QALaunchFlag.showNewGameInvalid.isSet {
            var invalid = valid
            // Whitespace-only, which A2.6 requires to read as empty.
            invalid.seats[1].name = "   "
            return invalid
        }
        let opensOnTheFixture = QALaunchFlag.showNewGame.isSet
            || QALaunchFlag.showNewGameOverwrite.isSet
            || QALaunchFlag.showNewGameCivilizationPicker.isSet
        guard opensOnTheFixture else { return nil }
        return valid
    }
    #endif
}

#Preview {
    NewGameSetupView(onStart: { _ in }, onCancel: {})
}
