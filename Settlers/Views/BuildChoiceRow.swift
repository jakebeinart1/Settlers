import SwiftUI
import CatanEngine

/// Construction-specific plaques keep disabled labels readable while making
/// availability unmistakable through fill, a state symbol and plain language.
/// Other popup rows retain their existing GoldRowButton appearance.
struct BuildChoiceRow: View {
    let presentation: BuildActionPresentation
    let identity: PlayerIdentity
    let action: () -> Void

    private static let readyFill = Color(red: 0.12, green: 0.29, blue: 0.24)
    private static let unavailableFill = Color(red: 0.17, green: 0.19, blue: 0.21)
    private static let mutedText = Color(red: 0.76, green: 0.80, blue: 0.81)
    private static let shortage = Color(red: 0.98, green: 0.70, blue: 0.61)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                header
                if !presentation.costs.isEmpty { costs }
                if let flexibleCost = presentation.flexibleCost {
                    Text(flexibleCost).font(.caption.weight(.semibold))
                }
                if let detail = presentation.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(presentation.isEnabled ? CatanTheme.onWaterText : Self.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let inventory = presentation.inventoryDetail {
                    Text(inventory).font(.caption).foregroundStyle(Self.mutedText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(PaintedChromeBackground(
                fill: presentation.isEnabled ? .tintedTexture(Self.readyFill) : .color(Self.unavailableFill), cornerRadius: 10
            ))
            // Put semantics on the fitting label consumed by the native
            // button. Outer composite metadata was lost across ViewThatFits.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.title)
            .accessibilityValue(presentation.accessibilityValue)
            .accessibilityIdentifier(presentation.kind.accessibilityIdentifier)
        }
        .buttonStyle(BuildChoiceButtonStyle())
        .disabled(!presentation.isEnabled)
        .accessibilityIdentifier(presentation.kind.accessibilityIdentifier)
        .accessibilityHint(presentation.isEnabled ? "Begin this action" : "")
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                title.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                stateLabel
            }
            VStack(alignment: .leading, spacing: 5) {
                title
                stateLabel
            }
        }
    }

    private var title: some View {
        HStack(spacing: 8) {
            icon
            Text(presentation.title)
                .font(.subheadline.bold())
                .foregroundStyle(presentation.isEnabled ? CatanTheme.onWaterText : Self.mutedText)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.remaining)
                .font(.caption)
                .foregroundStyle(Self.mutedText)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if presentation.kind == .ship {
            NavalShipBadge(color: identity.civilization.accentColor, civilization: identity.civilization)
                .frame(width: 30, height: 30)
                .saturation(presentation.isEnabled ? 1 : 0)
        } else {
            Image(systemName: presentation.kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(presentation.isEnabled ? CatanTheme.chipGold : Self.mutedText)
        }
    }

    private var stateLabel: some View {
        Label(presentation.status, systemImage: presentation.isEnabled ? "checkmark.circle.fill" : "lock.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(presentation.isEnabled ? CatanTheme.chipGold : Self.mutedText)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var costs: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { costTokens }
                .fixedSize(horizontal: true, vertical: false)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), alignment: .leading)], alignment: .leading, spacing: 6) {
                costTokens
            }
        }
    }

    private var costTokens: some View {
        ForEach(presentation.costs) { cost in
            HStack(spacing: 4) {
                ResourceSquare(resource: cost.resource, size: 18)
                Text("\(cost.held)/\(cost.required)")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                if cost.missing > 0 {
                    Image(systemName: "minus.circle.fill").font(.caption2)
                }
            }
            .foregroundStyle(cost.missing > 0 ? Self.shortage : CatanTheme.onWaterText)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                cost.missing > 0 ? Self.shortage.opacity(0.7) : .white.opacity(0.14), lineWidth: 1
            ))
        }
    }
}

/// Native plain styling can fade the whole disabled plaque. Keep its labels
/// and shortage counts at their designed contrast instead.
private struct BuildChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.9 : 1)
    }
}

extension BuildActionPresentation.Kind {
    var accessibilityIdentifier: String {
        switch self {
        case .ship: return "build.ship"
        case .road: return AccessibilityID.Build.road
        case .settlement: return AccessibilityID.Build.settlement
        case .city: return AccessibilityID.Build.city
        case .devCard: return AccessibilityID.Build.devCard
        case .armyCard: return AccessibilityID.Build.armyCard
        case .deployArmy: return AccessibilityID.Build.deployArmy
        }
    }

    var systemImage: String {
        switch self {
        case .ship: return "sailboat.fill"
        case .road: return "line.diagonal"
        case .settlement: return "house.fill"
        case .city: return "building.2.fill"
        case .devCard: return "rectangle.stack.fill"
        case .armyCard: return "shield.lefthalf.filled"
        case .deployArmy: return "flag.fill"
        }
    }
}
