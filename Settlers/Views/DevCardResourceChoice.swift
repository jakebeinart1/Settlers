import SwiftUI
import CatanEngine

/// The same resource control names the actual source of its quantity: Plenty
/// draws from the bank, while Monopoly collects the public aggregate in rivals' hands.
struct DevCardResourceChoice: View {
    let resource: Resource
    let quantity: DevCardResourceQuantity
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
                if let count = quantity.count {
                    Text("\(count)").font(.caption.weight(.semibold)).monospacedDigit()
                }
                Text(quantity.caption).font(.caption2).multilineTextAlignment(.center)
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
        .accessibilityValue(quantity.accessibilityValue + (isSelected ? ", Selected" : ""))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

enum DevCardResourceQuantity {
    case bank(Int)
    case rivals(Int?)

    var count: Int? {
        switch self {
        case .bank(let count): count
        case .rivals(let count): count
        }
    }

    var caption: String {
        switch self {
        case .bank: "in bank"
        case .rivals(let count): count == nil ? "Amount unknown" : "to collect"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .bank(let count): "\(count) in the bank"
        case .rivals(let count): count.map { "\($0) available to collect from rivals" } ?? "Amount available from rivals unknown"
        }
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
