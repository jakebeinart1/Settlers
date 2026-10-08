import SwiftUI
import CatanEngine

/// This optional rule belongs to the match contract, beside discovery and
/// harvest choices. Its consequence stays visible beside its On/Off value.
struct NavalShipStealingOptionView: View {
    @Binding var options: NavalOptions
    private let explanation = "When enabled, on an 11, after collecting resources, take control of one rival ship anywhere or skip. "
        + "It keeps its location and stays with its new owner until stolen again."

    var body: some View {
        GoldRowButton(title: "Ship stealing · \(options.shipStealingEnabled ? "On" : "Off")",
                      subtitle: explanation,
                      systemImage: options.shipStealingEnabled ? "checkmark.circle.fill" : "circle",
                      iconColor: CatanTheme.cityPennantGold,
                      action: { options.shipStealingEnabled.toggle() })
            .buttonStyle(.plain)
            .accessibilityIdentifier("new-game.naval.ship-stealing")
            .accessibilityLabel("Ship stealing")
            .accessibilityValue(options.shipStealingEnabled ? "On" : "Off")
            .accessibilityHint(explanation)
            .accessibilityAddTraits(options.shipStealingEnabled ? .isSelected : [])
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
