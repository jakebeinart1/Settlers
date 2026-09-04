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
    /// Which seat's turn-order picker is open, or `nil`. Only reachable when
    /// Turn Order is "As Shown" - `SeatCardView`'s header is a locked label,
    /// not a button, while it's Random (Jake's ask, 2026-09-03).
    @State private var pickingSeatNumberForSeat: Int?
    @State private var isConfirmingOverwrite = false
    /// The reason the last seat edit was refused (A1.3), shown in place of the
    /// standing note under the grid. Cleared by the next edit rather than on a
    /// timer: a message that vanishes on its own is a message the player who
    /// looked away has no way to get back.
    @State private var refusal: String?
    @State private var openHelp: HelpTopic?
    @State private var isShowingUnreadableSetupAlert: Bool

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

    init(hasSavedGame: Bool = false, setupLoadResult: MatchSetupStore.LoadResult = .none,
         onStart: @escaping (MatchSetup) -> Void, onCancel: @escaping () -> Void) {
        self.onStart = onStart
        self.onCancel = onCancel
        let name = PlayerNameStore.shared.load()
        let civilization = CivilizationSettingsStore.shared.load().yourCivilization
        preferredName = name
        preferredCivilization = civilization
        self.hasSavedGame = hasSavedGame
        let initial = Self.initialSetup(
            from: setupLoadResult,
            preferredName: name,
            preferredCivilization: civilization
        )
        _setup = State(initialValue: initial.setup)
        _isShowingUnreadableSetupAlert = State(initialValue: initial.wasUnreadable)
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
    /// Gap between the two seat columns and between the two seat rows. 14pt
    /// rather than 10pt (Jake's ask, 2026-09-03: the cards read as too large/
    /// cramped) - the number-badge removal in `SeatCardView` freed up enough
    /// header height that the grid can give some of it back as breathing
    /// room between cards instead.
    private static let seatGutter: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let isShortScreen = geometry.size.height < 750
            // Explicit, not `.frame(maxWidth: .infinity)` on each card - two
            // flexible siblings in an `HStack` are not guaranteed pixel-equal
            // width by construction, only "each gets as much as it asks for,
            // divided fairly" - and content that reports even a hair more
            // ideal width (a `fixedSize` `Text`, a longer accessibility
            // label) can tip that division unevenly. Measured, reproducibly:
            // two seat cards with byte-identical content ("Aztec"/"Aztec")
            // still rendered the right one's text larger than the left's,
            // which only a genuine width difference between the two columns
            // could produce. A width computed once here and applied with
            // `.frame(width:)` (not `maxWidth:`) removes the ambiguity
            // instead of negotiating around it (Jake's ask, 2026-09-03).
            let seatCardWidth = (geometry.size.width - 2 * Self.screenInset - Self.seatGutter) / 2
            ZStack {
                paintedBackground

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            configuration(isShortScreen: isShortScreen, seatCardWidth: seatCardWidth)
                                .id(Self.footerAnchor)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        #if DEBUG
                        .task { await qaScrollToFooter(proxy) }
                        #endif
                    }

                    bottomBar(isShortScreen: isShortScreen)
                }

                if let seatIndex = pickingCivilizationForSeat { civilizationPicker(for: seatIndex) }
                if let seatIndex = pickingSeatNumberForSeat { seatNumberPicker(for: seatIndex) }
                if isConfirmingOverwrite { overwriteConfirmation }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Screen.newGame)
        .foregroundStyle(.white)
        .fontDesign(.serif)
        .alert("Couldn't open your previous setup", isPresented: $isShowingUnreadableSetupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The saved setup could not be read. It was left untouched, and safe defaults are shown instead.")
        }
    }

    /// The same painted seaside world + dark scrim `MainMenuView` sits on,
    /// rather than the flat navy `SettingsChrome.screenBackground` this
    /// screen used before - Jake's ask, 2026-09-03, that the two screens read
    /// as one continuous flow rather than the New Game screen dropping into
    /// separate "settings-app" chrome the moment New Game is tapped.
    private var paintedBackground: some View {
        ZStack {
            GeometryReader { geo in
                Image("board-background")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.55),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func configuration(isShortScreen: Bool, seatCardWidth: CGFloat) -> some View {
        VStack(spacing: isShortScreen ? 6 : 12) {
            titleBlock
            tableSizeSection
            seatsSection(isShortScreen: isShortScreen, seatCardWidth: seatCardWidth)
            matchSettingsSection
        }
        .padding(.horizontal, Self.screenInset)
        .padding(.top, isShortScreen ? 2 : 8)
        .padding(.bottom, isShortScreen ? 4 : 24)
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
    private static func initialSetup(
        from loadResult: MatchSetupStore.LoadResult,
        preferredName: String,
        preferredCivilization: Civilization
    ) -> (setup: MatchSetup, wasUnreadable: Bool) {
        #if DEBUG
        if let fixture = qaFixture() { return (fixture, false) }
        #endif
        let fallback = MatchSetup.default(preferredName: preferredName,
                                          preferredCivilization: preferredCivilization)
        guard case .loaded(var saved) = loadResult else {
            if case .unreadable = loadResult { return (fallback, true) }
            return (fallback, false)
        }
        guard GameSetup.supportedPlayerCounts.contains(saved.seats.count) else {
            return (fallback, true)
        }
        if MatchLength(rawValue: saved.victoryPointTarget) == nil {
            saved.victoryPointTarget = WinCondition.standardTarget
        }
        saved.normalizeNewGameOptions()
        applyAppPreferences(
            to: &saved,
            preferredName: preferredName,
            preferredCivilization: preferredCivilization
        )
        return (saved, false)
    }

    /// App Settings are defaults for the next match, not merely for the first
    /// match ever created. Preserve the rest of the previous layout while
    /// moving an occupied preferred civilization instead of creating a
    /// duplicate that would silently disable Start.
    private static func applyAppPreferences(
        to setup: inout MatchSetup,
        preferredName: String,
        preferredCivilization: Civilization
    ) {
        guard let humanIndex = setup.seats.firstIndex(where: \.isHuman) else { return }
        let previousCivilization = setup.seats[humanIndex].civilization
        if let occupiedIndex = setup.seats.firstIndex(where: {
            $0.index != setup.seats[humanIndex].index && $0.civilization == preferredCivilization
        }) {
            setup.seats[occupiedIndex].civilization = previousCivilization
        }
        setup.seats[humanIndex].name = preferredName
        setup.seats[humanIndex].civilization = preferredCivilization
    }

    // MARK: - Title

    /// Title only. The subtitle explained what the screen is to somebody who
    /// can already see four seat cards and a Start button, and cost ~30pt of
    /// the height that the match settings needed. No flanking diamond
    /// ornaments - Jake's ask, 2026-09-03, along with the matching ornaments
    /// on `InGameSettingsView`'s title and both screens' section headers.
    private var titleBlock: some View {
        Text("New Game")
            .font(.system(size: 26, weight: .bold, design: .serif))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
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

    private func seatsSection(isShortScreen: Bool, seatCardWidth: CGFloat) -> some View {
        VStack(spacing: isShortScreen ? 5 : 12) {
            SettingsSectionHeader(title: "Players & Civilizations", titleColor: .white)
            seatGrid(isShortScreen: isShortScreen, seatCardWidth: seatCardWidth)
            // Only the refusal. The standing note explained that seat 4 is
            // optional, which the "Optional" pill on that card already says,
            // and it occupied ~45pt permanently to do it.
            if let refusal {
                plaque(icon: "exclamationmark.triangle.fill", text: refusal,
                       tint: Self.problemTint, accent: Self.problemAccent)
            }
        }
    }

    /// Two rows of `HStack`, not `LazyVGrid` - Jake's ask, 2026-09-03. Lazy
    /// grids defer each row's layout pass, and that deferral was producing a
    /// measurable, reproducible size difference (confirmed pixel-for-pixel
    /// against a device screenshot: the bottom row's `minimumScaleFactor`
    /// text rendered visibly larger than the top row's, both at the
    /// identical explicit point size) between rows that are otherwise laid
    /// out identically. Four cards is a fixed, tiny count with nothing to
    /// gain from laziness, so a plain `HStack` per row - computed eagerly,
    /// in one pass - removes that inconsistency, but not the one below it.
    ///
    /// Each card also gets an explicit `seatCardWidth` (see `body`) rather
    /// than `.frame(maxWidth: .infinity)`: two flexible `HStack` siblings are
    /// not guaranteed pixel-equal width, and with identical content in both
    /// columns ("Aztec" in both) the right one still measurably rendered
    /// larger than the left. An explicit, precomputed, identical width for
    /// every card removes the ambiguity instead of negotiating around it.
    private func seatGrid(isShortScreen: Bool, seatCardWidth: CGFloat) -> some View {
        VStack(spacing: Self.seatGutter) {
            ForEach(seatRows.indices, id: \.self) { rowIndex in
                HStack(spacing: Self.seatGutter) {
                    ForEach(seatRows[rowIndex]) { seat in
                        seatCard(for: seat, isShortScreen: isShortScreen)
                            .frame(width: seatCardWidth)
                    }
                    // An odd seat count (3 players) leaves the last row with
                    // one card; a spacer holds the second column's width so
                    // that lone card doesn't stretch to fill the row.
                    if seatRows[rowIndex].count < 2 {
                        Color.clear.frame(width: seatCardWidth)
                    }
                }
            }
        }
    }

    /// `setup.seats` chunked into rows of two, in seat order - what
    /// `LazyVGrid`'s two-column layout produced implicitly, made explicit so
    /// `seatGrid` can lay each row out with a plain `HStack`.
    private var seatRows: [[MatchSetup.Seat]] {
        stride(from: 0, to: setup.seats.count, by: 2).map {
            Array(setup.seats[$0..<min($0 + 2, setup.seats.count)])
        }
    }

    private func seatCard(for seat: MatchSetup.Seat, isShortScreen: Bool) -> some View {
        SeatCardView(
            seat: seat,
            isOptional: seat.index == GameSetup.supportedPlayerCounts.upperBound - 1,
            onSetHuman: { setSeat(seat.index, human: $0) },
            onRename: { setup.seats[seat.index].name = $0 },
            onEditCivilization: { pickingCivilizationForSeat = seat.index },
            onEditSeatNumber: { pickingSeatNumberForSeat = seat.index },
            seatOrderIsRandom: setup.randomizeSeatOrder,
            isShortScreen: isShortScreen
        )
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
        // A profile is a snapshot of a realized AI opponent, not editable New
        // Game input. A role change must not leave a hidden second identity in
        // the same chair for `startNewGame` to discover later.
        setup.seats[index].opponentProfile = nil
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
                setup.seats[seatIndex].opponentProfile = nil
                pickingCivilizationForSeat = nil
            },
            onCancel: { pickingCivilizationForSeat = nil }
        )
    }

    private func seatNumberPicker(for seatIndex: Int) -> some View {
        SeatNumberPickerPopup(
            seatIndex: seatIndex,
            seatCount: setup.seats.count,
            onSelect: { number in
                setSeatNumber(seatIndex, to: number)
                pickingSeatNumberForSeat = nil
            },
            onCancel: { pickingSeatNumberForSeat = nil }
        )
    }

    /// Swaps this seat's turn-order position with whichever seat currently
    /// holds `number` (Jake's ask, 2026-09-03: picking a number "trades
    /// places" rather than leaving two cards claiming it or one orphaned).
    ///
    /// Swaps *content* (who's sitting there), never `.index` itself:
    /// `validationProblem` requires `hasOrderedSeatIndices` - every seat's
    /// `index` must equal its array position - so array position *is* turn
    /// order here, and every other seat mutation in this file already
    /// addresses seats by that same position (`setup.seats[seat.index]`).
    /// Reassigning `.index` values instead would silently break every one of
    /// those call sites.
    private func setSeatNumber(_ seatIndex: Int, to number: Int) {
        let targetIndex = number - 1
        guard targetIndex != seatIndex, setup.seats.indices.contains(targetIndex) else { return }
        let moved = setup.seats[seatIndex]
        let displaced = setup.seats[targetIndex]
        setup.seats[seatIndex].isHuman = displaced.isHuman
        setup.seats[seatIndex].name = displaced.name
        setup.seats[seatIndex].civilization = displaced.civilization
        setup.seats[seatIndex].opponentProfile = displaced.opponentProfile
        setup.seats[targetIndex].isHuman = moved.isHuman
        setup.seats[targetIndex].name = moved.name
        setup.seats[targetIndex].civilization = moved.civilization
        setup.seats[targetIndex].opponentProfile = moved.opponentProfile
    }

    // MARK: - Match settings (A4, A5)

    private var matchSettingsSection: some View {
        VStack(spacing: 10) {
            SettingsSectionHeader(title: "Match Settings", titleColor: .white)
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
            helpText: "The game ends when a player reaches this many victory points. "
                + "A saved game resumes at the target it started with. "
                + "Epic (12 VP) is available at three-player tables.",
            caption: nil
        ) {
            PaintedChoiceRow(
                options: MatchLength.allCases.filter {
                    MatchSetup.newGameVictoryPointTargets(for: setup.seats.count).contains($0.rawValue)
                },
                title: \.displayName,
                selection: MatchLength(rawValue: setup.victoryPointTarget) ?? .standard,
                isCompact: true,
                fontSize: SeatCardView.bodyTextSize,
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
                fontSize: SeatCardView.bodyTextSize,
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
                fontSize: SeatCardView.bodyTextSize,
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
    /// anybody asks for by name. Epic is shown only for a three-player table;
    /// `MatchSetup` owns that product rule so the view cannot drift from Start.
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
    private func bottomBar(isShortScreen: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(SettingsChrome.ornamentGold.opacity(0.4))
                .frame(height: 1)

            statusPlaque
                .padding(.horizontal, Self.screenInset)
                .padding(.top, isShortScreen ? 4 : 8)

            HStack(spacing: 12) {
                UniformActionButton(
                    title: "Cancel",
                    systemImage: "chevron.left",
                    isEnabled: true,
                    backgroundImageName: "button-fill-trade",
                    action: onCancel
                )
                .accessibilityIdentifier(AccessibilityID.NewGame.cancel)
                .frame(width: Self.cancelWidth)
                UniformActionButton(
                    title: "Start New Game",
                    systemImage: "flag.fill",
                    isEnabled: setup.isStartable,
                    backgroundImageName: "button-fill-turn",
                    action: startTapped
                )
                .accessibilityIdentifier(AccessibilityID.NewGame.start)
            }
            // `UniformActionButton` grows to whatever height it is given
            // (`maxHeight: .infinity`), so the row has to state one.
            .frame(height: isShortScreen ? 48 : 62)
            .padding(.horizontal, Self.screenInset)
            .padding(.vertical, isShortScreen ? 6 : 12)
        }
        // Matches the scrim's darkest stop rather than the old flat navy, so
        // the pinned bar reads as part of the same painted background instead
        // of a solid-colour strip stitched onto the bottom of it.
        .background(Color.black.opacity(0.55))
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
            message: "Starting a new game replaces the saved table. Its recording will be preserved.",
            confirmTitle: "Start New Game",
            confirmIdentifier: AccessibilityID.NewGame.confirmOverwrite,
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
