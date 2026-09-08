import SwiftUI

/// One chair at the table on the New Game screen: who is sitting in it, what
/// they are called, and which empire they lead.
///
/// ## Why a card per seat rather than a full-width row per seat
/// A row carrying a Human/AI control, a name and a civilization is tall, and
/// four of them stacked is more than a phone screen - while A1.1 asks for every
/// seat to be visible at once. Two columns of two cards fits the whole table
/// into one glance.
///
/// ## The 375pt arithmetic, which is what actually sizes everything here
/// The tightest screen this has to survive is 375pt (iPhone SE / 13 mini); the
/// 402pt simulator does not exercise it. `NewGameSetupView` insets the screen
/// by 20pt each side and puts a 14pt gutter between the columns (10pt before
/// Jake's ask, 2026-09-03, for more breathing room between cards), so a card
/// is (375 - 40 - 14) / 2 = 160.5pt wide, and 144.5pt inside its own 8pt
/// padding. Every measurement below is chosen against that:
///
/// - Header: 6pt dot + 5 + "Seat 4" at 15pt serif (~44pt) + an "Optional"
///   pill (~48pt) = ~103pt, leaving ~41pt of slack (was ~18pt before the
///   numbered circle badge in front of the dot was dropped, Jake's ask,
///   2026-09-03 - it duplicated the seat number the text already states).
/// - Civilization row: 13pt glyph + 7 + "Britannia" at 15pt serif (~66pt) +
///   chevron + 20pt padding = ~120pt.
///
/// Every text size on the card - header, Human/AI toggle, name field,
/// general name, civilization row - is the same 15pt (`bodyTextSize`),
/// except the "Optional" pill, a badge rather than a content line (Jake's
/// ask, 2026-09-03). The Human/AI box's vertical padding is pulled from the
/// civilization row's own so the two boxes come out the same height
/// (`civilizationRowVerticalPadding`), also Jake's ask.
///
/// `lineLimit(1)` + `minimumScaleFactor` is the backstop for a larger Dynamic
/// Type setting, not the mechanism - the layout is meant to fit at 1x.
///
/// ## Why the card carries the civilization's colour
/// The seat colour *is* the civilization's colour on the board, which is why
/// A3.2 makes distinctness an invariant rather than a warning. Painting the
/// card's border and fill with it means two hard-to-tell-apart picks show up
/// here, before the game starts, rather than mid-game on a crowded board.
struct SeatCardView: View {
    let seat: MatchSetup.Seat
    /// Draws the "Optional" pill. True only for the seat a 3-player table drops
    /// (`MatchSetup.resize` shrinks off the end), so the pill is telling the
    /// truth about which chair disappears rather than decorating the last card.
    let isOptional: Bool
    let onSetHuman: (Bool) -> Void
    let onRename: (String) -> Void
    let onEditCivilization: () -> Void
    /// Raises `SeatNumberPickerPopup` for this seat. Only reachable when
    /// `seatOrderIsRandom` is false - the header renders as a plain locked
    /// label instead of a button while it's true, so this is never called
    /// then (Jake's ask, 2026-09-03).
    var onEditSeatNumber: () -> Void = {}
    /// Whether `NewGameSetupView`'s Turn Order is set to Random - when it is,
    /// none of the four cards' positions is the actual play order, so the
    /// header shows a locked "Seat: ?" instead of a number the player could
    /// edit, which would misleadingly imply a fixed turn order (Jake's ask,
    /// 2026-09-03).
    var seatOrderIsRandom = false
    var isShortScreen = false

    /// A2.5: a name has a maximum length, enforced at input rather than by
    /// truncating at display. Twelve characters is what fits the 142.5pt field
    /// at 15pt serif without the text scrolling under the caret, and is also
    /// what the in-game HUD card can show without eliding.
    static let maximumNameLength = 12

    /// The AI's name when its seat draws its civilization at random: there is
    /// no general to name yet, because the empire is not decided until the game
    /// starts. "Random Player" - not just "Random", which read ambiguously
    /// next to the civilization row's own "Random" label right below it
    /// (Jake's ask, 2026-09-03) - and not a standing title like "Noble
    /// Strategist", which read as the general's actual name.
    static let undrawnGeneralName = "Random Player"

    /// One text size for every label in the card - header, Human/AI toggle,
    /// name field, general name, civilization row - so nothing reads as
    /// bigger or smaller than its neighbour. The "Optional" pill is the one
    /// deliberate exception (Jake's ask, 2026-09-03): it is a badge, not a
    /// line of the card's own content. Was 15pt in the first pass at this,
    /// which Jake still read as too large - dropped to 13pt, his second ask
    /// the same day. Internal, not private: `NewGameSetupView`'s Match
    /// Settings rows reuse it (his third ask) so the two sit at one size by
    /// construction rather than by two literals coincidentally agreeing.
    static let bodyTextSize: CGFloat = 13

