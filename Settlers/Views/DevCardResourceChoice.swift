import SwiftUI
import CatanEngine

/// The development-card chooser draws the same resource squares as trade and
/// the HUD. Counts and legality are supplied by the existing card overlay,
/// never inferred here.
struct DevCardResourceChoice: View {
    let resource: Resource
    let count: Int
    let isEnabled: Bool
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ResourceSquare(resource: resource, size: 32)
                Group {
                    Text(resource.rawValue.capitalized).font(.caption2)
                    Text("\(count)").font(.caption.bold())
                }
                .opacity(isEnabled ? 1 : 0.5)
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
        .buttonStyle(UndimmedButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel("\(count) \(resource.rawValue)")
    }
}
