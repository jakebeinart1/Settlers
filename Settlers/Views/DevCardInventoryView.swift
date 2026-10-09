import SwiftUI
import CatanEngine

/// A compact selector: the selected detail owns effect and timing copy.
/// Repeating full faces consumed the space needed for resource choices.
struct DevCardInventoryTile: View {
    let item: DevCardInventoryItem
    let isSelected: Bool
    var maximumWidth: CGFloat = .infinity
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                DevCardEmblem(type: item.type).frame(width: 28, height: 28)
                Text(DevCardStyle.fullName(for: item.type))
                    .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text("×\(item.held)").font(.subheadline.bold()).monospacedDigit().fixedSize()
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? maximumWidth - 24 : nil)
            .fontDesign(.serif)
            .foregroundStyle(DevCardChrome.ivory)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(minHeight: 44)
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

/// The existing 54×44 footprint keeps the board viewport stable. Availability
/// stays in spoken status and full details, rather than a third tiny title.
struct DevCardHandBadge: View {
    let item: DevCardInventoryItem
    let action: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Button(action: action) {
                HUDCardLabel(title: DevCardStyle.shortName(for: item.type), count: item.held) {
                    DevCardEmblem(type: item.type)
                }
                .foregroundStyle(DevCardChrome.ivory)
                .frame(width: 58, height: HUDCardMetrics.height)
                .background { DevCardChrome.background(item.type).padding(.vertical, -HUDCardMetrics.tileBleed) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(DevCardStyle.fullName(for: item.type)), \(item.held) owned")
            .accessibilityValue(DevCardDisplay.accessibilityValue(item))
            .accessibilityIdentifier(AccessibilityID.DevCards.tile(item.type))
            HUDCardCountFrame(identifier: "dev-cards.hud-count.\(item.type.rawValue)")
        }
    }
}

/// Fixed slots put all private-hand counts on one baseline. Compact shortcuts
/// remain fixed at accessibility sizes; the opened inspection surface scales.
enum HUDCardMetrics {
    static let height: CGFloat = 44
    static let iconHeight: CGFloat = 16
    static let titleHeight: CGFloat = 11
    static let countHeight: CGFloat = 17
    /// How far a tile's painted background reaches past its 44pt slot, top
    /// and bottom. The slot stays 44pt so the panel (and so the board) never
    /// changes height; only the frame grows, so the emblem and count stop
    /// touching its edge (Jake, 2026-10-09: "crammed ... on the edge").
    static let tileBleed: CGFloat = 4
    /// Width of the fade at the hand row's right edge.
    static let scrollFade: CGFloat = 24
}

struct HUDCardLabel<Icon: View>: View {
    let title: String
    let count: Int
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 0) {
            icon.frame(width: 18, height: HUDCardMetrics.iconHeight)
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .serif))
                .frame(height: HUDCardMetrics.titleHeight)
            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .serif))
                .monospacedDigit()
                .frame(height: HUDCardMetrics.countHeight)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 3)
    }
}

/// A Debug sibling leaf measures layout without becoming an accessibility
/// ancestor of the real button or changing the button's spoken content.
struct HUDCardCountFrame: View {
    let identifier: String

    var body: some View {
#if DEBUG
        Color.clear.frame(height: HUDCardMetrics.countHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hand count frame")
            .accessibilityIdentifier(identifier)
            .accessibilityRespondsToUserInteraction(false)
            .allowsHitTesting(false)
#endif
    }
}
