import SwiftUI
import CatanEngine

/// A readable private-hand charter. Blocked cards keep full contrast and a
/// working inspection action; play permission belongs to the detail surface.
struct DevCardInventoryTile: View {
    let item: DevCardInventoryItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    DevCardEmblem(type: item.type).frame(width: 48, height: 48)
                    Spacer(minLength: 0)
                    Text("×\(item.held)").font(.headline)
                }
                Text(DevCardStyle.fullName(for: item.type))
                    .font(.subheadline.bold())
                    .frame(minHeight: 38, alignment: .topLeading)
                Text(DevCardDisplay.summary(item.type)).font(.caption)
                Divider().overlay(DevCardChrome.gold.opacity(0.6))
                Text(DevCardDisplay.inventoryBadge(item))
                    .font(.caption.bold())
                if !item.status.isPlayable && item.status != .passiveVictoryPoint && item.status != .boughtThisTurn {
                    Text(DevCardStyle.statusTitle(for: item.status)).font(.caption)
                }
            }
            .fontDesign(.serif)
            .foregroundStyle(DevCardChrome.ivory)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(width: 150, alignment: .topLeading)
            .background(DevCardChrome.background(item.type))
            .overlay {
                if isSelected {
                    FrameCornerRect(cornerRadius: DevCardChrome.borderRadius, notchScale: 0.5)
                        .strokeBorder(DevCardChrome.ivory, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DevCardStyle.fullName(for: item.type)), \(item.held) owned")
        .accessibilityValue(DevCardDisplay.accessibilityValue(item))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(AccessibilityID.DevCards.tile(item.type))
    }
}

/// Additive replacement for PlayerHUDView's private DevCardHUDTile. The exact
/// 54×44 footprint preserves the hand shelf and board viewport. Full names,
/// mixed counts and disabled reasons remain available through accessibility
/// and the scalable inventory opened by the existing action.
struct DevCardHandBadge: View {
    let item: DevCardInventoryItem
    let action: () -> Void

    private enum Metrics {
        static let width: CGFloat = 54
        static let height: CGFloat = 44
        static let emblem: CGFloat = 24
        static let label: CGFloat = 8
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    DevCardEmblem(type: item.type).frame(width: Metrics.emblem, height: Metrics.emblem)
                    Text("\(item.held)").font(.system(size: 12, weight: .bold, design: .serif))
                }
                Text(DevCardStyle.shortName(for: item.type))
                    .font(.system(size: Metrics.label, weight: .bold, design: .serif))
                Text(DevCardDisplay.handBadgeStatus(item))
                    .font(.system(size: Metrics.label, weight: .bold, design: .serif))
            }
            .foregroundStyle(DevCardChrome.ivory)
            .frame(width: Metrics.width, height: Metrics.height)
            .background(DevCardChrome.background(item.type))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DevCardStyle.fullName(for: item.type)), \(item.held) owned")
        .accessibilityValue(DevCardDisplay.accessibilityValue(item))
        .accessibilityIdentifier(AccessibilityID.DevCards.tile(item.type))
    }
}