    var body: some View {
        // Tight on purpose. Four of these have to fit above the fold alongside
        // the table size, the match settings and the status line, and at the
        // original spacing the whole configuration did not fit on a phone - the
        // match settings sat entirely below the fold on the screen whose job is
        // to show you the configuration.
        VStack(alignment: .leading, spacing: isShortScreen ? 3 : 6) {
            header
            rolePicker
            identityBlock
            civilizationBlock
        }
        .padding(isShortScreen ? 6 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TintedTextureBackground(tint: cardTint, cropWidthFraction: 0.12))
        .clipShape(FrameCornerRect(cornerRadius: Self.cornerRadius))
        .playerCardBorder(color: seatColor, cornerRadius: Self.cornerRadius, lineWidth: 1.25)
    }

    // MARK: - Seat colours

    private static let cornerRadius: CGFloat = 12

    /// The seat's identity colour: its civilization's, or gold while the
    /// civilization is still to be drawn.
    private var seatColor: Color { seat.civilization?.accentColor ?? SettingsChrome.ornamentGold }

    /// Card fill and dropdown fill reuse the same two brightness levels the
    /// in-game HUD cards already derive from a civilization
    /// (`cardBackgroundColor(active:)`) rather than introducing a third palette
    /// - so a seat's card here is recognisably the same colour as that seat's
    /// card during the game.
    private var cardTint: Color { seat.civilization?.cardBackgroundColor(active: false) ?? Self.undrawnCardTint }
    private var dropdownTint: Color { seat.civilization?.cardBackgroundColor(active: true) ?? Self.undrawnDropdownTint }

    private static let undrawnCardTint = Color(red: 0.17, green: 0.13, blue: 0.04)
    private static let undrawnDropdownTint = Color(red: 0.30, green: 0.22, blue: 0.05)

    // MARK: - Header

