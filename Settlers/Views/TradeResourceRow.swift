import SwiftUI
import CatanEngine

/// The two editor rows share positions, words and controls. Availability is
/// attached to the resource it constrains instead of becoming another tray.
struct TradeResourceRow: View {
    let draft: TradeDraftFeedback
    let isGive: Bool
    let onAdd: (Resource) -> Void
    let onRemove: (Resource) -> Void

    static let receiveAccent = Color(red: 0.67, green: 0.91, blue: 0.80)
    private var accent: Color { isGive ? CatanTheme.chipGold : Self.receiveAccent }
    private var counts: [Resource: Int] { isGive ? draft.give : draft.receive }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(isGive ? "You give" : "You receive", systemImage: isGive ? "arrow.up.right" : "arrow.down.left")
                    .font(.headline)
                    .foregroundStyle(accent)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(isGive ? draft.giveTotal : draft.receiveTotal) selected")
                    .font(.caption)
                    .foregroundStyle(CatanTheme.onWaterText.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Equal columns keep quantities and hit targets in place as the
            // draft changes. Accessibility sizes use two wider columns.
            resourceGrid
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var resourceGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                 count: dynamicTypeSize.isAccessibilitySize ? 2 : 5), spacing: 8) {
            ForEach(Resource.allCases, id: \.self) { resource in
                cell(resource)
            }
        }
    }

    private func cell(_ resource: Resource) -> some View {
        let count = counts[resource, default: 0]
        return VStack(spacing: 2) {
            ResourceChip(resource: resource, count: count,
                         isEnabled: draft.canAdd(resource, toGive: isGive),
                         isSelected: count > 0, size: 38, appearance: .illustrated, accent: accent) {
                onAdd(resource)
            }
            .accessibilityIdentifier(addIdentifier(resource))
            .accessibilityLabel("Add \(isGive ? draft.addStep(resource) : 1) \(resource.rawValue.capitalized) to \(isGive ? "You give" : "You receive")")
            .accessibilityValue("\(count)")
            availability(resource)
            removeButton(resource, count: count)
        }
    }

    @ViewBuilder
    private func availability(_ resource: Resource) -> some View {
        if isGive {
            Text("\(draft.remaining(resource)) left")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                .accessibilityIdentifier("trade.inventory.\(resource.rawValue)")
                .accessibilityLabel("\(draft.remaining(resource)) left")
                .accessibilityHint("You hold \(draft.owned(resource)) \(resource.rawValue.capitalized) before this trade")
            if draft.isBank {
                Text("\(draft.rate(resource)):1")
                    .font(.caption2.bold())
                    .foregroundStyle(CatanTheme.chipGold)
                    .accessibilityIdentifier("trade.bank.rate.\(resource.rawValue)")
            }
        } else if draft.isBank {
            Text("\(draft.stock(resource)) stock")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CatanTheme.onWaterText.opacity(0.8))
                .accessibilityIdentifier("trade.bank.stock.\(resource.rawValue)")
                .accessibilityLabel("Bank has \(draft.stock(resource)) \(resource.rawValue.capitalized)")
        }
    }

    private func removeButton(_ resource: Resource, count: Int) -> some View {
        Button { onRemove(resource) } label: {
            Image(systemName: "minus.circle")
                .font(.system(size: 19))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .disabled(count == 0)
        .opacity(count == 0 ? 0.3 : 1)
        .accessibilityLabel("Remove \(isGive ? min(count, draft.removeStep(resource)) : 1) \(resource.rawValue.capitalized) from \(isGive ? "You give" : "You receive")")
        .accessibilityIdentifier(removeIdentifier(resource))
    }

    private func addIdentifier(_ resource: Resource) -> String {
        if draft.isBank { return isGive ? AccessibilityID.Trade.bankGive(resource) : AccessibilityID.Trade.bankGet(resource) }
        return isGive ? AccessibilityID.Trade.giveChip(resource) : AccessibilityID.Trade.wantChip(resource)
    }

    private func removeIdentifier(_ resource: Resource) -> String {
        if draft.isBank { return AccessibilityID.Trade.bankRemove(resource, fromGive: isGive) }
        return "trade.\(isGive ? "give" : "want").remove.\(resource.rawValue)"
    }
}
