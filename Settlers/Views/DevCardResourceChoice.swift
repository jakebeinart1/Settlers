import SwiftUI
import CatanEngine

/// Stock is optional: Monopoly takes from rivals and must not advertise bank
/// quantities. Plenty supplies real stock and its existing legality mask.
struct DevCardResourceChoice: View {
    let resource: Resource
    let count: Int?
    let isEnabled: Bool
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ResourceSquare(resource: resource, size: 28)
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DevCardChrome.ink, DevCardChrome.gold)
                                .font(.system(size: 12)).offset(x: 4, y: 3)
                        }
                    }
                Text(resource.rawValue.capitalized).font(.caption2.weight(.semibold))
                if let count { Text("\(count) left").font(.caption2).monospacedDigit() }
            }
            .fontDesign(.serif)
            .foregroundStyle(DevCardChrome.ivory)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? DevCardChrome.gold.opacity(0.18) : DevCardChrome.ink.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? DevCardChrome.gold : DevCardChrome.gold.opacity(0.3),
                              lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(DevCardResourceButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(resource.rawValue.capitalized)
        .accessibilityValue(count.map { "\($0) in the bank" } ?? (isSelected ? "Selected" : "Not selected"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Availability belongs to the control environment. Styling it here updates
/// even when a tap disables its own button while the label is being tracked.
private struct DevCardResourceButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(isEnabled ? (configuration.isPressed ? 0.9 : 1) : 0.38)
    }
}

/// Two explicit places for the two bank cards. Empty places are informational;
/// filled places remove one pick, including one of two identical resources.
struct DevCardPickSlot: View {
    let resource: Resource?
    let identifier: String
    let onRemove: () -> Void

    var body: some View {
        if let resource {
            Button(action: onRemove) {
                HStack(spacing: 6) {
                    ResourceSquare(resource: resource, size: 20)
                    Text(resource.rawValue.capitalized).font(.caption.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: "minus.circle.fill").foregroundStyle(DevCardChrome.gold)
                }
                .foregroundStyle(DevCardChrome.ivory)
                .padding(9).frame(maxWidth: .infinity, minHeight: 44)
                .background(DevCardChrome.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove one \(resource.rawValue.capitalized)")
            .accessibilityIdentifier(identifier)
        } else {
            Text("Choose a resource")
                .font(.caption).foregroundStyle(DevCardChrome.ivory.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(9).frame(maxWidth: .infinity, minHeight: 44)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(DevCardChrome.gold.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
    }
}
