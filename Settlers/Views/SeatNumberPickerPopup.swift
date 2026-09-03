import SwiftUI

/// The turn-order picker raised from a `SeatCardView`'s header, when Turn
/// Order is "As Shown" - Jake's ask, 2026-09-03. Only meaningful then: with
/// Turn Order set to Random, no card's position is the actual play order, so
/// there is nothing here to edit and the header shows a locked "Seat: ?"
/// instead (`SeatCardView.header`).
///
/// ## Why a swap, not a free-form reassignment
/// Every seat number 1...N is always in use exactly once - that is what "turn
/// order" means. Picking "3" for this card has to come from somewhere, so it
/// trades places with whichever card currently holds "3" rather than leaving
/// two cards claiming the same number or one number orphaned.
struct SeatNumberPickerPopup: View {
    /// 0-based, shown 1-based in the title so it matches the card it came from.
    let seatIndex: Int
    let seatCount: Int
    /// 1-based target seat number.
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        PopupCard(onDismiss: onCancel) {
            VStack(spacing: 14) {
                Text("Seat \(seatIndex + 1) Turn Order")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                Text("Swap this seat's turn order with:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                numberRow
                GoldRowButton(title: "Close", systemImage: "xmark", action: onCancel)
            }
            .padding(16)
            .foregroundStyle(.white)
        }
    }

    private var numberRow: some View {
        HStack(spacing: 10) {
            ForEach(1...seatCount, id: \.self) { number in
                numberButton(number)
            }
        }
    }

    /// The card's own current number is shown but disabled (A3.3's "never
    /// grey out the current choice" pattern doesn't apply here - swapping a
    /// seat with itself is a no-op, not a valid alternative to offer).
    private func numberButton(_ number: Int) -> some View {
        let isCurrent = number == seatIndex + 1
        return Button {
            onSelect(number)
        } label: {
            Text("\(number)")
                .font(.system(size: 18, weight: .bold, design: .serif))
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(isCurrent ? SettingsChrome.selectedOptionFill : Color.black.opacity(0.3))
                )
                .overlay(Circle().strokeBorder(SettingsChrome.ornamentGold, lineWidth: isCurrent ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .accessibilityLabel(isCurrent ? "Seat \(number), current position" : "Swap to seat \(number)")
    }
}

#Preview {
    ZStack {
        SettingsChrome.screenBackground.ignoresSafeArea()
        SeatNumberPickerPopup(seatIndex: 0, seatCount: 4, onSelect: { _ in }, onCancel: {})
    }
}
