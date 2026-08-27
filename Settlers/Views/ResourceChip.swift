import SwiftUI
import CatanEngine

/// Shared little "resource chip" button - just the resource-colored
/// rounded square (plus an optional count overlaid on it) - used by every
/// give/want/discard-style popup (`TradePopupView`, `DiscardPopupView`,
/// `DevCardPopupView`'s Monopoly/Year of Plenty picker) so their hand
/// trays/slots look and behave the same. No icon, no resource name
/// anywhere - the color alone is the app's one consistent way to identify
/// a resource at a glance, matching `HumanPlayerPanel`'s resource row and
/// `IncomingTradeCardView`'s offer dots. A rounded square, not a circle -
/// matches the resource swatches everywhere else in the app (main menu
/// title block, the board's own resource counts, `BuildPopupView`'s cost
/// dots) - see the "rounded squares over circles" ask in chat.
struct ResourceChip: View {
    let resource: Resource
    let count: Int?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(CatanTheme.color(for: resource))
                if let count {
                    Text("\(count)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 36, height: 36)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// One slot row (Give/Want/Discard): a chip per resource currently in that
/// slot, tap to remove one unit back out. `emptyText` shows instead while
/// the slot is empty.
struct ResourceSlotRow: View {
    let counts: [Resource: Int]
    let emptyText: String
    let onTap: (Resource) -> Void

    var body: some View {
        HStack(spacing: 8) {
            let entries = Resource.allCases.filter { (counts[$0] ?? 0) > 0 }
            if entries.isEmpty {
                Text(emptyText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.self) { resource in
                    ResourceChip(resource: resource, count: counts[resource]) { onTap(resource) }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 40)
    }
}
