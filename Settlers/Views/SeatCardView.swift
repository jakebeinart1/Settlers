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
/// by 20pt each side and puts a 10pt gutter between the columns, so a card is
/// (375 - 40 - 10) / 2 = 162.5pt wide, and 142.5pt inside its own 10pt padding.
/// Every measurement below is chosen against 142.5pt:
///
/// - Header: 22pt badge + 5 + 6pt dot + 5 + "Seat 4" at 13pt serif (~38pt) + an
///   "Optional" pill (~48pt) = ~124pt, leaving ~18pt of slack.
/// - Civilization row: 13pt glyph + 7 + "Britannia" at 14pt serif (~62pt) +
///   chevron + 20pt padding = ~115pt.
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

    /// A2.5: a name has a maximum length, enforced at input rather than by
    /// truncating at display. Twelve characters is what fits the 142.5pt field
    /// at 15pt serif without the text scrolling under the caret, and is also
    /// what the in-game HUD card can show without eliding.
    static let maximumNameLength = 12

    /// The AI's name when its seat draws its civilization at random: there is
    /// no general to name yet, because the empire is not decided until the game
    /// starts. A neutral standing title rather than "Random General", which
    /// reads as the general's actual name.
    static let undrawnGeneralName = "Noble Strategist"

    var body: some View {
        // Tight on purpose. Four of these have to fit above the fold alongside
        // the table size, the match settings and the status line, and at the
        // original spacing the whole configuration did not fit on a phone - the
        // match settings sat entirely below the fold on the screen whose job is
        // to show you the configuration.
        VStack(alignment: .leading, spacing: 6) {
            header
            rolePicker
            identityBlock
            civilizationBlock
        }
        .padding(8)
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

    private var header: some View {
        HStack(spacing: 5) {
            numberBadge
            Circle()
                .fill(seatColor)
                .frame(width: 6, height: 6)
            Text("Seat \(seat.index + 1)")
                .font(.system(size: 13, weight: .semibold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 2)
            if isOptional { optionalPill }
        }
    }

    private var numberBadge: some View {
        Text("\(seat.index + 1)")
            .font(.system(size: 12, weight: .bold, design: .serif))
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(seatColor, lineWidth: 1.25))
    }

    private var optionalPill: some View {
        Text("Optional")
            .font(.system(size: 9, weight: .semibold, design: .serif))
            .foregroundStyle(SettingsChrome.ornamentGold)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(SettingsChrome.ornamentGold.opacity(0.7), lineWidth: 1))
            .fixedSize()
    }

    // MARK: - Human / AI (A1.2)

    /// The same painted segmented control the match-settings rows use. Refusing
    /// the last human seat (A1.3) is `NewGameSetupView`'s job, not this row's:
    /// the rule is about the *table*, and a card cannot see the other three.
    private var rolePicker: some View {
        PaintedChoiceRow(
            options: [true, false],
            title: { $0 ? "Human" : "AI" },
            selection: seat.isHuman,
            isCompact: true,
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
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, minHeight: Self.identityRowHeight, alignment: .leading)
            }
        }
    }

    private static let identityRowHeight: CGFloat = 32

    private var nameField: some View {
        TextField("", text: nameBinding, prompt: Text("Enter name").foregroundColor(.white.opacity(0.35)))
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .semibold, design: .serif))
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(.horizontal, 9)
            .frame(height: Self.identityRowHeight)
            .background(PaintedChromeBackground(fill: .color(Self.fieldFill), cornerRadius: 8, notchScale: 0.45))
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
                    Image(systemName: seat.civilization?.emblemSymbol ?? "die.face.5.fill")
                        .font(.system(size: 13))
                    Text(seat.civilization?.displayName ?? "Random")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(PaintedChromeBackground(fill: .tintedTexture(dropdownTint), cornerRadius: 8, notchScale: 0.45))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Seat \(seat.index + 1) civilization, \(seat.civilization?.displayName ?? "Random")")
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
