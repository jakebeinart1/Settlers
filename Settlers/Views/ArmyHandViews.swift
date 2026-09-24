import SwiftUI
import CatanEngine

/// Army red, shared by every army surface (Build rows, panel tiles, the hand).
enum ArmyStyle {
    static let color = Color(red: 0.62, green: 0.16, blue: 0.14)

    static func effect(strength: Int) -> String {
        "Deploy it onto a hex your buildings touch. Against a tribe or a rival it is "
            + "subtracted from their garrison: beat it and the hex is yours, holding the "
            + "difference. On a hex you hold it adds \(strength) to your garrison."
    }
}

/// One strength in the hand strip, in `DevCardHandTile`'s shape and size.
struct ArmyHandTile: View {
    let strength: Int
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.title3)
                Text("Army \(strength)")
                    .font(.system(size: 10, weight: .bold, design: .serif))
                Text("×\(count)")
                    .font(.caption2.bold())
                Text("STRENGTH \(strength)")
                    .font(.system(size: 8, weight: .bold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(width: 70, height: 76)
            .background(RoundedRectangle(cornerRadius: 11).fill(ArmyStyle.color.opacity(0.48).gradient))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(isSelected ? SettingsChrome.ornamentGold : .white.opacity(0.28),
                                  lineWidth: isSelected ? 2.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Army card, strength \(strength), \(count) held")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(AccessibilityID.Army.handTile(strength))
    }
}

/// The selected card's art, in `DevCardArtwork`'s frame: rings, a shield, and
/// the strength large enough to read at a glance.
struct ArmyArtwork: View {
    let strength: Int?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(ArmyStyle.color.opacity(strength == nil ? 0.14 : 0.32).gradient)
            Circle()
                .stroke(SettingsChrome.ornamentGold.opacity(0.32), lineWidth: 1)
                .frame(width: 104, height: 104)
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(ArmyStyle.color.opacity(strength == nil ? 0.5 : 1))
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            if let strength {
                Text("\(strength)")
                    .font(.system(size: 30, weight: .heavy, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
        }
        .frame(height: 124)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(SettingsChrome.ornamentGold.opacity(0.7), lineWidth: 1.25)
        )
        .accessibilityHidden(true)
    }
}
