import SwiftUI
import CatanEngine

/// Raise an army card, paying exactly the cards the player picks. Built from
/// the same pieces as Year of Plenty's chooser - `ResourceSlotRow` for what is
/// staged, `ResourceChip`s for the hand, on a painted plaque - so the two
/// resource choices in the game look and behave alike.
struct ArmyPurchasePopupView: View {
    let viewModel: GameViewModel
    let onDismiss: () -> Void

    @State private var paying: [Resource: Int] = [:]
    @State private var errorMessage: String?

    var body: some View {
        let state = viewModel.state
        let me = viewModel.humanPlayer
        let hand = state.players.first { $0.id == me }?.resources ?? [:]
        let price = state.armyPrice
        let isValid = Conquest.isValidPayment(paying, price: price, hand: hand) && !state.armyDeck.isEmpty

        PopupCard(onDismiss: onDismiss) {
            VStack(spacing: 12) {
                Text("Raise an army").font(.headline)
                Text("Pay \(price.label) · \(state.armyDeck.count) cards left in the deck")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose what to pay")
                        .font(.caption.bold())
                        .foregroundStyle(SettingsChrome.ornamentGold)
                    ResourceSlotRow(counts: paying) { resource in
                        paying[resource] = max(0, (paying[resource] ?? 0) - 1)
                        if paying[resource] == 0 { paying[resource] = nil }
                    }
                    HStack(spacing: 8) {
                        ForEach(Resource.allCases, id: \.self) { resource in
                            let left = (hand[resource] ?? 0) - (paying[resource] ?? 0)
                            ResourceChip(resource: resource, count: left, isEnabled: left > 0 && canAddMore(price)) {
                                paying[resource, default: 0] += 1
                            }
                            .accessibilityIdentifier(AccessibilityID.Army.payment(resource))
                        }
                    }
                }
                .padding(10)
                .background(PaintedChromeBackground(fill: .color(SettingsChrome.plaqueFill), cornerRadius: 10))

                GoldRowButton(
                    title: "Raise army card",
                    systemImage: "shield.lefthalf.filled",
                    iconColor: .red,
                    isEnabled: isValid,
                    action: raise
                )
                .accessibilityIdentifier(AccessibilityID.Army.raise)
                if let errorMessage {
                    Text(errorMessage).font(.caption2).foregroundStyle(.red)
                }
                GoldRowButton(title: "Close", systemImage: "xmark", action: onDismiss)
            }
            .padding(16)
            .frame(maxWidth: 340)
        }
    }

    /// Any-N prices stop accepting cards at N; one-of-each is checked on Raise.
    private func canAddMore(_ price: ArmyPrice) -> Bool {
        guard let count = Conquest.payment(for: [.brick: 9, .lumber: 9, .wool: 9, .grain: 9, .ore: 9], price: price)?
            .values.reduce(0, +) else { return true }
        return paying.values.reduce(0, +) < count
    }

    private func raise() {
        do {
            try viewModel.apply(.buyArmyCard(paying: paying))
            paying = [:]
            errorMessage = nil
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
