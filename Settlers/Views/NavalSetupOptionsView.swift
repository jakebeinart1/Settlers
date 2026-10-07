import SwiftUI
import CatanEngine

/// The two independent maritime rules are selected before the match starts;
/// they remain match-scoped through Restart and cold resume.
struct NavalSetupOptionsView: View {
    @Binding var options: NavalOptions

    var body: some View {
        VStack(spacing: 8) {
            option("Mist", subtitle: "Home starts charted. Settlements and ships reveal within two hexes. Discoveries stay public.",
                   value: $options.fogEnabled, identifier: "new-game.naval.fog")
            option("Resource islands", subtitle: "Numbered harvest fields let a settlement choose 1 resource or a city choose 2 when their number rolls.",
                   value: $options.resourceChoiceEnabled, identifier: "new-game.naval.resources")
        }
        .padding(.vertical, 4)
    }

    private func option(_ title: String, subtitle: String,
                        value: Binding<Bool>, identifier: String) -> some View {
        GoldRowButton(title: "\(title) · \(value.wrappedValue ? "On" : "Off")", subtitle: subtitle,
            systemImage: value.wrappedValue ? "checkmark.circle.fill" : "circle",
            iconColor: CatanTheme.cityPennantGold,
            action: { value.wrappedValue.toggle() })
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(title)
            .accessibilityValue(value.wrappedValue ? "On" : "Off")
            .accessibilityHint(subtitle)
            .accessibilityAddTraits(value.wrappedValue ? .isSelected : [])
            // Match the editor's deliberately bounded help typography. At
            // unbounded AX sizes a single explanatory toggle exceeded the
            // entire viewport, so even scrolling could not reveal it whole.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}
