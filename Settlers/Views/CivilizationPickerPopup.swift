import SwiftUI

/// The seat civilization picker raised from a `SeatCardView`'s dropdown.
///
/// ## Why a grid, and why it does not scroll
/// A3.4 requires every civilization to be reachable "without the list running
/// off the screen", with any scrolling visibly indicated. That criterion exists
/// because of a specific complaint about `SettingsView`, which lists the eight
/// civilizations as full-width rows inside a `ScrollView` with no scroll
/// indicator and no visual hint - three of the eight are simply below the fold,
/// and a player who never dragged would not know they existed.
///
/// Three columns of eight cells is 3 + 3 + 2, about 200pt tall, which fits on
/// the shortest screen this app supports (375 x 667, iPhone SE) alongside the
/// title, the Random row and Close with room to spare. Nothing scrolls, so
/// there is nothing to indicate.
///
/// ## Why "Random" is a row rather than a ninth cell
/// It is not a civilization; it is the absence of a choice
/// (`MatchSetup.Seat.civilization == nil`, A3.5). Putting it in the grid makes
/// it read as a ninth empire, which is exactly the confusion the separate row
/// avoids.
struct CivilizationPickerPopup: View {
    /// 0-based, shown 1-based in the title so it matches the card it came from.
    let seatIndex: Int
    let selection: Civilization?
    /// Civilizations another seat already holds (A3.3). Comes from
    /// `MatchSetup.civilizationsTaken(excluding:)`, which excludes this seat's
    /// own pick - so re-opening the picker never greys out the current choice.
    let taken: Set<Civilization>
    let onSelect: (Civilization?) -> Void
    let onCancel: () -> Void

    private static let columnCount = 3
    private static let cellSpacing: CGFloat = 8

    var body: some View {
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                Text("Seat \(seatIndex + 1) Civilization")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                grid
                randomRow
                GoldRowButton(title: "Close", systemImage: "xmark", action: onCancel)
            }
            .padding(16)
            .foregroundStyle(.white)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Self.cellSpacing),
                count: Self.columnCount
            ),
            spacing: Self.cellSpacing
        ) {
            ForEach(Civilization.allCases, id: \.self) { civilization in
                cell(civilization)
            }
        }
    }

    /// One civilization. A taken one is dimmed, marked, and not tappable -
    /// visibly unavailable rather than silently ignoring the tap, which reads
    /// as a broken button.
    private func cell(_ civilization: Civilization) -> some View {
        let isTaken = taken.contains(civilization)
        let isSelected = civilization == selection
        return Button {
            onSelect(civilization)
        } label: {
            VStack(spacing: 4) {
                CivilizationBadge(civilization: civilization, isCity: false, size: 30)
                    .overlay(alignment: .topTrailing) {
                        if isTaken {
                            Image(systemName: "nosign")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                Text(civilization.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(cellBackground(civilization, isSelected: isSelected))
            .opacity(isTaken ? 0.35 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isTaken)
        .accessibilityIdentifier(AccessibilityID.NewGame.civilizationOption(civilization))
        .accessibilityLabel(isTaken ? "\(civilization.displayName), taken by another seat" : civilization.displayName)
    }

    /// Opaque, not a translucent tint: `PopupCard`'s own panel is a fairly
    /// bright blue, and a half-transparent swatch over it came out reading
    /// blue for every civilization whose colour is not strongly saturated -
    /// Aztec, Columbia and Norse were indistinguishable in the first
    /// simulator screenshot. The two brightness levels are the same ones the
    /// in-game HUD cards use, so a civilization looks here as it will there.
    private func cellBackground(_ civilization: Civilization, isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(civilization.cardBackgroundColor(active: isSelected))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isSelected ? SettingsChrome.ornamentGold : civilization.accentColor.opacity(0.45),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
    }

    /// A3.5. `nil` means "draw one at start from whatever is still free", which
    /// is why it can never conflict with another seat and is always offered.
    private var randomRow: some View {
        GoldRowButton(
            title: "Random",
            subtitle: "Drawn at the start from the civilizations still free",
            // A question mark, not a die - matches `SeatCardView`'s own
            // undrawn-civilization icon (Jake's ask, 2026-09-03): a die reads
            // as "rolled for during the game", when this is actually a
            // one-time draw at the start that then stays fixed.
            systemImage: "questionmark.circle.fill",
            iconColor: SettingsChrome.ornamentGold,
            trailing: {
                if selection == nil {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(SettingsChrome.ornamentGold)
                }
            },
            action: { onSelect(nil) }
        )
    }
}

#Preview {
    ZStack {
        SettingsChrome.screenBackground.ignoresSafeArea()
        CivilizationPickerPopup(
            seatIndex: 1,
            selection: .rome,
            taken: [.greece, .japan],
            onSelect: { _ in },
            onCancel: {}
        )
    }
}
