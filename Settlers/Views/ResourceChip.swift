import SwiftUI
import CatanEngine

/// Shared little "resource chip" button - icon, optional count badge,
/// resource-colored rounded square - used by every give/want/discard-style
/// popup (`TradePopupView`, `DiscardPopupView`) so their hand trays/slots
/// look and behave the same.
struct ResourceChip: View {
    let resource: Resource
    let count: Int?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: CatanTheme.symbolName(for: resource))
                    .font(.callout)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(CatanTheme.color(for: resource), in: RoundedRectangle(cornerRadius: 8))
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
