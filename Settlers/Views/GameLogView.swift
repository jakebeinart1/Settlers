import SwiftUI

/// Scrollable recent-events list, reading `state.log` (populated by
/// `RulesEngine.apply`). Shows most-recent-first and auto-scrolls to the
/// newest entry as the log grows.
public struct GameLogView: View {
    public let log: [String]

    public init(log: [String]) {
        self.log = log
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(log.enumerated()), id: \.offset) { index, entry in
                        Text(entry)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .onChange(of: log.count) {
                guard let lastIndex = log.indices.last else { return }
                withAnimation {
                    proxy.scrollTo(lastIndex, anchor: .bottom)
                }
            }
        }
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    GameLogView(log: [
        "You placed a settlement",
        "You placed a road",
        "Player 1 placed a settlement",
        "You rolled 8",
        "You built a road",
    ])
    .frame(height: 120)
    .padding()
    .background(Color.black)
}
