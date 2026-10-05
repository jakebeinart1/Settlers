import SwiftUI
import CatanEngine

/// The development-card chooser uses the approved commodity illustrations,
/// while shared trade/discard ResourceChip remains unchanged. Counts and
/// legality are supplied by the existing card overlay, never inferred here.
struct DevCardResourceChoice: View {
    let resource: Resource
    let count: Int
    let isEnabled: Bool
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(CatanTheme.iconImageName(for: resource))
                    .resizable().scaledToFit()
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                Text(resource.rawValue.capitalized).font(.caption2)
                Text("\(count)").font(.caption.bold())
            }
            .fontDesign(.serif)
            .foregroundStyle(DevCardChrome.ivory)
            .padding(.vertical, 5)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .background(DevCardChrome.ink.opacity(0.6))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(DevCardChrome.gold, lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel("\(count) \(resource.rawValue)")
    }
}