    /// No numbered circle badge - it duplicated the "Seat N" text right next
    /// to it, and once that text can also read "?" (turn order set to
    /// Random), a badge still pinned to the fixed seat number would
    /// contradict the very label it sits beside (Jake's ask, 2026-09-03).
    ///
    /// "Seat: N" is a tappable dropdown - opening `SeatNumberPickerPopup` to
    /// swap this seat's turn-order position with another's - whenever the
    /// position is actually fixed (Turn Order "As Shown"). Under Random it
    /// is a plain locked "Seat: ?": no position is decided yet, so there is
    /// nothing here to edit (Jake's ask, 2026-09-03).
    private var header: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(seatColor)
                .frame(width: 6, height: 6)
            if seatOrderIsRandom {
                Text("Seat: ?")
                    .font(.system(size: Self.bodyTextSize, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Button(action: onEditSeatNumber) {
                    HStack(spacing: 2) {
                        Text("Seat: \(seat.index + 1)")
                            .font(.system(size: Self.bodyTextSize, weight: .semibold, design: .serif))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Seat \(seat.index + 1), edit turn order")
            }
            Spacer(minLength: 2)
            if isOptional { optionalPill }
        }
    }

    /// Tightened (10pt font down from 9, 4pt horizontal padding down from 6,
    /// no vertical padding change) after "Random Seat" - longer than "Seat
    /// N" - started losing the race for header width against this pill on
    /// seat 4, the only card both showing it and needing the longer label,
    /// so its `Text` alone hit `minimumScaleFactor` and rendered visibly
    /// smaller than the other three cards' headers (Jake's ask, 2026-09-03).
    private var optionalPill: some View {
        Text("Optional")
            .font(.system(size: 8, weight: .semibold, design: .serif))
            .foregroundStyle(SettingsChrome.ornamentGold)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(SettingsChrome.ornamentGold.opacity(0.7), lineWidth: 1))
            .fixedSize()
    }

    // MARK: - Human / AI (A1.2)

    /// The same painted segmented control the match-settings rows use.
    /// Matches `civilizationBlock`'s own vertical padding rather than the
    /// default compact padding, so the Human/AI box comes out the same
    /// height as the civilization box beneath it (Jake's ask, 2026-09-03).
    /// Refusing the last human seat (A1.3) is `NewGameSetupView`'s job, not
    /// this row's: the rule is about the *table*, and a card cannot see the
    /// other three.
    private var rolePicker: some View {
        PaintedChoiceRow(
            options: [true, false],
            title: { $0 ? "Human" : "AI" },
            selection: seat.isHuman,
            verticalPadding: civilizationRowVerticalPadding,
            fontSize: Self.bodyTextSize,
            onSelect: onSetHuman
        )
    }

    // MARK: - Identity (A2)

    /// A human seat gets a name field; an AI seat gets its general's name and
    /// no field at all (A2.7). Both branches are pinned to the same height so
    /// that a row holding one of each still has two cards of equal height -
    /// a `LazyVGrid` row is as tall as its tallest cell, and an unpinned AI
    /// card left a visible gap under its shorter label.
    @ViewBuilder
    private var identityBlock: some View {
        // No caption. A text field with an "Enter name" prompt does not need a
        // label reading "Name", and an AI seat's general is identified by the
        // civilization row directly beneath it. Three captions per card is
        // ~96pt across the grid, which is most of what pushed the match
        // settings off screen.
        VStack(alignment: .leading, spacing: 4) {
            if seat.isHuman {
                nameField
            } else {
                Text(seat.civilization?.generalName ?? Self.undrawnGeneralName)
                    .font(.system(size: Self.bodyTextSize, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    // Left padding to match `nameField`'s own horizontal
                    // inset (9pt) just above it in a human seat's card - the
                    // AI general's name sat flush against the card edge
                    // while the human's name field didn't (Jake's ask,
                    // 2026-09-03).
                    .padding(.leading, 9)
                    .frame(maxWidth: .infinity, minHeight: identityRowHeight, alignment: .leading)
            }
        }
    }

    private var identityRowHeight: CGFloat { isShortScreen ? 26 : 32 }

    /// Shared by `rolePicker` and `civilizationBlock` so the Human/AI box and
    /// the civilization box come out the same height (Jake's ask,
    /// 2026-09-03).
    private var civilizationRowVerticalPadding: CGFloat { isShortScreen ? 4 : 7 }

    private var nameField: some View {
        TextField("", text: nameBinding, prompt: Text("Enter name").foregroundColor(.white.opacity(0.35)))
            .textFieldStyle(.plain)
            .font(.system(size: Self.bodyTextSize, weight: .semibold, design: .serif))
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(.horizontal, 9)
            .frame(height: identityRowHeight)
            .background(PaintedChromeBackground(fill: .color(Self.fieldFill), cornerRadius: 8, notchScale: 0.45))
            .accessibilityIdentifier(AccessibilityID.NewGame.seatName(seat.index))
    }

    private static let fieldFill = Color(red: 0.03, green: 0.06, blue: 0.10)

    /// A2.5 is enforced *here*, at the keystroke: anything past the limit is
    /// dropped before it ever reaches the setup, so there is no over-long name
    /// for a later check to have to reject or a label to have to truncate.
    private var nameBinding: Binding<String> {
        Binding(
            get: { seat.name },
            set: { onRename(String($0.prefix(Self.maximumNameLength))) }
        )
    }

    // MARK: - Civilization (A3)

    private var civilizationBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onEditCivilization) {
                HStack(spacing: 7) {
                    civilizationMark
                    Text(seat.civilization?.displayName ?? "Random")
                        .font(.system(size: Self.bodyTextSize, weight: .semibold, design: .serif))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, civilizationRowVerticalPadding)
                .background(PaintedChromeBackground(fill: .tintedTexture(dropdownTint), cornerRadius: 8, notchScale: 0.45))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Seat \(seat.index + 1) civilization, \(seat.civilization?.displayName ?? "Random")")
        }
    }

    /// The same painted settlement the chosen civilization will place on the
    /// board. Random remains a question mark because no identity exists yet;
    /// a die implied the game would keep rerolling it.
    @ViewBuilder
    private var civilizationMark: some View {
        if let civilization = seat.civilization {
            CivilizationCrest(civilization: civilization, size: 20)
        } else {
            Image(systemName: "questionmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(SettingsChrome.ornamentGold)
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(SettingsChrome.ornamentGold, lineWidth: 1.5))
        }
    }

}

#Preview {
    ZStack {
        SettingsChrome.screenBackground.ignoresSafeArea()
        HStack(spacing: 10) {
            SeatCardView(
                seat: MatchSetup.Seat(index: 0, isHuman: true, name: "Alex", civilization: .greece),
                isOptional: false,
                onSetHuman: { _ in },
                onRename: { _ in },
                onEditCivilization: {}
            )
            SeatCardView(
                seat: MatchSetup.Seat(index: 3, isHuman: false, name: "", civilization: nil),
                isOptional: true,
                onSetHuman: { _ in },
                onRename: { _ in },
                onEditCivilization: {}
            )
        }
        .padding(.horizontal, 20)
        .frame(width: 375)
    }
    .foregroundStyle(.white)
}
